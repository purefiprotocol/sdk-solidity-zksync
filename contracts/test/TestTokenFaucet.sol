// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "../../openzeppelin-contracts-master/contracts/token/ERC20/ERC20.sol";
import "./TestBotProtection.sol";

contract TestTokenFaucet is ERC20{

    mapping(address => uint64) public faucetPeriod; // address => timestamp for next faucet trigger
    uint64 blockPeriod;

    constructor(uint256 _supply, string memory _name, string memory _symbol) ERC20(_name, _symbol) {
        _mint(_msgSender(), _supply);
        blockPeriod = 24 * 60 * 60;
    }

    function giveMeTokens() external{
        uint64 nextMintTimestamp = faucetPeriod[msg.sender];
        require(block.timestamp >= nextMintTimestamp, "TestToken : Not enough time has passed");
        faucetPeriod[msg.sender] += blockPeriod;
        _mint(msg.sender, 50000*10**18);
    }
    
}