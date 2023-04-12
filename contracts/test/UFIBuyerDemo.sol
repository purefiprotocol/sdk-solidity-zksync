pragma solidity ^0.8.0;

import "../PureFiVerifier.sol";
import "../PureFiContext.sol";
import "../../openzeppelin-contracts-upgradeable-master/contracts/access/OwnableUpgradeable.sol";
import "../../openzeppelin-contracts-upgradeable-master/contracts/token/ERC20/IERC20Upgradeable.sol";


contract UFIBuyerDemo is PureFiContext, OwnableUpgradeable {
    IERC20Upgradeable ufi;

    function initialize(address _token, address _verifier) external initializer {
        ufi = IERC20Upgradeable(_token);
        address verifier = _verifier;
        __Ownable_init();
        __PureFiContext_init_unchained(verifier);
    }

     function version() public pure returns(uint32){
        // 000.000.000 - Major.minor.internal
        return 2000004;
    }
    function setVerifier(address _verifier) external onlyOwner{
        pureFiVerifier = _verifier;
    }
    /**
    * buys UFI tokens for the full amount of _value provided.
    * @param _to - address to send bought tokens to
    * @param _purefidata -  a signed data package from the PureFi Issuer
    */
    function buyForWithAML(address _to,
                    bytes calldata _purefidata
                    ) external payable withDefaultAddressVerification (DefaultRule.AML, msg.sender, _purefidata) {
        _buy(_to);
    }
    /**
    * buys UFI tokens for the full amount of _value provided.
    * @param _to - address to send bought tokens to
    * @param _purefidata -  a signed data package from the PureFi Issuer
    */
    function buyForWithKYC(address _to,
                    bytes calldata _purefidata
                    ) external payable withDefaultAddressVerification (DefaultRule.KYC, msg.sender, _purefidata) {
        _buy(_to);
    }
    /**
    * buys UFI tokens for the full amount of _value provided.
    * @param _to - address to send bought tokens to
   @param _purefidata -  a signed data package from the PureFi Issuer
    */
    function buyForWithKYCAML(address _to,
                   bytes calldata _purefidata
                    ) external payable withDefaultAddressVerification (DefaultRule.KYCAML, msg.sender, _purefidata) {
        _buy(_to);
    }

    function buyForWithCOUNTRYKYC(address _to,
                   bytes calldata _purefidata
                    ) external payable withDefaultAddressVerification (DefaultRule.COUNTRYKYC, msg.sender, _purefidata) {
        _buy(_to);
    }
    function buyForWithAGEKYC(address _to,
                   bytes calldata _purefidata
                    ) external payable withDefaultAddressVerification (DefaultRule.AGEKYC, msg.sender, _purefidata) {
        _buy(_to);
    }
    function buyForWithCOUNTRYAGEKYC(address _to,
                   bytes calldata _purefidata
                    ) external payable withDefaultAddressVerification (DefaultRule.COUNTRYAGEKYC, msg.sender, _purefidata) {
        _buy(_to);
    }
    function buyForWithOptionalKYCAML(address _to,
                   bytes calldata _purefidata
                    ) external payable withDefaultAddressVerification (DefaultRule.Type2KYCAML, msg.sender, _purefidata) {
        _buy(_to);
    }

    function _buy(address _to) internal returns (uint256){
        uint256 denom = 1000;
        uint256 oneCent = 10 ** 18 / denom;
        require(msg.value >= oneCent, "Please send more then 0.01 ETH");
        uint tokensToSend = msg.value * denom;
        ufi.transfer(_to, tokensToSend);
        return tokensToSend;
    }
}