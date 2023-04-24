// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "./../PureFiContext.sol";
import "hardhat/console.sol";
contract ContextTestContract is PureFiContext{

    event NewCounterValue( uint256 indexed newValue );
    uint256 counter;
    constructor( address _verifier ) {
        __PureFiContext_init_unchained(_verifier);
        counter = 0;
    }

    function funcWithPureFiContext(
        bytes calldata _purefidata
        ) external withPureFiContext(_purefidata){
        counter = 100;
        emit NewCounterValue(counter);
    }

    function funcWithDefaultAddressVerification(
        DefaultRule rule, 
        address _address, 
        bytes calldata _purefidata 
        ) external withDefaultAddressVerification(rule, _address, _purefidata){
            counter = 200;
        }

    function funcWithCustomAddressVerification(
        uint256 _ruleId,
        address _address,
        bytes calldata _purefidata
    ) external withCustomAddressVerification(_ruleId, _address, _purefidata){
        counter = 300;
    }

    function getCounter() external view returns(uint256 ){
        return counter;
    }

}