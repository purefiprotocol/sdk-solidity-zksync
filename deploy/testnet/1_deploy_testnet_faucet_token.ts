import { BigNumber } from "ethers";
import { config } from "hardhat";
import hre from "hardhat";

import { Provider, utils, Wallet } from 'zksync-web3';
import * as ethers from 'ethers';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import EthCrypto from 'eth-crypto';
import { Deployer } from '@matterlabs/hardhat-zksync-deploy';
import { privateKey } from "../../network_keys/secrets.json";
import fs from 'fs';
import { Address } from 'zksync-web3/build/src/types';
import { arrayify } from 'ethers/lib/utils';
const NETWORK_URL = 'https://zksync2-testnet.zksync.dev';

const decimals = BigNumber.from(10).pow(18);
const SUPPLY = BigNumber.from("100000000").mul(decimals);
const NAME = "TestUFI";
const SYMBOL = "tUFI";


async function main(){

    const provider = new Provider(NETWORK_URL);

    const wallet = new Wallet(privateKey, provider);

    const deployer = new Deployer(hre, wallet);

    // deploy erc20
    const erc20Artifact = await deployer.loadArtifact("TestTokenFaucet");

    
    const token = await deployer.deploy(erc20Artifact, [SUPPLY, NAME, SYMBOL]);

    console.log("Test UFI address : ", token.address);
}


main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
  