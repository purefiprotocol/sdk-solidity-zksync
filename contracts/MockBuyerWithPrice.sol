// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.12;

import "../openzeppelin-contracts-master/contracts/access/Ownable.sol";

contract MockBuyerWithPrice is Ownable {

    uint256 public constant DENOM = 10**9;
    uint256 public price = 30_000_000;

    error NotImplemented();

    function setPrice(uint256 _price) external onlyOwner {
        price = _price;
    }

    receive() external payable {
        revert NotImplemented();
    }

    fallback() external payable {
        revert NotImplemented();
    }

    function busdToUFI(uint256 _amountBUSD)
        external
        view
        returns (uint256, uint256)
    {
        return (1, DENOM*_amountBUSD/price);
    }
}
