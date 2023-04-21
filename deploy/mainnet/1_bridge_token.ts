import { Provider, utils, Wallet, Contract } from 'zksync-web3';
import * as ethers from 'ethers';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import EthCrypto from 'eth-crypto';
import { Deployer } from '@matterlabs/hardhat-zksync-deploy';

import { privateKey } from "../../network_keys/secrets.json";
import fs from 'fs';


const UFI_TOKEN_ADDRESS = "0xcDa4e840411C00a614aD9205CAEC807c7458a0E3"; //mainnet Ethereum
const AMOUNT = "11";

const decimals = toBN(10).pow(18);


function toBN(number: any) {
    return ethers.BigNumber.from(number);
}
/**
 * $ yarn hardhat deploy-zksync --script deploy/testnet/1_deploy_testnet_sdk.ts
 */
export default async function (hre : HardhatRuntimeEnvironment){

    const provider = new Provider(hre.config.networks.zkSyncTestnet.url);
    const wallet = new Wallet(privateKey, provider);
    const deployer = new Deployer(hre, wallet);

   // Deposit ERC20 tokens to L2
  const depositHandle = await deployer.zkWallet.deposit({
    to: deployer.zkWallet.address,
    token: UFI_TOKEN_ADDRESS,
    amount: ethers.utils.parseEther(AMOUNT), // assumes ERC20 has 18 decimals
    // performs the ERC20 approve action
    approveERC20: true,
  });

  console.log(`Deposit transaction sent ${depositHandle.hash}`);
  console.log(`Waiting for deposit to be processed in L2...`);
  // Wait until the deposit is processed on zkSync
  await depositHandle.wait();
  console.log(`ERC20 tokens available in L2`);

}
  
