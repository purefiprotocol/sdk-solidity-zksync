# PureFi custom Paymaster

Original codebase is derived from the "Build a custom paymaster" tutorial from the [zkSync v2 documentation](https://v2-docs.zksync.io/dev/).

The idea of the Paymaster is inspired by the [PureFiContext](https://github.com/purefiprotocol/sdk-solidity/blob/master/contracts/PureFiContext.sol) contract, which is following OpenZeppelin re-entrancy guard contract design approach. Meaning that it is setting context storage variables before target Tx starts, and erases after it finishes. 

[PureFiContext](https://github.com/purefiprotocol/sdk-solidity/blob/master/contracts/PureFiContext.sol) itself is the part of the PureFi protocol implementation which delivers AML (Anti-money laundering) verification data into the smart contract, thus allowing smart contract designers and operators take the decision either to accept or to block incoming funds (due to a high risk associated with the address or transaction, for example). PureFi makes use of the so called Rules (identified by RuleID), which associates the identifier (ruleID) with the explicit verification that is 
performed on the PureFi Issuer side. This process is typically initiated by the front-end (dApp), then verification is performed and signed package is provided to be used by the dApp to convince Smart contract that required veficication was performed, and it can accept funds. The detailed guide and description can be found [here](https://docs.purefi.io/integrate/products/aml-sdk/interactive-mode)

[PureFiPaymaster](./contracts/PureFiPaymaster.sol) accepts signed packages issued by the PureFi issuer within the Paymaster payload
```
    (bytes memory input) = abi.decode(_transaction.paymasterInput[4:], (bytes));

    (uint64 timestamp, bytes memory signature, bytes memory package) = decodePureFiData(input);
```

then decodes and validates this data
```

    VerificationPackage memory packageStruct = decodePackage(package);
    //get issuer address from the signature
    address issuer = recoverSigner(keccak256(abi.encodePacked(timestamp, package)), signature);

    require(hasRole(ISSUER_ROLE, issuer), "PureFiPaymaster: Issuer signature invalid");

    require(timestamp + graceTime >= block.timestamp, "PureFiPaymaster: Credentials data expired");

```

then set up the transaction context variables.
```
    address contextAddress = packageStruct.from;

    //saving data locally so that they can be queried by the customer contract

    contextData[contextAddress] = _getPureFiContext(packageStruct, timestamp + uint64(graceTime));

These variables could be then queried by the target smart contract [FilteredPool.sol](./contracts/example/FilteredPool.sol) to make sure that verification was performed according to the expected rule.
```
    function depositTo(
        uint256 _amount,
        address _to
    ) external {
        //verify sender funds via PureFiContext
        (
            uint256 sessionID,
            uint256 ruleID,
            uint64 validUntil,
            address verifiedUser,
            address to,
            address token,
            uint256 amount,
            bytes memory payload
        ) = contextHolder.pureFiContextDataX(msg.sender);

                   require(ruleID == expectedDepositRuleID, "Invalid ruleID provided");
            require(
                msg.sender == verifiedUser,
                "Invalid verifiedUser provided"
            );
            require(token == address(basicToken), "Invalid token provided");
            require(
                to == address(this),
                "Invalid to receiver address provided"
            );
            require(amount == _amount, "Invalid amount provided");
            require(
                validUntil >= block.timestamp,
                "Validity package is expired"
            );
            require(
                keccak256(payload) == keccak256(""),
                "Invalid payload provided"
            );
            _deposit(_amount, _to);
       
    }
``` 
> contextHolder in the code above is actually the PureFiPaymaster contract.

This way the smart contract can be sure that funds and the sender address were verified according to the ruleID expected, and thus, it's safe to accept these funds from the user. 

## Deployment and usage

> complete deployment and test requires about 0.03 ETH

create a folder `network_keys` inside the project folder and put a file `secrets.json` into this folder. The structure of the secrets file is the following:

```
    {
        "mnemonic": "YOUR MNEMONIC HERE",
        "infuraApiKey": "<YOUR API KEY HERE>",
        "privateKey" : "YOUR MAIN WALLET PK HERE, WITH SOME BALANCE IN ZKSYNC TESTNET"
    }
```

Compile with command:
- `yarn hardhat compile`

Deploy contracts:
- `yarn hardhat deploy-zksync --script deploy/1_deploy_testnet.ts`

Contracts addresses in script 2_use_paymaster.ts 
( PAYMASTER_ADDRESS, FILTERED_POOL_ADDRESS, TEST_TOKEN_ADDRESS ) replace with deployed contract

the test is performed by the following command:
- `yarn hardhat deploy-zksync --script deploy/2_use_paymaster.ts`: 

## Testing flow
1. ERC20, FilteredPool and PureFiPaymaster are deployed
2. a new wallet (a.k.a. emptyWallet) is generated and obtains 100 ERC20 tokens. No ETH balance exists on this address
3. approval tx is issued from emptyWallet to allow FilteredPool to grap tokens. Tx is processed via PureFiPaymaster which pays for this tx
3. deposit tx is issued from emptyWallet to FilteredPool. ERC20 tokens are transferred from emptyWallet to FilteredPool, totalCap is encreased. 
3. withdraw tx is issued from emptyWallet to FilteredPool. ERC20 tokens are transferred from FilteredPool to emptyWallet, totalCap is decreased.
