// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "../../openzeppelin-contracts-master/contracts/token/ERC20/ERC20.sol";
import "./TestBotProtection.sol";

contract TestToken is ERC20{

    address public botProtector;

    constructor(uint256 _supply, string memory _name, string memory _symbol) ERC20(_name, _symbol) {
        _mint(_msgSender(), _supply);
    }

    function setBotProtector(address _botProtector) public{
        botProtector = _botProtector;
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
         if(botProtector != address(0)){//address required for seamless upgrade
            require(!TestBotProtection(botProtector).isPotentialBotTransfer(from, to, amount, _msgSender()), "PureFiToken: Bot transaction reverted");
        }
    }
    
}