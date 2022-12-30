// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import {IPaymaster, ExecutionResult} from "@matterlabs/zksync-contracts/l2/system-contracts/interfaces/IPaymaster.sol";
import {IPaymasterFlow} from "@matterlabs/zksync-contracts/l2/system-contracts/interfaces/IPaymasterFlow.sol";
import {TransactionHelper, Transaction} from "@matterlabs/zksync-contracts/l2/system-contracts/TransactionHelper.sol";

import "@matterlabs/zksync-contracts/l2/system-contracts/Constants.sol";

import "@openzeppelin/contracts/interfaces/IERC20.sol";

import "./interfaces/IPureFiTxContext.sol";
import "./libraries/SignLib.sol";
import "./libraries/BytesLib.sol";
import "./PureFiData.sol";


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

    address public pureFiSubscriptionContract;

    bytes32 public constant ISSUER_ROLE = 0x0000000000000000000000000000000000000000000000000000000000009999;
    // context data

    uint256 internal graceTime; //a period verification credentials are considered valid;

    mapping (address => PureFiContext) contextData; //context data structure


    modifier onlyBootloader() {
        require(
            msg.sender == BOOTLOADER_FORMAL_ADDRESS,
            "PureFiPaymaster: Only bootloader can call this method"
        );
        // Continure execution if called from the bootloader.
        _;
    }

    constructor(address _admin, address _subscriptionContract) {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        pureFiSubscriptionContract = _subscriptionContract; //this is to validate the PureFi subscription in future. 
        graceTime = 180;//3 min - default value;
    }

    function version() external pure returns(uint256){
        //xxx.yyy.zzz
        return 2000001;
    }

    function setGracePeriod(uint256 _gracePeriod) external onlyRole(DEFAULT_ADMIN_ROLE){
        graceTime = _gracePeriod;
    }

    function validateAndPayForPaymasterTransaction(
        bytes32 _txHash,
        bytes32 _suggestedSignedHash,
        Transaction calldata _transaction
    ) external payable override onlyBootloader returns (bytes memory context) {
        require(
            _transaction.paymasterInput.length >= 4,
            "PureFiPaymaster: The standard paymaster input must be at least 4 bytes long"
        );

        bytes4 paymasterInputSelector = bytes4(
            _transaction.paymasterInput[0:4]
        );

        if (paymasterInputSelector == IPaymasterFlow.general.selector) {
            //unpack general() data
            (bytes memory input) = abi.decode(_transaction.paymasterInput[4:], (bytes));
            //unpack embedded data geberated by the PureFi Issuer service
            
    
            (uint64 timestamp, bytes memory signature, bytes memory package) = decodePureFiData(input);

            VerificationPackage memory packageStruct = decodePackage(package);
            //get issuer address from the signature
            address issuer = recoverSigner(keccak256(abi.encodePacked(timestamp, package)), signature);

            require(hasRole(ISSUER_ROLE, issuer), "PureFiPaymaster: Issuer signature invalid");

            require(timestamp + graceTime >= block.timestamp, "PureFiPaymaster: Credentials data expired");

            address contextAddress = packageStruct.from;

            //saving data locally so that they can be queried by the customer contract

            contextData[contextAddress] = _getPureFiContext(packageStruct, timestamp + uint64(graceTime));
            
            // Note, that while the minimal amount of ETH needed is tx.ergsPrice * tx.ergsLimit,
            // neither paymaster nor account are allowed to access this context variable.
            uint256 requiredETH = _transaction.ergsLimit *
                _transaction.maxFeePerErg;

            // require(msg.value >= requiredETH, "PureFiPaymaster: not enough ETH to pay for tx");

            // The bootloader never returns any data, so it can safely be ignored here.
            (bool success, ) = payable(BOOTLOADER_FORMAL_ADDRESS).call{
                value: requiredETH
            }("");
            require(success, "PureFiPaymaster: Failed to transfer funds to the bootloader");

        } 
        else {
            revert("Unsupported paymaster flow");
        }
    }

    function pureFiContextDataX(address _contextAddr) external view returns (
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

    function postOp(
        bytes calldata _context,
        Transaction calldata _transaction,
        bytes32 _txHash,
        bytes32 _suggestedSignedHash,
        ExecutionResult _txResult,
        uint256 _maxRefundedErgs
    ) external payable onlyBootloader {
        //MIHA: no storage writing operations here. results in CALL_EXCEPTION
    }

    receive() external payable {}


    // get PureFiContext struct from VerificationPackage and timestamp
    function _getPureFiContext(VerificationPackage memory _package, uint64 _validUntil) internal pure returns(PureFiContext memory){
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
}
