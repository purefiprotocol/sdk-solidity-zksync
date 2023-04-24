# PureFi SDK for Solidity (Version 4) (for ZkSync)

SDK is dedicated for the EVM based networks. Provides KYC and AML verifications for smart contracts based vaults, funds and DeFi protocols. 

SDK provides 3 different verification methods: 
 1. Interactive Mode: requires interaction with Issuer via API before transaction issued. More detail 
 2. Whitelist Mode: completely on-chain mode, but requires pre-publishing of the verified data in whitelist, which is a special smart contract.
 3. Non-Interactive Mode: on-chain verification with the help of ZK-SNARKS. Implementation is still in progress...   

 ## Changelist V2->V3
 1. PureFiVerifier: Interactive mode now supports 3 types of data packages:
    1.1 single address verification (derived from V1 and V2)
    1.2 combined verification of the {from, to, token, amount}, where from - funds sender address, to - funds receiver address, token - token contract address and amount - max amount of tokens sent (max amount means that actual deposit can be less or equal). This type is recommended for a standard deposit functions where single token is sent by user and received by the smart contract.
    1.3 transaction payload verification. This mode is designed for transactions, that combines sending of different tokens at the same time. For example, adding liquidity into the DEX pool. 
    1.4 removed default support for whitelisted credentials. PureFiWhitelist still can be used directly.
2. PureFiContext: upgraded to match PureFiVerifier changes + added helper functions and default rules for V2 compatible implementations. 

## Changelist V3->V4
1. PureFiVerifier: Enhances security for smart contract controlled subscriptions. 
    1.1 Verifier contract now validates the caller of the verification data package. Should match either "from" or "to". This way only related contracts has access to verification data. 
    1.2 All verification data packages now recorded on-chain to aviod re-use of the same package in consequent transacitons. 
2. Subscriptions contract can now support contract subscriptions and on-chain resolver to let Issuer decide whether or not to process incoming request.

## Integration example and live demo
Please check the [Live Demo here:](https://frontendsdksolidity.purefi.io/)
Integration documentation is available [here](https://docs.purefi.io/integrate/products/aml-sdk/interactive-mode)

Live Demo is available for both Ethereum and Binance Chain and is built upon the example contracts from this repo:
 * [UFIBuyerBSCWithCheck](./contracts/examples/ex02-filtered_tokenbuyer/UFIBuyerBSCWithCheck.sol)
 * [UFIBuyerETHWithCheck](./contracts/examples/ex02-filtered_tokenbuyer/UFIBuyerETHWithCheck.sol)
## On-chain infrastructure:
### ZKSync Era mainnet
| Contract name | contract address |
| ----------- | ----------- |
| PureFi Token | 0xa0C1BC64364d39c7239bd0118b70039dBe5BbdAE |
| PureFi Verifier (v4) | 0xB647483dB83ca97dB8a613c337886bf10ad3cD5B |
| PureFi Subscription | 0xbB86a7C9aCf201A281488Df371E18c6cf5222010 |

### ZKSync Era Testnet
| Contract name | contract address |
| ----------- | ----------- 
| PureFi Token | 0xB477a7AB4d39b689fEa0fDEd737F97C76E4b0b93 |
| PureFi Verifier (V4) | 0x324DC9E87395B8581379dd35f43809C35c89470e |
| PureFi Subscription | 0x587DB6B30848FbEE4EDf98aD581EB94E410C9a82 |

## Documentation
Please check PureFi Wiki site for more details. [AML SDK documentation is here](https://docs.purefi.io/integrate/welcome)
