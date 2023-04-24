// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0;

import "../../openzeppelin-contracts-master/contracts/token/ERC20/ERC20.sol";

interface IUFILock{
    /**
    returns (lockedBalance, lockedUntil)
     */
    function getLockData(address _holder) external view returns (uint256, uint64);
}

contract TestBotProtection {

    address public tokenProtected;//erc20 token protected by this contract
    address public ufiLocker; //UFI Lock contract
  
    modifier onlyProtectedToken() {
        require(tokenProtected == msg.sender, "PureFiBotProtection: only protected token can call this function");
        _;
    }

    constructor(address _tokenProtected, address _ufiLocker) {
        tokenProtected = _tokenProtected;
        ufiLocker = _ufiLocker;

    }

    function isPotentialBotTransfer(address _from, address _to, uint256 _amount, address _msgsender) external onlyProtectedToken returns (bool){
        
        require (ufiLocker == address(0) || _lockedTokensUnaffected(_from, _amount),
             "UFIToken: can't transfer locked tokens. Open PureFi Dashboard and connect your wallet for details.");
     
        return false; //allow by default
    }

   
    /**
    returns true if locked tokens are unaffected by transfer
     */
    function _lockedTokensUnaffected(address _holder, uint256 _transferAmt) private returns(bool){
        uint256 holderBalance = ERC20(tokenProtected).balanceOf(_holder);
        (uint256 lockedTokens, uint64 lockedUntil) = IUFILock(ufiLocker).getLockData(_holder);
        return (block.timestamp >= lockedUntil) || (holderBalance >= lockedTokens + _transferAmt);
    }
}