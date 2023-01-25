import '@matterlabs/hardhat-zksync-deploy';
import '@matterlabs/hardhat-zksync-solc';
import 'hardhat-abi-exporter';
import { HardhatUserConfig } from 'hardhat/types';


module.exports = {
  zksolc: {
    version: '1.2.2',
    compilerSource: 'binary',
    settings: {
      optimizer: {
        enabled: true,
      },
      experimental: {
        dockerImage: 'matterlabs/zksolc',
        tag: 'v1.2.2',
      },
    },
  },
  networks: {
    hardhat: {
      zksync: true,
    },
    zkSyncTestnet: {
      url: 'https://zksync2-testnet.zksync.dev',
      ethNetwork: 'goerli', // Can also be the RPC URL of the network (e.g. `https://goerli.infura.io/v3/<API_KEY>`)
      zksync: true,
    },
  },
  solidity: {
    version: '0.8.16',
  },
};
