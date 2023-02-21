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

}
