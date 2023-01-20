import { Provider, utils, Wallet } from 'zksync-web3';
import * as ethers from 'ethers';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import EthCrypto, { sign, util } from 'eth-crypto';
import { Deployer } from '@matterlabs/hardhat-zksync-deploy';

import { privateKey } from "../network_keys/secrets.json";
import { defaultAbiCoder, keccak256, recoverAddress, solidityPack } from 'ethers/lib/utils';

const PAYMASTER_ADDRESS = "0xaaE07A34b767bD96677Cb3f2a58994DA87f28c47";

const FILTERED_POOL_ADDRESS = "0xA8830e0033D5b4135A45cF797DcBB581cDfE32c6";

const TEST_TOKEN_ADDRESS = "0xd10A0c013ca49CF5D5841498d6D901a5Ac156074";

const privateKeyIssuer = 'e3ad95aa7e9678e96fb3d867c789e765db97f9d2018fca4068979df0832a5178';

const EMPTY_WALLET_PRIVATE_KEY = "0x9f1f9daa4d7093111684d7043824bc98a863444cd1a9e2a7c85eebaeb9d8c04d";

const ISSUER_ADDRESS = EthCrypto.publicKey.toAddress(EthCrypto.publicKeyByPrivateKey(privateKeyIssuer));

const WALLET_ADDRESS = "0xB5a045b7352dB0A2c08228b60629a94CDc09A651";

const fundPaymaster = async (hre: HardhatRuntimeEnvironment, provider: any, valueToSend: any) => {

    console.log(`Funding Paymaster for ${ethers.utils.formatEther(valueToSend)} ETH`);
    const wallet = new Wallet(privateKey, provider);
    const deployer = new Deployer(hre, wallet);
    await (
        await deployer.zkWallet.sendTransaction({
            to: PAYMASTER_ADDRESS,
            value: valueToSend,
        })
    ).wait();
    console.log("After funding paymaster");
}

const currentTimestamp = async (hre: HardhatRuntimeEnvironment) => {
    const provider = new Provider(hre.config.zkSyncDeploy.zkSyncNetwork);   
    const blockNum = provider.getBlockNumber();
    const block = await provider.getBlock(blockNum);
    return block.timestamp;
}

const preparePureFiPaymasterParams = async (
    hre: HardhatRuntimeEnvironment,
    type: number,
    ruleId: number | ethers.BigNumber,
    sender: string,
    receiver?: string,
    token?: string,
    amount?: ethers.BigNumber,
    payload?: string

) => {

    const timestamp = await currentTimestamp(hre);
    const sessionId = 1;

    const pureFiPackage = await _getPureFiPackage(
        type,
        ruleId,
        sessionId,
        sender,
        receiver,
        token,
        amount,
        payload
    );

    const signature = await _signPureFiPackage(timestamp, pureFiPackage, privateKeyIssuer);


    // console.log("Signature : ", signature);

    // console.log("timestamp + package hash :", defaultAbiCoder.encode(
    //     ["uint64", "bytes"],
    //     [timestamp, pureFiPackage]
    // ));


    const pureFiData = await _packPureFiData(timestamp, signature, pureFiPackage);

    const paymasterParams = utils.getPaymasterParams(
        PAYMASTER_ADDRESS,
        {
            type: "General",
            innerInput: pureFiData
        }
    );
    return paymasterParams;
}

const _getPureFiPackage = async (
    type: number,
    ruleId: number | ethers.BigNumber,
    sessionId: number,
    sender: string,
    receiver?: string,
    token?: string,
    amount?: ethers.BigNumber,
    payload?: string
) => {
    let pureFiPackage;
    if (type == 1) {
        pureFiPackage = ethers.utils.defaultAbiCoder.encode(
            ["uint8", "uint256", "uint256", "address"],
            [type, ruleId, sessionId, sender]
        );
    } else if (type == 2) {
        pureFiPackage = ethers.utils.defaultAbiCoder.encode(
            ["uint8", "uint256", "uint256", "address", "address", "address", "uint256"],
            [type, ruleId, sessionId, sender, receiver, token, amount]
        );
    } else if (type == 3) {
        pureFiPackage = ethers.utils.defaultAbiCoder.encode(
            ["uint8", "uint256", "uint256", "bytes"],
            [ruleId, sessionId, payload]
        );
    }

    return pureFiPackage;
}

const _signMessage = async (message: any, privateKey: any) => {

    const messageHash = keccak256(message);
    const signature = EthCrypto.sign(privateKey, messageHash);
    return signature;
}

const _signPureFiPackage = async (timestamp: number, purefipackage: any, privateKey: any) => {
    const message = solidityPack(
        ["uint64", "bytes"],
        [timestamp, purefipackage]
    );

    return _signMessage(message, privateKey);
}

const _packPureFiData = async (timestamp: number, signature: any, pureFiPackage: any) => {
    return defaultAbiCoder.encode(
        ["uint64", "bytes", "bytes"],
        [timestamp, signature, pureFiPackage]
    );
}


export default async function (hre: HardhatRuntimeEnvironment) {

    const provider = new Provider(hre.config.zkSyncDeploy.zkSyncNetwork);

    const wallet = new Wallet(privateKey, provider);

    console.log("Wallet address : ", wallet.address.toString() );
    
    const emptyWallet = new Wallet(EMPTY_WALLET_PRIVATE_KEY, provider);
    console.log("Empty wallet address : ", emptyWallet.address);

    // contracts
    const erc20Artifact = hre.artifacts.readArtifactSync("MyERC20");
    const erc20 = new ethers.Contract(TEST_TOKEN_ADDRESS, erc20Artifact.abi);

    const filteredPoolArtifact = hre.artifacts.readArtifactSync("FilteredPool");
    const filteredPool = new ethers.Contract(FILTERED_POOL_ADDRESS, filteredPoolArtifact.abi);

    const paymasterArtifact = hre.artifacts.readArtifactSync("PureFiPaymaster");
    const paymaster = new ethers.Contract(PAYMASTER_ADDRESS, paymasterArtifact.abi);

    // empty wallet erc20 balance 
    console.log("Empty wallet balance : ", await (await erc20.connect(emptyWallet).balanceOf(emptyWallet.address)).toString());

    const depositAmount = ethers.utils.parseEther('1');

    // approve

    if (true) {
        const depositRule = 12345;
        const paymasterParams = await preparePureFiPaymasterParams(
            hre,
            2,
            depositRule,
            emptyWallet.address,
            filteredPool.address,
            erc20.address,
            depositAmount);

        let gasPrice = await provider.getGasPrice();

        let gasLimit = await erc20.connect(emptyWallet).estimateGas.approve(
            filteredPool.address,
            depositAmount,
            {
                customData: {
                    ergsPerPubdata: utils.DEFAULT_ERGS_PER_PUBDATA_LIMIT,
                    paymasterParams: {
                        paymaster: paymasterParams.paymaster,
                        paymasterInput: paymasterParams.paymasterInput
                    }
                }
            });

        console.log("Approve gas limit : ", gasLimit.toString());

        let fee = gasPrice.mul(gasLimit);
        let valueToSend = fee.add(ethers.utils.parseEther('0.0001'));

        await fundPaymaster(hre, provider, valueToSend);

        await (
            await erc20.connect(emptyWallet).approve(
                filteredPool.address,
                depositAmount,
                {
                    maxFeePerGas: gasPrice,
                    maxPriorityFeePerGas: gasPrice,
                    gasLimit,
                    //paymaster info
                    customData: {
                        paymasterParams,
                        ergsPerPubdata: utils.DEFAULT_ERGS_PER_PUBDATA_LIMIT
                    },
                })
        ).wait();


        console.log("Success approve");
        console.log("Allowance : ", await (await erc20.connect(emptyWallet).allowance(emptyWallet.address, filteredPool.address)).toString());
    }
    // deposit erc20

    const context = await paymaster.connect(emptyWallet).getPureFiContextData(emptyWallet.address);

    console.log("Context : ", context);

    const paymasterBalanceBefore = await provider.getBalance(paymaster.address);
    console.log("Paymaster balance before deposit : ", paymasterBalanceBefore.toString());

    if(true){

        const gasPrice = await provider.getGasPrice();
        const depositRule = ethers.BigNumber.from(12345);

        console.log("DepositRule : ", depositRule);

        const paymasterParams = await preparePureFiPaymasterParams(
            hre,
            2,
            depositRule,
            emptyWallet.address,
            filteredPool.address,
            erc20.address,
            depositAmount);

        // const gasLimit = await filteredPool.connect(emptyWallet).estimateGas.depositTo(
        //     depositAmount,
        //     emptyWallet.address,
        //     {
        //         customData: {
        //             ergsPerPubdata: utils.DEFAULT_ERGS_PER_PUBDATA_LIMIT,
        //             paymasterParams: {
        //                 paymaster: paymasterParams.paymaster,
        //                 paymasterInput: paymasterParams.paymasterInput
        //             }
        //         }
        //     });

        // console.log("DepositTo Gas Limit : ", gasLimit);
        const gasLimit = 5993436;

        let fee = gasPrice.mul(gasLimit);
        let valueToSend = fee.add(ethers.utils.parseEther('0.02'));

        await fundPaymaster(hre, provider, valueToSend);

        const paymasterBalanceAfter = await provider.getBalance(paymaster.address);
        console.log("Paymaster balance after funding : ", paymasterBalanceAfter.toString());

        await (await filteredPool.connect(emptyWallet).depositTo(
            depositAmount,
            emptyWallet.address,
            {
                customData: {
                    ergsPerPubdata: utils.DEFAULT_ERGS_PER_PUBDATA_LIMIT,
                    paymasterParams: {
                        paymaster: paymasterParams.paymaster,
                        paymasterInput: paymasterParams.paymasterInput
                    }
                }
            })).wait();
        console.log("Successful deposit");
    }

    const paymasterBalanceAfterDeposit = await provider.getBalance(paymaster.address);
    console.log("Paymaster balance after deposit: ", paymasterBalanceAfterDeposit.toString());

    
}

