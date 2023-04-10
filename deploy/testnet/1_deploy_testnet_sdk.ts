import * as ethers from 'ethers';
import hre from "hardhat";
import { BigNumber, utils } from "ethers";

//**** PUREFI SDK DEPLOYMENT SCRIPT *******//
//**** TESTNET ONLY                 *******//

// params for verifier

const PARAM_DEFAULT_AML_GRACETIME_KEY = 3;
const DEFAULT_GRACETIME_VALUE = 300;

const DEFAULT_AML_RULE = 431050;
const DEFAULT_KYC_RULE = 777;
const DEFAULT_KYCAML_RULE = 731090;

const PARAM_TYPE1_DEFAULT_AML_RULE = 4;
const PARAM_TYPE1_DEFAULT_KYC_RULE = 5;
const PARAM_TYPE1_DEFAULT_KYCAML_RULE = 6;

const PROXY_ADMIN_ADDRESS = "";
const decimals = BigNumber.from(10).pow(18);

// issuer_registry params

const VALID_ISSUER_ADDRESS = "0x592157ab4c6FADc849fA23dFB5e2615459D1E4e5";
const PROOF = utils.keccak256(utils.toUtf8Bytes("PureFi Stage Issuer")); 
const ADMIN = "0xcE14bda2d2BceC5247C97B65DBE6e6E570c4Bb6D";  // admin of issuer_registry


// SUBSCRIPTION_SERVICE params

const UFI_TOKEN = "0x70892902C0BfFdEEAac711ec48F14c00b0fa7E3A";
const TOKEN_BUYER = "";
const PROFIT_COLLECTION_ADDRESS = "0xcE14bda2d2BceC5247C97B65DBE6e6E570c4Bb6D";


async function main(){

    if ( PROOF.length == 0 || ADMIN.length == 0 ){
        throw new Error('ADMIN or PROOF variable is missed');
    }

    const PPROXY = await ethers.getContractFactory("PPRoxy");
    const PPROXY_ADMIN = await ethers.getContractFactory("PProxyAdmin");

    const WHITELIST = await ethers.getContractFactory("PureFiWhitelist");
    const ISSUER_REGISTRY = await ethers.getContractFactory("PureFiIssuerRegistry");
    const VERIFIER = await ethers.getContractFactory("PureFiVerifier");
    const SUBSCRIPTION_SERVICE = await ethers.getContractFactory("PureFiSubscriptionService");
    const TOKEN_BUYER = await ethers.getContractFactory("PureFiTokenBuyerPolygon");

    // DEPLOY PROXY_ADMIN //
    // ------------------------------------------------------------------- //
    var actual_proxy_admin;
    if(PROXY_ADMIN_ADDRESS.length>0){
        actual_proxy_admin = await ethers.getContractAt("PProxyAdmin", PROXY_ADMIN_ADDRESS);
    } else {
        console.log("Deploying new proxy admin...");
        actual_proxy_admin = await PPROXY_ADMIN.deploy();
        await actual_proxy_admin.deployed();
        await new Promise(resolve => setTimeout(resolve, 3000)); // 3 sec
    }
    const proxy_admin = actual_proxy_admin
    
    console.log("PROXY_ADMIN address : ", proxy_admin.address);
    

    // DEPLOY ISSUER_REGISTRY //
    // ------------------------------------------------------------------- //
    const issuer_registry_mastercopy = await ISSUER_REGISTRY.deploy();
    await issuer_registry_mastercopy.deployed();

    console.log("ISSUER_REGISTRY_MASTERCOPY address : ", issuer_registry_mastercopy.address);
    await new Promise(resolve => setTimeout(resolve, 3000)); // 3 sec

    const issuer_registry_proxy = await PPROXY.deploy(issuer_registry_mastercopy.address, proxy_admin.address, "0x");
    await issuer_registry_proxy.deployed();

    console.log("issuer_registry address : ", issuer_registry_proxy.address);
    await new Promise(resolve => setTimeout(resolve, 3000)); // 3 sec

    // initialize issuer_registry
    const issuer_registry = await ethers.getContractAt("PureFiIssuerRegistry", issuer_registry_proxy.address);

    await (await issuer_registry.initialize(ADMIN)).wait();

    // set issuer
    await issuer_registry.register(VALID_ISSUER_ADDRESS, PROOF);


    // DEPLOY WHITELIST // 
    // ------------------------------------------------------------------- //
    
    const whitelist_mastercopy = await WHITELIST.deploy();
    await whitelist_mastercopy.deployed();

    console.log("whitelist_mastercopy address : ", whitelist_mastercopy.address);
    await new Promise(resolve => setTimeout(resolve, 3000)); // 3 sec

    const whitelist_proxy = await PPROXY.deploy(whitelist_mastercopy.address, proxy_admin.address, "0x");
    await whitelist_proxy.deployed();

    console.log("whitelist_proxy address : ", whitelist_proxy.address);
    await new Promise(resolve => setTimeout(resolve, 3000)); // 3 sec

    const whitelist = await ethers.getContractAt("PureFiWhitelist", whitelist_proxy.address);

    // initialize whitelist
    await(await whitelist.initialize(issuer_registry.address)).wait();

    // DEPLOY VERIFIER // 
    // ------------------------------------------------------------------- //

    console.log("Deploying verifier...");
    const verifier_mastercopy = await VERIFIER.deploy();
    await verifier_mastercopy.deployed();

    console.log("verifier_mastercopy address : ", verifier_mastercopy.address);
    await new Promise(resolve => setTimeout(resolve, 3000)); // 3 sec

    const verifier_proxy = await PPROXY.deploy(verifier_mastercopy.address, proxy_admin.address, "0x");
    await verifier_proxy.deployed();

    console.log("verifier_proxy address : ", verifier_proxy.address);
    await new Promise(resolve => setTimeout(resolve, 3000)); // 3 sec
    
    // initialize verifier
    const verifier = await ethers.getContractAt("PureFiVerifier", verifier_proxy.address);
    await(await verifier.initialize(issuer_registry.address, whitelist.address)).wait();

    // set verifier params

    await(await verifier.setUint256(PARAM_DEFAULT_AML_GRACETIME_KEY, DEFAULT_GRACETIME_VALUE)).wait();

    await(await verifier.setUint256(PARAM_TYPE1_DEFAULT_AML_RULE, DEFAULT_AML_RULE)).wait();

    await(await verifier.setUint256(PARAM_TYPE1_DEFAULT_KYC_RULE, DEFAULT_KYC_RULE)).wait();

    await(await verifier.setUint256(PARAM_TYPE1_DEFAULT_KYCAML_RULE, DEFAULT_KYCAML_RULE)).wait();
    
    await(await verifier.setString(1, "PureFiVerifier: Issuer signature invalid")).wait();
    await(await verifier.setString(2, "PureFiVerifier: Funds sender doesn't match verified wallet")).wait();
    await(await verifier.setString(3, "PureFiVerifier: Verification data expired")).wait();
    await(await verifier.setString(4, "PureFiVerifier: Rule verification failed")).wait();
    await(await verifier.setString(5, "PureFiVerifier: Credentials time mismatch")).wait();
    await(await verifier.setString(6, "PureFiVerifier: Data package invalid")).wait();

    // DEPLOY TOKEN_BUYER // 
    // ------------------------------------------------------------------- //

    const token_buyer = await TOKEN_BUYER.deploy();
    await token_buyer.deployed();
    console.log("Token_buyer address :", token_buyer.address);
    await new Promise(resolve => setTimeout(resolve, 3000)); // 3 sec

    // DEPLOY SUBSCRIPTION_SERVICE // 
    // ------------------------------------------------------------------- //

    const sub_service_mastercopy = await SUBSCRIPTION_SERVICE.deploy();
    
    console.log("Subscription master copy : ", sub_service_mastercopy.address);
    await new Promise(resolve => setTimeout(resolve, 3000)); // 3 sec

    const sub_service_proxy = await PPROXY.deploy(sub_service_mastercopy.address, proxy_admin.address, "0x");
    await sub_service_proxy.deployed();    

    console.log("Subscription service address : ", sub_service_proxy.address);
    await new Promise(resolve => setTimeout(resolve, 3000)); // 3 sec

    // initialize sub_service 
    const sub_service = await ethers.getContractAt("PureFiSubscriptionService", sub_service_proxy.address);
    await(await sub_service.initialize(
        ADMIN,
        UFI_TOKEN,
        token_buyer.address,
        PROFIT_COLLECTION_ADDRESS
    )).wait();

    let yearTS = 86400*365;
    let USDdecimals = decimals;//10^18 // for current contract implementation
    await(await sub_service.setTierData(1,yearTS,BigNumber.from(50).mul(USDdecimals),20,1,5)).wait();
    await(await sub_service.setTierData(2,yearTS,BigNumber.from(100).mul(USDdecimals),20,1,15)).wait();
    await(await sub_service.setTierData(3,yearTS,BigNumber.from(300).mul(USDdecimals),20,1,45)).wait();
  

    // pause profitDistribution functionality

    await (await sub_service.pauseProfitDistribution()).wait();

    console.log("isProfitDistibutionPaused : ", await sub_service.isProfitDistributionPaused());

}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
  