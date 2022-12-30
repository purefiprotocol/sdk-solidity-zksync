import '@matterlabs/hardhat-zksync-deploy';
import '@matterlabs/hardhat-zksync-solc';
import 'hardhat-abi-exporter';

module.exports = {
  zksolc: {
    version: '1.2.0',
    compilerSource: 'binary',
    settings: {
      optimizer: {
        enabled: true,
      },
      experimental: {
        dockerImage: 'matterlabs/zksolc',
        tag: 'v1.2.0',
      },
    },
  },
  zkSyncDeploy: {
    zkSyncNetwork: 'https://zksync2-testnet.zksync.dev',
    ethNetwork: 'goerli'
  },
  networks: {
    hardhat: {
      zksync: true,
    },
  },
  solidity: {
    version: '0.8.16',
  },
};

