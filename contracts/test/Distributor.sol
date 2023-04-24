// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.9;

import "hardhat/console.sol";
interface IProfitDistributor {
    function distributeProfit(uint256 amountTokens) external;
}

contract Distributor is IProfitDistributor {
    constructor() {}

    event Distributed(uint256 indexed distributedAmount);

    function distributeProfit(uint256 amountTokens) external {
        console.log("Distributor : distrubuteProfit function : amountTokens : ", amountTokens);
        emit Distributed(amountTokens);
    }
}
