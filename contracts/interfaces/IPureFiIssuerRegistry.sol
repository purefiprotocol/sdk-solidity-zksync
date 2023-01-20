// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.0;

interface IPureFiIssuerRegistry{
    function register(address _issuer, bytes32 proof) external;
    function unresiger(address _issuer) external;
    function getRegistrationProof(address _issuer) external view returns(bytes32);
    function isValidIssuer(address _issuer) external view returns(bool);

}