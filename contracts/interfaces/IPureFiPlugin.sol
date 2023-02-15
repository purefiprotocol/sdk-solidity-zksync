// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPureFiPlugin{
    function swapTokens() external returns (uint256 receivedETH);
    function getMinTokensAmountForETH( address _token, uint256 _requiredETH ) external view returns(uint256);
    function whitelistToken( address _token ) external returns(bool);
    function delistToken( address _token ) external returns(bool);
}