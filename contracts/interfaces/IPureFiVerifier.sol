// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

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

interface IPureFiVerifier{

    function validatePureFiData(bytes memory _purefidata) external view returns (bytes memory, uint16);
    function decodePureFiPackage(bytes memory _purefipackage) external view returns (VerificationPackage memory);
}