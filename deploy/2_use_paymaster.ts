import { Provider, utils, Wallet } from 'zksync-web3';
import * as ethers from 'ethers';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import EthCrypto from 'eth-crypto';
import { Deployer } from '@matterlabs/hardhat-zksync-deploy';

import { privateKey } from "../network_keys/secrets.json";
import { usdc, usdt, paymaster, mockPlugin, filteredPool, testToken } from "../addresses.json";
import { defaultAbiCoder, keccak256, parseEther, solidityPack } from 'ethers/lib/utils';


const NETWORK_URL = 'https://zksync2-testnet.zksync.dev';
const EMPTY_WALLET_ADDRESS = "0x4DF6Ba41aAF6209A9C47856feF7Fb8058e93d7Ae";
const STUB_ADDRESS = "0x0000000000000000000000000000000000000001";

const TEST_TOKEN = testToken;
const FILTERED_POOL_ADDRESS = filteredPool;
const PAYMASTER_ADDRESS = paymaster;

const privateKeyIssuer = 'e3ad95aa7e9678e96fb3d867c789e765db97f9d2018fca4068979df0832a5178';

const EMPTY_WALLET_PRIVATE_KEY = "0x9f1f9daa4d7093111684d7043824bc98a863444cd1a9e2a7c85eebaeb9d8c04d";

const decimals = ethers.BigNumber.from(10).pow(18);


export default async function (hre: HardhatRuntimeEnvironment) {

    const provider = new Provider(NETWORK_URL);

    const wallet = new Wallet(privateKey, provider);

    const deployer = new Deployer(hre, wallet);

    const paymasterArtifact = await deployer.loadArtifact("PureFiPaymaster");
    const paymasterContract = new ethers.Contract(paymaster, paymasterArtifact.abi);

    console.log(" paymaster version :", (await paymasterContract.connect(wallet).version()).toString());
    ;
    const tokenToWhitelist = "0x0000000000000000000000000000000000000002";

    // console.log("   Whitelist token");
    // await whitelistToken(tokenToWhitelist, paymasterContract, wallet);

    // console.log("   Delist token");
    // await delistToken(tokenToWhitelist, paymasterContract, wallet);

    const emptyWallet = new Wallet(EMPTY_WALLET_PRIVATE_KEY, provider);
    console.log("Empty wallet address : ", emptyWallet.address);

    console.log("   UsePaymaster");
    await usePaymaster(emptyWallet, wallet, deployer, hre, provider);

}

async function delistToken(token: string, paymaster: ethers.Contract, wallet: Wallet) {
    await (await paymaster.connect(wallet).delistToken(token)).wait();

    const isWhitelisted = await paymaster.connect(wallet).isWhitelisted(token);

    if (!isWhitelisted) {
        console.log("Token is delisted");
    } else {
        throw Error("Tokens is not delisted");
    }


}

async function whitelistToken(token: string, paymaster: ethers.Contract, wallet: Wallet) {
    await (await paymaster.connect(wallet).whitelistToken(token)).wait();

    const isWhitelisted = await paymaster.connect(wallet).isWhitelisted(token);

    if (isWhitelisted) {
        console.log("Token is whitelisted");
    } else {
        throw Error("Tokens is not whitelisted");
    }
}

async function usePaymaster(
    emptyWallet: Wallet,
    wallet: Wallet,
    deployer: Deployer,
    hre: HardhatRuntimeEnvironment,
    provider: Provider
) {

    // contracts
    const erc20Artifact = hre.artifacts.readArtifactSync("MyERC20");
    const erc20 = new ethers.Contract(TEST_TOKEN, erc20Artifact.abi);

    const usdcContract = new ethers.Contract(usdc, erc20Artifact.abi);

    const filteredPoolArtifact = hre.artifacts.readArtifactSync("FilteredPool");
    const filteredPool = new ethers.Contract(FILTERED_POOL_ADDRESS, filteredPoolArtifact.abi);

    const paymasterArtifact = hre.artifacts.readArtifactSync("PureFiPaymaster");
    const paymaster = new ethers.Contract(PAYMASTER_ADDRESS, paymasterArtifact.abi);

    const depositAmount = ethers.utils.parseEther('1');

    // approve
    
    if (true) {
        console.log(" =========================== \n \tApprove \n =========================== ");
        const depositRule = 12345;
        let paymasterParams = await preparePureFiPaymasterParams(
            hre,
            parseEther("0.01"), // need to hardcode requiredETH because it is not available before gas estimation
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
                    gasPerPubdata: utils.DEFAULT_GAS_PER_PUBDATA_LIMIT,
                    paymasterParams: {
                        paymaster: paymasterParams.paymaster,
                        paymasterInput: paymasterParams.paymasterInput
                    }
                }
            });


        console.log("Approve gas limit : ", gasLimit.toString());

        let fee = gasPrice.mul(gasLimit);
        // update paymasterParams after we get requiredEth for tx
        paymasterParams = await preparePureFiPaymasterParams(
            hre,
            fee,
            2,
            depositRule,
            emptyWallet.address,
            filteredPool.address,
            erc20.address,
            depositAmount);

        console.log("Fee for ERC20 approve : ", fee.toString());

        let valueToSend = fee;
        await fundPaymaster(hre, provider, valueToSend);

        let emptyWalletUSDCBalanceBefore = await usdcContract.connect(wallet).balanceOf(emptyWallet.address);
        let paymasterUSDCBalanceBefore =  await usdcContract.connect(wallet).balanceOf(paymaster.address);

        const tx = await (
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
                        gasPerPubdata: utils.DEFAULT_GAS_PER_PUBDATA_LIMIT
                    },
                })
        ).wait();

        console.log("Success approve");

        let emptyWalletUSDCBalanceAfter = await usdcContract.connect(wallet).balanceOf(emptyWallet.address);
        let paymasterUSDCBalanceAfter =  await usdcContract.connect(wallet).balanceOf(paymaster.address);

        console.log(" =========================== \n Balances diff \n ===========================  ");
        console.log(
            "emptyWallet USDC balances :\n Before : ", 
            emptyWalletUSDCBalanceBefore.toString(), 
            "\n After : ", 
            emptyWalletUSDCBalanceAfter.toString() 
        );

        console.log(
            "paymaster USDC balances :\n Before : ", 
            paymasterUSDCBalanceBefore.toString(), 
            "\n After : ", 
            paymasterUSDCBalanceAfter.toString()
        );

        console.log(" emptyWallet USDC balance diff : ", emptyWalletUSDCBalanceBefore.sub(emptyWalletUSDCBalanceAfter).toString());
        console.log(" paymaster USDC balance diff : ", paymasterUSDCBalanceAfter.sub(paymasterUSDCBalanceBefore).toString());
        // console.log("Allowance : ", await (await erc20.connect(emptyWallet).allowance(emptyWallet.address, filteredPool.address)).toString());
    }
    // deposit erc20


    if (true) {
        console.log(" =========================== \n \tDeposit \n =========================== ")
        const gasPrice = await provider.getGasPrice();
        const depositRule = ethers.BigNumber.from(12345);

        console.log("DepositRule : ", depositRule);

        let paymasterParams = await preparePureFiPaymasterParams(
            hre,
            parseEther("0.01"),
            2,
            depositRule,
            emptyWallet.address,
            filteredPool.address,
            erc20.address,
            depositAmount);

        let gasLimit = await filteredPool.connect(emptyWallet).estimateGas.depositTo(
            depositAmount,
            emptyWallet.address,
            {
                customData: {
                    gasPerPubdata: utils.DEFAULT_GAS_PER_PUBDATA_LIMIT,
                    paymasterParams: {
                        paymaster: paymasterParams.paymaster,
                        paymasterInput: paymasterParams.paymasterInput
                    }
                }
            });

        console.log("DepositTo Gas Limit : ", gasLimit.toString());

        let fee = gasPrice.mul(gasLimit);
        let valueToSend = fee;

        paymasterParams = await preparePureFiPaymasterParams(
            hre,
            fee,
            2,
            depositRule,
            emptyWallet.address,
            filteredPool.address,
            erc20.address,
            depositAmount);


        await fundPaymaster(hre, provider, valueToSend);

        const paymasterBalanceAfter = await provider.getBalance(paymaster.address);
        console.log("Paymaster balance after funding : ", paymasterBalanceAfter.toString());

        //balances before deposit
        const emptyWalletBalanceBefore = await (await erc20.connect(emptyWallet).balanceOf(emptyWallet.address)).toString();
        console.log("Empty wallet balance before deposit: ", emptyWalletBalanceBefore);

        const filteredPoolBalanceBefore = await (await erc20.connect(emptyWallet).balanceOf(filteredPool.address)).toString();
        console.log("FilteredPool balance before : ", filteredPoolBalanceBefore);

        const tx = await (await filteredPool.connect(emptyWallet).depositTo(
            depositAmount,
            emptyWallet.address,
            {
                maxFeePerGas: gasPrice,
                maxPriorityFeePerGas: gasPrice,
                gasLimit: gasLimit,
                customData: {
                    gasPerPubdata: utils.DEFAULT_GAS_PER_PUBDATA_LIMIT,
                    paymasterParams: {
                        paymaster: paymasterParams.paymaster,
                        paymasterInput: paymasterParams.paymasterInput
                    }
                }
            })).wait();
        console.log("Successful deposit");
    }

    //balances after deposit
    const emptyWalletBalanceAfter = await (await erc20.connect(emptyWallet).balanceOf(emptyWallet.address)).toString();
    console.log("Empty wallet balance after deposit: ", emptyWalletBalanceAfter);

    const filteredPoolBalanceAfter = await (await erc20.connect(emptyWallet).balanceOf(filteredPool.address)).toString()
    console.log("FilteredPool balance after : ", filteredPoolBalanceAfter);

}



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
    const provider = new Provider(NETWORK_URL);
    const blockNum = provider.getBlockNumber();
    const block = await provider.getBlock(blockNum);
    return block.timestamp;
}

const getMinTokenAllowance = async (hre: HardhatRuntimeEnvironment, requiredETH: ethers.BigNumberish) => {
    const provider = new Provider(NETWORK_URL);
    const wallet = new Wallet(privateKey, provider);
    const deployer = new Deployer(hre, wallet);

    const mockPluginArtifact = await deployer.loadArtifact("MockUniswapPlugin");
    const mockPluginContract = new ethers.Contract(mockPlugin, mockPluginArtifact.abi);

    const paymasterArtifact = await deployer.loadArtifact("PureFiPaymaster");
    const paymaster = new ethers.Contract(PAYMASTER_ADDRESS, paymasterArtifact.abi);

    const DENOM_PERCENTAGE = await paymaster.connect(wallet).DENOM_PERCENTAGE();
    const overheadPercentage = await paymaster.connect(wallet).overheadPercentage();

    let requiredAllowance = await mockPluginContract.connect(wallet).getMinTokensAmountForETH(usdc, requiredETH);
    console.log("Required allowance from mockplugin ( USDC decimals : 6 ): ", requiredAllowance.toString());

    requiredAllowance = requiredAllowance.mul( DENOM_PERCENTAGE + overheadPercentage ).div(DENOM_PERCENTAGE); // extra 20% for refunding
    return requiredAllowance;
}

const preparePureFiPaymasterParams = async (
    hre: HardhatRuntimeEnvironment,
    requiredETH: ethers.BigNumber,
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

    const pureFiData = await _packPureFiData(timestamp, signature, pureFiPackage);

    const allowance = await getMinTokenAllowance(hre, requiredETH);


    const paymasterParams = utils.getPaymasterParams(
        PAYMASTER_ADDRESS,
        {
            type: 'ApprovalBased',
            token: usdc,
            minimalAllowance: allowance,
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
