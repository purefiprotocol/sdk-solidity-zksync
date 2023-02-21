// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

interface IPaymasterPluginCompatible{
    function approveTokenForPlugin(address _token, uint256 _amount) external returns(bool);
    
}

