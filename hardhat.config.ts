import '@matterlabs/hardhat-zksync-deploy';
import '@matterlabs/hardhat-zksync-solc';
import 'hardhat-abi-exporter';
import { HardhatUserConfig } from 'hardhat/types';


module.exports = {
  zksolc: {
    version: "1.2.3",
    compilerSource: "binary",
    settings: {},
  },
  networks: {
    zkSyncTestnet: {
      url: "https://zksync2-testnet.zksync.dev",
      ethNetwork: "goerli", // Can also be the RPC URL of the network (e.g. `https://goerli.infura.io/v3/<API_KEY>`)
      zksync: true,
    },
  },
  defaultNetwork: "zkSyncTestnet",
  solidity: {
    version: '0.8.16',
  },
};
