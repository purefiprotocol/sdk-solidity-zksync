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

    function validateAndDecode(bytes memory _purefidata) external returns (VerificationPackage memory);

    //@Deprecated
    function validatePureFiData(bytes memory _purefidata) external returns (bytes memory, uint16);
    //@Deprecated
    function decodePureFiPackage(bytes memory _purefipackage) external view returns (VerificationPackage memory);
}