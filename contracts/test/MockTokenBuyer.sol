// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

contract MockTokenBuyer {
    function busdToUFI(uint256 _amountBUSD)
        external
        view
        returns (uint256, uint256)
    {
        return (1, _amountBUSD);
    }
}
