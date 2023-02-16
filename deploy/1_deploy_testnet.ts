import { Provider, utils, Wallet } from 'zksync-web3';
import * as ethers from 'ethers';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import EthCrypto from 'eth-crypto';
import { Deployer } from '@matterlabs/hardhat-zksync-deploy';

import { privateKey } from "../network_keys/secrets.json";
import fs from 'fs';


const PLUG_ADDRESS = "0x0000000000000000000000000000000000000001";
const privateKeyIssuer = 'e3ad95aa7e9678e96fb3d867c789e765db97f9d2018fca4068979df0832a5178';

const EMPTY_WALLET_PRIVATE_KEY = "0x9f1f9daa4d7093111684d7043824bc98a863444cd1a9e2a7c85eebaeb9d8c04d";

const EMPTY_WALLET_ADDRESS = "0x4DF6Ba41aAF6209A9C47856feF7Fb8058e93d7Ae";

const NETWORK_URL = 'https://zksync2-testnet.zksync.dev';

const TEST_WETH  = "0x2075860EF318824804a5C08256909628E513D43e";

export default async function (hre : HardhatRuntimeEnvironment){

    const provider = new Provider(NETWORK_URL);

    const wallet = new Wallet(privateKey, provider);

    const deployer = new Deployer(hre, wallet);

    // deploy erc20
    const erc20Artifact = await deployer.loadArtifact("MyERC20");
    
    const usdc = await deployer.deploy(erc20Artifact, [
        "USDCtest",
        "USDCT",
        6
    ]);

    const usdt = await deployer.deploy(erc20Artifact,[
        "USDTtest",
        "USDTT",
        6
    ]);

    const testToken = await deployer.deploy(erc20Artifact,[
        "TST",
        "TST",
        18
    ]);

    console.log("USDC test address : ", usdc.address);

    console.log("USDT test address : ", usdt.address);

    console.log("TST address : ", testToken.address);

    const issuerAddress = EthCrypto.publicKey.toAddress(EthCrypto.publicKeyByPrivateKey(privateKeyIssuer));

    console.log("Issuer address : ", issuerAddress);

    // deploy issuer_registry
    const issuerRegistryArtifact = await deployer.loadArtifact("MockIssuerRegistry");
    const issuerRegistry = await deployer.deploy(issuerRegistryArtifact, [
        wallet.address
    ]);

    // register issuer 
    await issuerRegistry.register(issuerAddress, "0x0000000000000000000000000000000000000000000000000000000000000001");
    const whitelistedTokens = [ usdc.address, usdt.address ];
    // deploy paymaster
    const paymasterArtifact = await deployer.loadArtifact("PureFiPaymaster");
    const paymaster = await deployer.deploy(paymasterArtifact, [
        wallet.address,
        PLUG_ADDRESS,
        issuerRegistry.address,
        whitelistedTokens
    ]);

    console.log("Paymaster address : ", paymaster.address);

     // deploy mock_plugin
     const mockPluginArtifact = await deployer.loadArtifact("MockUniswapPlugin");
     const mockPlugin = await deployer.deploy(mockPluginArtifact, [
        whitelistedTokens,
        TEST_WETH,
        paymaster.address
     ]);

     console.log("mockPlugin address : ", mockPlugin.address);

    // set plugin for paymaster
    await paymaster.setPlugin(mockPlugin.address);


    // deploy test contract
    const testContractArtifact = await deployer.loadArtifact("FilteredPool");
    const testContract = await deployer.deploy(testContractArtifact, [
        testToken.address,
        paymaster.address
    ]);

    console.log("FilteredPool address : ", testContract.address);
    console.log("FilteredPool context holder : ", await testContract.contextHolder.call());


    // mint test tokens
    await( await usdc.mint(EMPTY_WALLET_ADDRESS, ethers.utils.parseEther("100"))).wait();
    await( await usdt.mint(EMPTY_WALLET_ADDRESS, ethers.utils.parseEther("100"))).wait();
    await( await testToken.mint(EMPTY_WALLET_ADDRESS, ethers.utils.parseEther("100"))).wait();


    console.log("Wallet balance : ", (await usdc.balanceOf(EMPTY_WALLET_ADDRESS)).toString());

    const isValidIssuer = await issuerRegistry.isValidIssuer(issuerAddress);
    console.log("isValidIssuer ( bool ) : ", isValidIssuer);

    // write new deployed contracts addresses to file;
    let contracts = {
        paymaster : paymaster.address,
        filteredPool : testContract.address,
        usdc : usdc.address,
        usdt : usdt.address,
        mockPlugin : mockPlugin.address,
        testToken : testToken.address
    };
    let data = JSON.stringify(contracts);

    fs.writeFileSync('./addresses.json', data);
    console.log("File is written");

}