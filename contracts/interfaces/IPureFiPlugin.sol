// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPureFiPlugin{
    function getMinTokensAmountForETH( address _token, uint256 _requiredETH ) external view returns(uint256);
    function swapToken( address _token, uint256 _amount ) external returns( uint256 receivedETH );
}