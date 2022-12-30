// SPDX-License-Identifier: MIT OR Apache-2.0

pragma solidity ^0.8.0;

interface IPureFiTxContext {

    function pureFiContextDataX(address _contextAddr) external view returns (
        uint256, //sessionID
        uint256, //ruleID
        uint64, //validUntil
        address, //from
        address, //to
        address, //token
        uint256, //amount
        bytes memory //payload
    );
    
}
