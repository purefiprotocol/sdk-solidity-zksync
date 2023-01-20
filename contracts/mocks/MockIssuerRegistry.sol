// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";

contract MockIssuerRegistry is AccessControl {

    mapping (address=>bytes32) issuers;

    event IssuerAdded(address indexed issuer);
    event IssuerRemoved(address indexed issuer);


    function version() public pure returns(uint32){
    // 000.000.000 - Major.minor.internal
    return 1000001;
    }

    constructor(address _admin){
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    function register(address _issuer, bytes32 proof) external onlyRole(DEFAULT_ADMIN_ROLE) {
        issuers[_issuer] = proof;
        
        emit IssuerAdded(_issuer);
    }

    function unresiger(address _issuer) external onlyRole(DEFAULT_ADMIN_ROLE){
        delete issuers[_issuer];
        
        emit IssuerRemoved(_issuer);
    }

    function getRegistrationProof(address _issuer) external view returns(bytes32){
        return issuers[_issuer];
    }

    function isValidIssuer(address _issuer) external view returns(bool){
        return (issuers[_issuer] != 0);
    }
}