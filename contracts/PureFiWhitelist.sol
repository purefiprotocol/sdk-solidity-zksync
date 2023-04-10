pragma solidity >=0.8.0;

import "../openzeppelin-contracts-upgradeable-master/contracts/security/PausableUpgradeable.sol";
import "../openzeppelin-contracts-upgradeable-master/contracts/access/OwnableUpgradeable.sol";
import "./PureFiIssuerRegistry.sol";
import "./libraries/SignLib.sol";

contract PureFiWhitelist is PausableUpgradeable, OwnableUpgradeable, SignLib{
    
    PureFiIssuerRegistry private issuerRegistry;
    mapping (address=> mapping (uint256 => Verification)) registry;

    event AddressWhitelisted(address indexed user, uint256 indexed ruleID);
    event AddressDelisted(address indexed user, uint256 indexed ruleID);

    struct Verification{
        uint256 sessionID; //verification session ID
        uint64 verifiedOn; //verification timestamp 
        uint64 validUntil;
        address issuer;
    }
    /**
    Changelog: 
    version 1.001.002:
        - added delistMe()
    version 1.002.001
        - added ruleID based structure 
    */
    function version() public pure returns(uint32){
        // 000.000.000 - Major.minor.internal
        return 1002001;
    }

    function initialize(address _issuerRegistry) public initializer{
        __Ownable_init();
        __Pausable_init_unchained();
        issuerRegistry = PureFiIssuerRegistry(_issuerRegistry);
    }

    modifier onlyIssuer(){
        require (issuerRegistry.isValidIssuer(msg.sender), "Whitelist: sender is not a registered Issuer");
        _;
    }

    function pause() onlyOwner external {
        super._pause();
    }

    function unpause() onlyOwner external {
        super._unpause();
    }

    function whitelist(address _user, uint256 _sessionID, uint256 _ruleID, uint64 _verifiedOn, uint64 _validUntil) public onlyIssuer whenNotPaused{
        registry[_user][_ruleID] = Verification(_sessionID, _verifiedOn, _validUntil, msg.sender);
        emit AddressWhitelisted(_user,_ruleID);
    }


    /**
    * whitelist user data function that can be initiated by anybody providing valid Issuer signature
    * @param data - user verification data
    * data[0] - user address (wallet)
    * data[1] - sessionID
    * data[2] - ruleID
    * data[3] - verifiedOn
    * data[4] - validUntil
    * @param signature - Issuer signature
    */
    function whitelistUserData(uint256[] memory data, bytes memory signature) external whenNotPaused {
      address recoveredIssuer = recoverSigner(keccak256(abi.encodePacked(data[0], data[1], data[2], data[3], data[4])), signature);
      require (issuerRegistry.isValidIssuer(recoveredIssuer), "Whitelist: signer is not a registered Issuer");
      require (uint64(data[3]) < block.timestamp, "Whitelist: invalid validOn param");
      require (uint64(data[4]) >= block.timestamp, "Whitelist: invalid validUntil param");
      address _user = address(uint160(data[0]));
      uint256 _ruleID = data[2];
      registry[_user][_ruleID] = Verification(data[1], uint64(data[3]), uint64(data[4]), recoveredIssuer);
      emit AddressWhitelisted(_user,_ruleID);
    }


    /**
    * Delists individual user record from registry, specified by ruleID
    * @param _user - user to delist
    * @param _ruleID - ruleID that identifies a users record to remove
    */
    function delist(address _user, uint256 _ruleID) public onlyIssuer whenNotPaused{
        require (registry[_user][_ruleID].issuer == msg.sender, "Whitelist: only the same issuer can revoke the record");
        delete registry[_user][_ruleID];
        emit AddressDelisted(_user,_ruleID);
    }

    /**
    * delistMe() allows any user to opt out from whitelist. 
    * Useful for users that suddenly undrestood their PK is compromized 
    * and want to deassosiate address from their identity 
    * @param _ruleID - ruleID that identifies a users record to remove
    */
    function delistMe(uint256 _ruleID) external whenNotPaused { 
        if(registry[msg.sender][_ruleID].sessionID > 0){
            delete registry[msg.sender][_ruleID];
            emit AddressDelisted(msg.sender, _ruleID);
        }
    }

    /**
    * Returns true in case the _address has been verified before and verification 
    * data has been uploaded on-chain
    * @param _user - address to verify
    * @param _ruleID - verification rule
    * returns true/false
    */
    function isAddressVerified(address _user, uint256 _ruleID) external view returns(bool){
        return registry[_user][_ruleID].validUntil > block.timestamp;
    }

    /** 
    * Returns the verification data record for the user address and ruleID
    * @param _user - a user address
    * @param _ruleID - ruleID 
    * @return tuple with the following items:
        [0] - sessionID
        [1] - verified on (timestamp, seconds)
        [2] - valid until (timestamp, seconds)
        [3] - record issuer adddress
    */
    function getAddressVerificationData(address _user, uint256 _ruleID) external view returns(uint256,uint64,uint64,address){
        return (
            registry[_user][_ruleID].sessionID,
            registry[_user][_ruleID].verifiedOn,
            registry[_user][_ruleID].validUntil,
            registry[_user][_ruleID].issuer
        );
    }

}