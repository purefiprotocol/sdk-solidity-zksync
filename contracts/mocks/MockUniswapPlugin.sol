// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "../interfaces/IPureFiPlugin.sol";
import "../interfaces/UniswapV3/IWETH9.sol";

contract MockUniswapPlugin is IPureFiPlugin {
    IWETH9 weth;
    address paymaster;

    constructor(
        address _weth,
        address _paymaster
    ) {
        weth = IWETH9(_weth);
        paymaster = _paymaster;
    }

    function getMinTokensAmountForETH(
        address _token,
        uint256 _requiredETH
    ) external view override returns (uint256) {
        // hardcode sqrtPriceX96 = 1974044266032894921671337932090008 as current ratio of WETH / USDC;
        // ratio = WETH / USDC
        // USDC_amount = WETH_amount / ratio;
        // ratio = (sqrtPriceX96 / 2**96) ** 2;
        uint160 sqrtPriceX96 = 1974044266032894921671337932090008;

        uint256 amount = (((_requiredETH * 2 ** 96) / sqrtPriceX96) * 2 ** 96) /
            sqrtPriceX96;
        return amount;
    }

    function swapToken(
        address _token,
        uint256 _amount
    ) external override returns (uint256 receivedETH) {}
}
