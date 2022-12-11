// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

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
  // if(purefipackagetype = 3) => packagedata = {uint256 ruleID, uint256 sessionId, bytes payload}
  // later on we'll add purefipackagetype = 4. with non-interactive mode data, and this will go into payload

// min size of purefidata = 8 + 65 + 1 + 32 + 32 + 20  = bytes


 struct VerificationPackage{
        uint8 packagetype;
        uint256 session;
        uint256 rule;
        address from;
        address to;
        address token;
        uint256 amount;
        bytes payload;
    }
library PureFiDataUtils{

    function decodePureFiData(bytes calldata self) public pure returns(uint64 timestamp, bytes memory signature, bytes memory package){
        require(self.length >= 158, "Incorrect purefidata pack");
        (timestamp, signature, package) = abi.decode(self, (uint64, bytes, bytes));
    }

    function decodePackage(bytes calldata _purefipackage) public pure returns (VerificationPackage memory data){
        uint256 packagetype = uint256(bytes32(_purefipackage[:32]));
    if(packagetype == 1){
      (, uint256 ruleID, uint256 sessionID, address sender) = abi.decode(_purefipackage, (uint8, uint256, uint256, address));
      return VerificationPackage({
          packagetype : 1,
          session: sessionID,
          rule : ruleID,
          from : sender,
          to : address(0),
          token : address(0),
          amount : 0,
          payload : ''
        }); 
    }
    else if(packagetype == 2){
      (, uint256 ruleID, uint256 sessionID, address sender, address receiver, address token_addr, uint256 tx_amount) = abi.decode(_purefipackage, (uint8, uint256, uint256, address, address, address, uint256));
      return VerificationPackage({
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
      (, uint256 ruleID, uint256 sessionID, bytes memory payload_data) = abi.decode(_purefipackage, (uint8, uint256, uint256, bytes));
      return VerificationPackage({
          packagetype : 3,
          rule : ruleID,
          session: sessionID,
          from : address(0),
          to : address(0),
          token : address(0),
          amount : 0,
          payload : payload_data
        }); 
    }
    require (false, "PureFiVerifier : invalid package data");
  }
}

