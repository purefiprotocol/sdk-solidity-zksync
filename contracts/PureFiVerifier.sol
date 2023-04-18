// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "../openzeppelin-contracts-upgradeable-master/contracts/security/PausableUpgradeable.sol";
import "../openzeppelin-contracts-upgradeable-master/contracts/access/OwnableUpgradeable.sol";
import "../openzeppelin-contracts-master/contracts/access/Ownable.sol";
import "./libraries/SignLib.sol";
import "./PureFiWhitelist.sol";
import "./PureFiIssuerRegistry.sol";
import "./utils/ParamStorage.sol";
import "./interfaces/IPureFiVerifier.sol";

contract PureFiVerifier is OwnableUpgradeable, ParamStorage, SignLib, IPureFiVerifier{

  uint16 private constant PARAM_DEFAULT_AML_GRACETIME = 3;
  uint16 private constant PARAM_ISSUER_REGISTRY_ADDRESS = 7;
  uint16 private constant PARAM_WHITELIST_ADDRESS = 8;
  uint16 private constant PARAM_CLEANING_TOLERANCE = 10;

  mapping (uint256 => uint256) requestsProcessed; 

  event PureFiPackageProcessed(address indexed caller, uint256 session);
  event PureFiStorageClear(address indexed caller, uint256 sessions_cleared);

  function initialize(address _issuerRegistry, address _whitelist) public initializer{
    __Ownable_init();
    addressParams[PARAM_ISSUER_REGISTRY_ADDRESS] = _issuerRegistry;
    addressParams[PARAM_WHITELIST_ADDRESS] = _whitelist;
  }

    /**
    Changelog:
    version 1001001:
    version 3000001:
    * Fix purefidata for tx_type=3, add sender field
    version 4000000:
    * introduced a check for msg.sender for verification that the caller contract matches receiver or sender in type2
    * added receiver field in type1 package
    */
  function version() public pure returns(uint32){
    // 000.000.000 - Major.minor.internal
    return 4000000;
  }

  // IMPORTANT
  // _purefidata = {uint64 timestamp, bytes signature, bytes purefipackage}. 
  //      timestamp = uint64, 8 bytes,
  //      signature = bytes, 65 bytes fixed length (bytes32+bytes32+uint8)
  //      purefipackage = bytes, dynamic, remaining data
  // purefipackage = {uint8 purefipackagetype, bytes packagedata}. 
  //      purefipackagetype = uint8, 1 byte
  //      packagedata = bytes, dynamic, remaining data
  // if(purefipackagetype = 1) => packagedata = {uint256 ruleID, uint256 sessionId, address sender}
  // if(purefipackagetype = 2) => packagedata = {uint256 ruleID, uint256 sessionId, address sender, address receiver, address token, uint258 amount}
  // if(purefipackagetype = 3) => packagedata = {uint256 ruleID, uint256 sessionId, address sender, bytes payload}
  // later on we'll add purefipackagetype = 4. with non-interactive mode data, and this will go into payload

  function validateAndDecode(bytes memory _purefidata) external override returns (VerificationPackage memory package){
    (package,) = _validateAndDecode(_purefidata);
  }

  function clearStorage(uint256[] memory _sessions) external {
    uint256 cleaningTolerance = uintParams[PARAM_CLEANING_TOLERANCE];
    if(cleaningTolerance == 0)
      cleaningTolerance = 86400; //avoding param-not-inited error. this is far more then PARAM_DEFAULT_AML_GRACETIME for any blockchain
    uint256 sessionCleared=0;
    for(uint i=0;i<_sessions.length;i++){
      if(requestsProcessed[_sessions[i]] + cleaningTolerance < block.timestamp) {
        delete requestsProcessed[_sessions[i]];
        sessionCleared++;
      }
    }
    emit PureFiStorageClear(msg.sender, sessionCleared);
  }

  //compatibility with the previous version (3.000.001)
  // @Deprecated
  function validatePureFiData(bytes memory _purefidata) external returns (bytes memory, uint16) {
    (,bytes memory encodedpackage) = _validateAndDecode(_purefidata);
    return (encodedpackage, 0);
  }
  // @Deprecated
  function decodePureFiPackage(bytes memory _purefipackage) external pure returns (VerificationPackage memory){
    return _decodePureFiPackage(_purefipackage);
  }

  // ************************************ PRIVATE FUNCTIONS *****************************************
  function _validateAndDecode(bytes memory _purefidata) private returns (VerificationPackage memory, bytes memory){
    //min package size = 8+65 +1+32
    require(_purefidata.length >= (8+65+1+32), "PureFiVerifier: _purefidata too short");
    
    (uint64 timestamp, bytes memory signature, bytes memory encodedpackage) = abi.decode(_purefidata, (uint64, bytes, bytes));

    //get issuer address from the signature
    address issuer = recoverSigner(keccak256(abi.encodePacked(timestamp, encodedpackage)), signature);

    require(
      PureFiIssuerRegistry(addressParams[PARAM_ISSUER_REGISTRY_ADDRESS]).isValidIssuer(issuer), 
      "PureFi Verifier : Invalid signature"
    );

    // grace time recommended:
    // Ethereum: 10 min
    // BSC: 3 min
    require(
      timestamp + uintParams[PARAM_DEFAULT_AML_GRACETIME] > block.timestamp, 
      "PureFi Verifier : Proof validity expired"
    );

    // check for the caller contract to match package data
    VerificationPackage memory package = _decodePureFiPackage(encodedpackage);
    // check for package re-use
    require(
      requestsProcessed[package.session] == 0,
      "PureFi Verifier : This package is already processed by verifier."
    );

    //check that a contract caller matches the data in the package
    require(
      (package.to == msg.sender) || ((package.packagetype == 2 || package.packagetype == 3)&&package.from == msg.sender),
      "PureFi Verifier : Contract caller invalid" 
    );

    //store requestID to avoid replay
    requestsProcessed[package.session] = block.timestamp;
    emit PureFiPackageProcessed(msg.sender, package.session);

    return (package, encodedpackage);
  }

  function _decodePureFiPackage(bytes memory _purefipackage) private pure returns (VerificationPackage memory package){
    uint8 packagetype = uint8(_purefipackage[31]);
    if(packagetype == 1){
      (, uint256 ruleID, uint256 sessionID, address sender, address receiver) = abi.decode(_purefipackage, (uint8, uint256, uint256, address, address));
      package = VerificationPackage({
          packagetype : 1,
          session: sessionID,
          rule : ruleID,
          from : sender,
          to : receiver,
          token : address(0),
          amount : 0,
          payload : ''
        }); 
    }
    else if(packagetype == 2){
      (, uint256 ruleID, uint256 sessionID, address sender, address receiver, address token_addr, uint256 tx_amount) = abi.decode(_purefipackage, (uint8, uint256, uint256, address, address, address, uint256));
      package = VerificationPackage({
          packagetype : 2,
          rule : ruleID,
          session: sessionID,
          from : sender,
          to : receiver,
          token : token_addr,
          amount : tx_amount,
          payload : ''
        }); 
    }
    else if(packagetype == 3){
      (, uint256 ruleID, uint256 sessionID, address sender, address receiver, bytes memory payload_data) = abi.decode(_purefipackage, (uint8, uint256, uint256, address, address, bytes));
      package = VerificationPackage({
          packagetype : 3,
          rule : ruleID,
          session: sessionID,
          from : sender,
          to : receiver,
          token : address(0),
          amount : 0,
          payload : payload_data
        }); 
    } else {
      require (false, "PureFiVerifier : invalid package data");
    }
  }

  function _authorizeSetter(address _setter) internal virtual override view returns (bool){
    require(_setter == owner(), "PureFi Verifier : param setter not the owner");
    return true;
  }

}
