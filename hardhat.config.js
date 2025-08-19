import hardhatViem from "@nomicfoundation/hardhat-viem";

/** @type import('hardhat/config').HardhatUserConfig */
export default {
  solidity: {
    version: "0.8.30",
    settings: {
      viaIR: true,  // Keep this - your contract needs it
      optimizer: {
        enabled: true,
        runs: 800,
      },
    },
  },
  plugins: [
    hardhatViem,  // Add the Viem plugin
  ],
  networks: {
    hardhat: {
      chainId: 1337,
      type: "http",
      url: "http://127.0.0.1:8545"
    },
    localhost: {
      url: "http://127.0.0.1:8545",
      chainId: 1337,
      type: "http"
    },
    // Add other networks as needed
    // sepolia: {
    //   url: process.env.SEPOLIA_URL || "",
    //   accounts: process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    //   type: "http"
    // },
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts", // Keep same artifacts directory for thirdweb compatibility
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: "USD",
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
}; 