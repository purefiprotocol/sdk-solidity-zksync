// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import {IPaymaster, ExecutionResult} from "@matterlabs/zksync-contracts/l2/system-contracts/interfaces/IPaymaster.sol";
import {IPaymasterFlow} from "@matterlabs/zksync-contracts/l2/system-contracts/interfaces/IPaymasterFlow.sol";
import {Transaction} from "@matterlabs/zksync-contracts/l2/system-contracts/libraries/TransactionHelper.sol";

import "@matterlabs/zksync-contracts/l2/system-contracts/Constants.sol";

// import "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC20} from "@matterlabs/zksync-contracts/l2/system-contracts/openzeppelin/token/ERC20/IERC20.sol";
import "./interfaces/IPureFiTxContext.sol";
import "./libraries/SignLib.sol";
import "./libraries/BytesLib.sol";
import "./PureFiData.sol";
import "./interfaces/IPureFiIssuerRegistry.sol";


contract PureFiPaymaster is AccessControl, SignLib, IPaymaster, IPureFiTxContext, PureFiDataUtils{

    struct PureFiContext{
        uint64 validUntil;
        uint256 session;
        uint256 rule;
        address from;
        address to;
        address token;
        uint256 amount;
        bytes payload;
    }

    // context data

    uint256 internal graceTime; //a period verification credentials are considered valid;

    mapping (address => PureFiContext) contextData; //context data structure

    mapping ( address => bool ) whitelistedTokens; 

    IPureFiIssuerRegistry issuerRegistry;

    address public pureFiSubscriptionContract;

    address public router;

    modifier onlyBootloader() {
        require(
            msg.sender == BOOTLOADER_FORMAL_ADDRESS,
            "PureFiPaymaster: Only bootloader can call this method"
        );
        // Continure execution if called from the bootloader.
        _;
    }

    constructor(
        address _admin,
        address _subscriptionContract,
        address _issuerRegistry,
        address _router,
        address[] memory _whitelistedTokens
        ) {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        pureFiSubscriptionContract = _subscriptionContract; //this is to validate the PureFi subscription in future. 
        graceTime = 180;//3 min - default value;
        issuerRegistry = IPureFiIssuerRegistry(_issuerRegistry);
        router = _router;

        if (_whitelistedTokens.length > 0){
            for(uint i = 0; i < _whitelistedTokens.length; i++){
                whitelistedTokens[_whitelistedTokens[i]] = true;
            }
        }
    }

    function version() external pure returns(uint256){
        //xxx.yyy.zzz
        return 2000005;
    }

    function setGracePeriod(uint256 _gracePeriod) external onlyRole(DEFAULT_ADMIN_ROLE){
        graceTime = _gracePeriod;
    }

    function validateAndPayForPaymasterTransaction(
        bytes32 _txHash,
        bytes32 _suggestedSignedHash,
        Transaction calldata _transaction
    ) external payable override onlyBootloader returns (bytes4 magic, bytes memory context) {
        require(
            _transaction.paymasterInput.length >= 4,
            "PureFiPaymaster: The standard paymaster input must be at least 4 bytes long"
        );

        bytes4 paymasterInputSelector = bytes4(
            _transaction.paymasterInput[0:4]
        );

        if (paymasterInputSelector == IPaymasterFlow.approvalBased.selector) {
            //unpack general() data
            (address token, uint256 minAllowance, bytes memory input) = abi
                .decode(
                    _transaction.paymasterInput[4:],
                     (address, uint256, bytes)
                    );
            require(_isWhitelisted(token), "PureFiPaymaster : Incorrect input token");

            uint256 requiredETH = _transaction.gasLimit *
                _transaction.maxFeePerGas;

            uint256 requiredTokenAmount = _getMinTokenAmount(token, requiredETH);
            require(minAllowance >= requiredTokenAmount, "PureFiPaymaster : Incorrect input min allowance");
            
            address userAddress = address(uint160(_transaction.from));
            uint256 providedAllowance = IERC20(token).allowance(userAddress, address(this));

            require(providedAllowance >= requiredTokenAmount, "PureFiPaymaster : Insufficient allowance");

            //unpack embedded data geberated by the PureFi Issuer service
    
            (uint64 timestamp, bytes memory signature, bytes memory package) = decodePureFiData(input);

            VerificationPackage memory packageStruct = decodePackage(package);
            //get issuer address from the signature
            address issuer = recoverSigner(keccak256(abi.encodePacked(timestamp, package)), signature);
            
            require(issuerRegistry.isValidIssuer(issuer), "PureFiPaymaster: Issuer signature invalid");

            require(timestamp + graceTime >= block.timestamp, "PureFiPaymaster: Credentials data expired");

            address contextAddress = packageStruct.from;

            //saving data locally so that they can be queried by the customer contract

            contextData[contextAddress] = _getPureFiContext(packageStruct, timestamp + uint64(graceTime));
            
            // Note, that while the minimal amount of ETH needed is tx.ergsPrice * tx.ergsLimit,
            // neither paymaster nor account are allowed to access this context variable.

            require(
                IERC20(token).transferFrom(userAddress, address(this), requiredTokenAmount), 
                "PureFiPaymaster : TransferFrom failed"
                );

            // The bootloader never returns any data, so it can safely be ignored here.
            (bool success, ) = payable(BOOTLOADER_FORMAL_ADDRESS).call{
                value: requiredETH
            }("");
            require(success, "PureFiPaymaster: Failed to transfer funds to the bootloader");

        } 
        else {
            revert("Unsupported paymaster flow");
        }

        // TODO : check docs for this moment;
        magic = IPaymaster.validateAndPayForPaymasterTransaction.selector;
    }

    function getPureFiContextData(address _contextAddr) external view returns (
        uint256, //sessionID
        uint256, //ruleID
        uint64, //validUntil
        address, //from
        address, //to
        address, //token
        uint256, //amount
        bytes memory //payload
    ) 
    {
        PureFiContext memory context = contextData[_contextAddr];
        return (
            context.session,
            context.rule,
            context.validUntil,
            context.from,
            context.to,
            context.token,
            context.amount,
            context.payload
        );
    }
    function postTransaction(
        bytes calldata _context,
        Transaction calldata _transaction,
        bytes32 _txHash,
        bytes32 _suggestedSignedHash,
        ExecutionResult _txResult,
        uint256 _maxRefundedGas
    ) external override payable{

    }

    receive() external payable {}


    // get PureFiContext struct from VerificationPackage and timestamp
    function _getPureFiContext(VerificationPackage memory _package, uint64 _validUntil) private pure returns(PureFiContext memory){
        return PureFiContext(
            _validUntil,
            _package.session,
            _package.rule,
            _package.from,
            _package.to,
            _package.token,
            _package.amount,
            _package.payload
            );
    }

    // get minimal amount of tokens for refunding transaction
    function _getMinTokenAmount( address token, uint256 _requiredETH ) private view returns(uint256 tokenAmount) {
        //TODO
        return 2*(10**18);
    }

    function _isWhitelisted(address _token) internal view returns (bool){
        return whitelistedTokens[_token];
    }

    function isWhitelisted(address _token) public view returns (bool){
        return _isWhitelisted(_token);
    }
}
