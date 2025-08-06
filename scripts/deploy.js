const { ethers } = require("hardhat");

async function main() {
  console.log("Deploying contracts...");

  // Get signers
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);

  // Deploy FakeDai
  console.log("Deploying FakeDai...");
  const FakeDai = await ethers.getContractFactory("FakeDai");
  const fakeDai = await FakeDai.deploy();
  await fakeDai.waitForDeployment();
  console.log("FakeDai deployed to:", await fakeDai.getAddress());

  // Deploy ConditionalTokens
  console.log("Deploying ConditionalTokens...");
  const ConditionalTokens = await ethers.getContractFactory("ConditionalTokens");
  const conditionalTokens = await ConditionalTokens.deploy();
  await conditionalTokens.waitForDeployment();
  console.log("ConditionalTokens deployed to:", await conditionalTokens.getAddress());

  // Deploy LMSR
  console.log("Deploying LMSR...");
  const LMSR = await ethers.getContractFactory("LsLMSR");
  const lmsr = await LMSR.deploy(
    await conditionalTokens.getAddress(),
    await fakeDai.getAddress(),
    deployer.address
  );
  await lmsr.waitForDeployment();
  console.log("LMSR deployed to:", await lmsr.getAddress());

  // Mint some DAI to deployer for testing
  console.log("Minting test DAI...");
  await fakeDai.mint(deployer.address, ethers.parseEther("10000"));
  console.log("Minted 10,000 DAI to deployer");

  console.log("\nDeployment Summary:");
  console.log("===================");
  console.log("FakeDai:", await fakeDai.getAddress());
  console.log("ConditionalTokens:", await conditionalTokens.getAddress());
  console.log("LMSR:", await lmsr.getAddress());
  console.log("Deployer:", deployer.address);
  console.log("Deployer DAI Balance:", ethers.formatEther(await fakeDai.balanceOf(deployer.address)));

  console.log("\nTo setup a market, call:");
  console.log(`lmsr.setup(oracle, questionId, 2, bInput, initialSubsidy, overround)`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 