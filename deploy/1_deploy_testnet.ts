import { Provider, utils, Wallet } from 'zksync-web3';
import * as ethers from 'ethers';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import EthCrypto from 'eth-crypto';
import { Deployer } from '@matterlabs/hardhat-zksync-deploy';

import { privateKey } from "../network_keys/secrets.json";


const PLUG_ADDRESS = "0x0000000000000000000000000000000000000001";
const privateKeyIssuer = 'e3ad95aa7e9678e96fb3d867c789e765db97f9d2018fca4068979df0832a5178';

const EMPTY_WALLET_PRIVATE_KEY = "0x9f1f9daa4d7093111684d7043824bc98a863444cd1a9e2a7c85eebaeb9d8c04d";

const EMPTY_WALLET_ADDRESS = "0x4DF6Ba41aAF6209A9C47856feF7Fb8058e93d7Ae";

export default async function (hre : HardhatRuntimeEnvironment){

    const provider = new Provider(hre.config.zkSyncDeploy.zkSyncNetwork);

    const wallet = new Wallet(privateKey, provider);

    const deployer = new Deployer(hre, wallet);

    // deploy erc20
    const erc20Artifact = await deployer.loadArtifact("MyERC20");
    const erc20 = await deployer.deploy(erc20Artifact, [
        "TestToken",
        "TST",
        18
    ]);

    console.log("ERC20 address : ", erc20.address);

    // deploy paymaster
    const paymasterArtifact = await deployer.loadArtifact("PureFiPaymaster");
    const paymaster = await deployer.deploy(paymasterArtifact, [
        wallet.address,
        PLUG_ADDRESS
    ]);

    console.log("Paymaster address : ", paymaster.address);

    const issuerAddress = EthCrypto.publicKey.toAddress(EthCrypto.publicKeyByPrivateKey(privateKeyIssuer));

    console.log("Issuer address : ", issuerAddress);

    const ISSUER_ROLE = await paymaster.ISSUER_ROLE.call();
    await(await paymaster.grantRole(ISSUER_ROLE, issuerAddress)).wait();

    let isIssuer = await paymaster.hasRole(ISSUER_ROLE, issuerAddress);
    console.log("isIssuer :", isIssuer);

    // deploy test contract
    const testContractArtifact = await deployer.loadArtifact("FilteredPool");
    const testContract = await deployer.deploy(testContractArtifact, [
        erc20.address,
        paymaster.address
    ]);

    console.log("FilteredPool address : ", testContract.address);
    console.log("FilteredPool context holder : ", await testContract.contextHolder.call());


    // mint test tokens
    await( await erc20.mint(EMPTY_WALLET_ADDRESS, ethers.utils.parseEther("100"))).wait();

    console.log("Wallet balance : ", await erc20.balanceOf(EMPTY_WALLET_ADDRESS));
}