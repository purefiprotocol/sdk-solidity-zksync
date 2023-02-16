// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "../interfaces/IPureFiPlugin.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
contract MockPureFiPaymaster {

    IPureFiPlugin uniswapV3Plugin;
    address[] whitelistedTokensArr;

    constructor(address _plugin, address[] memory _whitelistedTokens) {
        uniswapV3Plugin = IPureFiPlugin(_plugin);
        whitelistedTokensArr = _whitelistedTokens;
    }

    function swapTokens() external returns(uint256 receivedETH) {
        for(uint i = 0; i < whitelistedTokensArr.length; i++){
            uint256 balance = IERC20(whitelistedTokensArr[i]).balanceOf(address(this));
            require(
                IERC20(whitelistedTokensArr[i]).approve(address(uniswapV3Plugin), balance),
                "MockPaymaster : approve fail"    
            );
        }
        receivedETH = IPureFiPlugin(uniswapV3Plugin).swapTokens();

    }

    function whitelistToken( address _token ) external{
        require(uniswapV3Plugin.whitelistToken(_token));
    }

    function delistToken( address _token ) external{
        require(uniswapV3Plugin.delistToken(_token));
    }

}
