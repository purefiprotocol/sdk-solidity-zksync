// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../openzeppelin-contracts-upgradeable-master/contracts/proxy/utils/Initializable.sol";
import "./interfaces/IPureFiVerifier.sol";
import "./interfaces/IPureFiConstants.sol";

interface IParamStorage{
    function getUint256(uint16 key) external view returns (uint256);
}

abstract contract PureFiContext is Initializable{

    enum DefaultRule {NONE, KYC, AML, KYCAML} 

    bytes internal constant _PUREFI_CONTEXT_DATA_NOT_SET = "";
    uint256 internal constant _PUREFI_CONTEXT_NOT_VERIFIED = 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffa;
    uint256 internal constant _PUREFI_CONTEXT_VERIFIED = 0;

    address internal pureFiVerifier;

    uint256 private _txLocalPureFiCheckResult;
    bytes private _txLocalPureFiPackage; //similar to re-entrancy guard status or ThreadLocal in Java

    function __PureFiContext_init_unchained(address _pureFiVerifier) internal initializer{
        _txLocalPureFiCheckResult = _PUREFI_CONTEXT_NOT_VERIFIED;  
        _txLocalPureFiPackage = _PUREFI_CONTEXT_DATA_NOT_SET;
        pureFiVerifier = _pureFiVerifier;
    }

     modifier rejectUnverified() {
        require(_txLocalPureFiCheckResult == _PUREFI_CONTEXT_VERIFIED, "PureFiContext : context not set or unverified");
        _;
    }


    modifier withPureFiContext(bytes calldata _purefidata) {
        _validateAndSetContext(_purefidata);
        //here the smart contract can decide whether to fail a transaction in case of check failed
        _;
       _clearContext();
    }

    modifier withDefaultAddressVerification(DefaultRule _rule, address _address, bytes calldata _purefidata) {
        _validateAndSetContext(_purefidata);
        uint256 ruleID = 0;
        if(_rule == DefaultRule.AML)
            ruleID = IParamStorage(pureFiVerifier).getUint256(PARAM_TYPE1_DEFAULT_AML_RULE);
        else if(_rule == DefaultRule.KYC)
            ruleID = IParamStorage(pureFiVerifier).getUint256(PARAM_TYPE1_DEFAULT_KYC_RULE);
        else if(_rule == DefaultRule.KYCAML)
            ruleID = IParamStorage(pureFiVerifier).getUint256(PARAM_TYPE1_DEFAULT_KYCAML_RULE);
        else 
            require (false, "PureFiContext : Incorrect rule provided");
        _verifyAgainstTheRuleType1(ruleID, _address);
        //here the smart contract can decide whether to fail a transaction in case of check failed
        _;
        _clearContext();
    }

    modifier withCustomAddressVerification(uint256 _ruleID, address _address, bytes calldata _purefidata) {
        _validateAndSetContext(_purefidata);
        _verifyAgainstTheRuleType1(_ruleID, _address);
        //here the smart contract can decide whether to fail a transaction in case of check failed
        _;
        _clearContext();
    }


    function getVerificationPackage() internal view returns (VerificationPackage memory){
        require(_txLocalPureFiCheckResult == _PUREFI_CONTEXT_VERIFIED, "PureFiContext : Verification failed");
        return IPureFiVerifier(pureFiVerifier).decodePureFiPackage(_txLocalPureFiPackage);
    }

    function _verifyAgainstTheRuleType1(uint256 _ruleID, address _address) private view {
        VerificationPackage memory package = IPureFiVerifier(pureFiVerifier).decodePureFiPackage(_txLocalPureFiPackage);
        require (package.rule == _ruleID, "PureFiContext : package rule mismatch");
        require (package.from == _address, "PureFiContext : package address mismatch");
    }

    function _clearContext() private {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _txLocalPureFiCheckResult = _PUREFI_CONTEXT_NOT_VERIFIED;
        _txLocalPureFiPackage = _PUREFI_CONTEXT_DATA_NOT_SET;
    }

    function _validateAndSetContext(bytes calldata _purefidata) private {
        bytes memory purefiPackage;
        ( purefiPackage, _txLocalPureFiCheckResult) = IPureFiVerifier(pureFiVerifier).validatePureFiData(_purefidata);
        require(_txLocalPureFiCheckResult == _PUREFI_CONTEXT_VERIFIED, "PureFiContext : Verification failed");
        _txLocalPureFiPackage = purefiPackage;
    }

   

}
