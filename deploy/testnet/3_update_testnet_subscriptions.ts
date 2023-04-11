import { BigNumber } from "ethers";
import { config } from "hardhat";
import hre from "hardhat";

import { Provider, utils, Wallet, Contract } from 'zksync-web3';
import * as ethers from 'ethers';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import EthCrypto from 'eth-crypto';
import { Deployer } from '@matterlabs/hardhat-zksync-deploy';
import { privateKey } from "../../network_keys/secrets.json";
import fs from 'fs';
import { Address } from 'zksync-web3/build/src/types';
import { arrayify } from 'ethers/lib/utils';
const NETWORK_URL = 'https://zksync2-testnet.zksync.dev';


const UFI_ADDRESS = "0xB477a7AB4d39b689fEa0fDEd737F97C76E4b0b93";
const ISSUER_REGISTRY = "0x440d0a6d5c3dB3909606a043Bd404E533Eb31E26";
const WHITELIST = "0xd0145a886d16AE469969159A2139408888541DA0";
const VERIFIER_ADDRESS = "0x324DC9E87395B8581379dd35f43809C35c89470e";
const PROXY_ADMIN_ADDRESS = "0x1FDeEA7ae9D8d41C5a880E450E5Fac91B91CffDD";
const TOKEN_BUYER_ADDRESS = "0x9b1d98E6951431b87eCeaf38d174796A7E7A9A3f";
const SUBSCRIPTION_ADDRESS = "0x587DB6B30848FbEE4EDf98aD581EB94E410C9a82";

// params 

const PARAM_DEFAULT_AML_GRACETIME_KEY = 3;
const DEFAULT_GRACETIME_VALUE = 300;

const DEFAULT_AML_RULE = "431050";
const DEFAULT_KYC_RULE = "777";
const DEFAULT_KYCAML_RULE = "731090";

const PARAM_TYPE1_DEFAULT_AML_RULE = 4;
const PARAM_TYPE1_DEFAULT_KYC_RULE = 5;
const PARAM_TYPE1_DEFAULT_KYCAML_RULE = 6;




async function main(){

    const provider = new Provider(NETWORK_URL);

    const wallet = new Wallet(privateKey, provider);

    const deployer = new Deployer(hre, wallet);

    const PPRoxy = await deployer.loadArtifact("PPRoxy");
    const PProxyAdmin = await deployer.loadArtifact("PProxyAdmin");

    const PureFiWhitelist = await deployer.loadArtifact("PureFiWhitelist");
    const PureFiIssuerRegistry = await deployer.loadArtifact("PureFiIssuerRegistry");
    const PureFiVerifier = await deployer.loadArtifact("PureFiVerifier");
    const PureFiSubscriptionService = await deployer.loadArtifact("PureFiSubscriptionService");
    const PureFiTokenBuyerPolygon = await deployer.loadArtifact("PureFiTokenBuyerPolygon");
    const MockTokenBuyer = await deployer.loadArtifact("MockTokenBuyer");

    // deploy erc20
   
  

    const proxy_admin = new Contract(PROXY_ADMIN_ADDRESS, PProxyAdmin.abi, wallet);

    console.log("Proxy admin : ", proxy_admin.address);

    const subscriptionMasterCopy = await deployer.deploy(PureFiSubscriptionService);
    await new Promise(resolve => setTimeout(resolve, 3000)); // 3 sec
    // await subscriptionMasterCopy.deployed();
    console.log("Subscriptions master copy : ", subscriptionMasterCopy.address);

    await(await proxy_admin.upgrade(SUBSCRIPTION_ADDRESS, subscriptionMasterCopy.address)).wait();
    const subscriptionsContract = new Contract(SUBSCRIPTION_ADDRESS, PureFiSubscriptionService.abi, wallet);
    console.log("Upgraded version: ", (await subscriptionsContract.version()).toString());
    console.log("completed");

    const token_buyer = await deployer.deploy(MockTokenBuyer);

    console.log("Token_buyer address :", token_buyer.address);
    await new Promise(resolve => setTimeout(resolve, 3000)); // 3 sec

    await subscriptionsContract.setTokenBuyer(token_buyer.address);
    console.log("completed");
}


main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
  