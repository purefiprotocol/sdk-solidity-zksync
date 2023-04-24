import { Provider, utils, Wallet, Contract } from 'zksync-web3';
import * as ethers from 'ethers';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import EthCrypto from 'eth-crypto';
import { Deployer } from '@matterlabs/hardhat-zksync-deploy';

import { privateKey } from "../../network_keys/secrets.json";
import fs from 'fs';


//**** PUREFI SDK DEPLOYMENT SCRIPT *******//
// params for verifier

const PARAM_DEFAULT_AML_GRACETIME_KEY = 3;
const DEFAULT_GRACETIME_VALUE = 300;

const DEFAULT_AML_RULE = 431050;
const DEFAULT_KYC_RULE = 777;
const DEFAULT_KYCAML_RULE = 731090;
const DEFAULT_CLEANING_TOLERANCE = 3600;

const PARAM_TYPE1_DEFAULT_AML_RULE = 4;
const PARAM_TYPE1_DEFAULT_KYC_RULE = 5;
const PARAM_TYPE1_DEFAULT_KYCAML_RULE = 6;
const PARAM_CLEANING_TOLERANCE = 10;

const PROXY_ADMIN_ADDRESS = "0xB477a7AB4d39b689fEa0fDEd737F97C76E4b0b93";
const decimals = toBN(10).pow(18);

// issuer_registry params

const VALID_ISSUER_ADDRESS = "0xee5FF7E46FB99BdAd874c6aDb4154aaE3C90E698";
const PROOF = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("PureFi Issuer")); 
const ADMIN = "0xcE14bda2d2BceC5247C97B65DBE6e6E570c4Bb6D";  // admin of issuer_registry

// PureFiSubscriptionService params

const UFI_TOKEN = "0xa0C1BC64364d39c7239bd0118b70039dBe5BbdAE"; //test token in zksync testnet
const PROFIT_COLLECTION_ADDRESS = "0xcE14bda2d2BceC5247C97B65DBE6e6E570c4Bb6D";

function toBN(number: any) {
    return ethers.BigNumber.from(number);
}
/**
 * $ yarn hardhat deploy-zksync --script deploy/mainnet/2_deploy_sdk.ts
 */
export default async function (hre : HardhatRuntimeEnvironment){

    const provider = new Provider(hre.config.networks.zkSyncMainnet.url);
    const wallet = new Wallet(privateKey, provider);
    const deployer = new Deployer(hre, wallet);

    if ( PROOF.length == 0 || ADMIN.length == 0 ){
        throw new Error('ADMIN or PROOF variable is missed');
    }

    const PPRoxy = await deployer.loadArtifact("PPRoxy");
    const PProxyAdmin = await deployer.loadArtifact("PProxyAdmin");

    const PureFiWhitelist = await deployer.loadArtifact("PureFiWhitelist");
    const PureFiIssuerRegistry = await deployer.loadArtifact("PureFiIssuerRegistry");
    const PureFiVerifier = await deployer.loadArtifact("PureFiVerifier");
    const PureFiSubscriptionService = await deployer.loadArtifact("PureFiSubscriptionService");
    const PureFiTokenBuyer = await deployer.loadArtifact("MockBuyerWithPrice");

    // DEPLOY PROXY_ADMIN //
    // ------------------------------------------------------------------- //
    var actual_proxy_admin;
    if(PROXY_ADMIN_ADDRESS.length>0){
        actual_proxy_admin = new Contract(PROXY_ADMIN_ADDRESS, PProxyAdmin.abi, wallet)
    } else {
        console.log("Deploying new proxy admin...");
        actual_proxy_admin = await deployer.deploy(PProxyAdmin, []);
        await new Promise(resolve => setTimeout(resolve, 3000)); // 3 sec
    }
    const proxy_admin = actual_proxy_admin
    console.log("PROXY_ADMIN address : ", proxy_admin.address);
    

    // DEPLOY PureFiIssuerRegistry //
    // ------------------------------------------------------------------- //
    // const issuer_registry_mastercopy = await deployer.deploy(PureFiIssuerRegistry, [])
    
    // console.log("ISSUER_REGISTRY_MASTERCOPY address : ", issuer_registry_mastercopy.address);
    // await new Promise(resolve => setTimeout(resolve, 3000)); // 3 sec
    
    const issuer_registry_proxy = await deployer.deploy(PPRoxy, ["0x1FDeEA7ae9D8d41C5a880E450E5Fac91B91CffDD", proxy_admin.address, "0x"]);
    
    console.log("issuer_registry address : ", issuer_registry_proxy.address);
    
    await new Promise(resolve => setTimeout(resolve, 3000)); // 3 sec

    // initialize issuer_registry
    const issuer_registry = new Contract(issuer_registry_proxy.address, PureFiIssuerRegistry.abi, wallet);

    await (await issuer_registry.initialize(ADMIN)).wait();

    // set issuer
    await issuer_registry.register(VALID_ISSUER_ADDRESS, PROOF);


    // DEPLOY PureFiWhitelist // 
    // ------------------------------------------------------------------- //
    
    const whitelist_mastercopy = await deployer.deploy(PureFiWhitelist, [])//await PureFiWhitelist.deploy();

    console.log("whitelist_mastercopy address : ", whitelist_mastercopy.address);
    await new Promise(resolve => setTimeout(resolve, 3000)); // 3 sec

    const whitelist_proxy = await deployer.deploy(PPRoxy, [whitelist_mastercopy.address, proxy_admin.address, "0x"]);
    
    console.log("whitelist_proxy address : ", whitelist_proxy.address);
    await new Promise(resolve => setTimeout(resolve, 3000)); // 3 sec

    const whitelist = new Contract(whitelist_proxy.address, PureFiWhitelist.abi, wallet);

    // initialize whitelist
    await(await whitelist.initialize(issuer_registry.address)).wait();

    // DEPLOY PureFiVerifier // 
    // ------------------------------------------------------------------- //

    console.log("Deploying verifier...");
    const verifier_mastercopy = await deployer.deploy(PureFiVerifier, []);

    console.log("verifier_mastercopy address : ", verifier_mastercopy.address);

    await new Promise(resolve => setTimeout(resolve, 3000)); // 3 sec

    const verifier_proxy = await deployer.deploy(PPRoxy, [verifier_mastercopy.address, proxy_admin.address, "0x"]);

    console.log("Verifier address : ", verifier_proxy.address);

    await new Promise(resolve => setTimeout(resolve, 3000)); // 3 sec
    
    // initialize verifier
    const verifier = new Contract(verifier_proxy.address, PureFiVerifier.abi, wallet);
    await(await verifier.initialize(issuer_registry.address, whitelist.address)).wait();
    console.log("Verifier version: ", (await verifier.version()).toString());


    // set verifier params

    await(await verifier.setUint256(PARAM_DEFAULT_AML_GRACETIME_KEY, DEFAULT_GRACETIME_VALUE)).wait();
    await(await verifier.setUint256(PARAM_TYPE1_DEFAULT_AML_RULE, DEFAULT_AML_RULE)).wait();
    await(await verifier.setUint256(PARAM_TYPE1_DEFAULT_KYC_RULE, DEFAULT_KYC_RULE)).wait();
    await(await verifier.setUint256(PARAM_TYPE1_DEFAULT_KYCAML_RULE, DEFAULT_KYCAML_RULE)).wait();
    await(await verifier.setUint256(PARAM_CLEANING_TOLERANCE, DEFAULT_CLEANING_TOLERANCE)).wait();

    await(await verifier.setString(1, "PureFiVerifier: Issuer signature invalid")).wait();
    await(await verifier.setString(2, "PureFiVerifier: Funds sender doesn't match verified wallet")).wait();
    await(await verifier.setString(3, "PureFiVerifier: Verification data expired")).wait();
    await(await verifier.setString(4, "PureFiVerifier: Rule verification failed")).wait();
    await(await verifier.setString(5, "PureFiVerifier: Credentials time mismatch")).wait();
    await(await verifier.setString(6, "PureFiVerifier: Data package invalid")).wait();

    // DEPLOY PureFiTokenBuyerPolygon // 
    // ------------------------------------------------------------------- //

    const token_buyer = await deployer.deploy(PureFiTokenBuyer, []);

    console.log("Token_buyer address :", token_buyer.address);
    await new Promise(resolve => setTimeout(resolve, 3000)); // 3 sec

    // DEPLOY PureFiSubscriptionService // 
    // ------------------------------------------------------------------- //

    const sub_service_mastercopy = await deployer.deploy(PureFiSubscriptionService, []);
    
    console.log("Subscription master copy : ", sub_service_mastercopy.address);
    await new Promise(resolve => setTimeout(resolve, 3000)); // 3 sec

    const sub_service_proxy = await deployer.deploy(PPRoxy, [sub_service_mastercopy.address, proxy_admin.address, "0x"]);

    console.log("Subscription service address : ", sub_service_proxy.address);
    await new Promise(resolve => setTimeout(resolve, 3000)); // 3 sec

    // initialize sub_service 
    const sub_service = new Contract(sub_service_proxy.address, PureFiSubscriptionService.abi, wallet);
    await(await sub_service.initialize(
        ADMIN,
        UFI_TOKEN,
        token_buyer.address,
        PROFIT_COLLECTION_ADDRESS
    )).wait();

    console.log("Subscription version: ", (await sub_service.version()).toString());

    let yearTS = 86400*365;
    let USDdecimals = decimals;//10^18 // for current contract implementation
    await(await sub_service.setTierData(1,yearTS,toBN(50).mul(USDdecimals), 20, 1, 5)).wait();
    await(await sub_service.setTierData(2,yearTS,toBN(100).mul(USDdecimals), 20, 1, 15)).wait();
    await(await sub_service.setTierData(3,yearTS,toBN(300).mul(USDdecimals), 20, 1, 45)).wait();
    await(await sub_service.setTierData(10,yearTS,toBN(10000).mul(USDdecimals),0,3000,10000)).wait();

    // pause profitDistribution functionality

    await (await sub_service.pauseProfitDistribution()).wait();

    console.log("isProfitDistibutionPaused : ", await sub_service.isProfitDistributionPaused());

    console.log("completed");

}
  
