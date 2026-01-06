import { network } from "hardhat";

async function main() {
  console.log("Deploying LMSR Contract...");
  
  const { viem } = await network.connect();
  
  // Get the deployer account
  const [deployer] = await viem.getWalletClients();
  console.log("Deployer address:", deployer.account.address);
  
  // Deploy Nash first
  console.log("Deploying Nash...");
  const nash = await viem.deployContract("Nash");
  console.log("Nash deployed to:", nash.address);
  
  // Deploy ConditionalTokens
  console.log("Deploying ConditionalTokens...");
  const conditionalTokens = await viem.deployContract("ConditionalTokens");
  console.log("ConditionalTokens deployed to:", conditionalTokens.address);
  
  // Deploy LMSR contract with both addresses
  console.log("Deploying LMSR Contract...");
  const lmsr = await viem.deployContract("LsLMSR", [
    conditionalTokens.address,  // _ct parameter
    nash.address,           // _token parameter
    deployer.account.address    // initialOwner parameter
  ]);
  
  console.log("LMSR Contract deployed to:", lmsr.address);
  
  // Mint 1,000,000 NASH to the deployer
  console.log("Minting 1,000,000 Nash to deployer...");
  const mintAmount = 1000000n * 10n**18n; // 1M Nash (18 decimals)
  
  try {
    await nash.write.mint([deployer.account.address, mintAmount]);
    console.log("Successfully minted 1,000,000 Nash to deployer");
    
    // Check the balance
    const balance = await nash.read.balanceOf([deployer.account.address]);
    console.log("Deployer Nash balance:", balance / 10n**18n, "Nash");
    
  } catch (error) {
    console.error("Error minting Nash:", error);
    return;
  }
  
  // Approve LMSR contract to spend Nash on behalf of deployer
  console.log("Approving LMSR contract to spend deployer's Nash...");
  
  try {
    await nash.write.approve([lmsr.address, mintAmount]);
    console.log("Successfully approved LMSR contract to spend Nash");
    
    // Check the allowance
    const allowance = await nash.read.allowance([deployer.account.address, lmsr.address]);
    console.log("LMSR allowance:", allowance / 10n**18n, "NASH");
    
  } catch (error) {
    console.error("Error approving Nash:", error);
    return;
  }
  
  // Setup the market using the setup function
  console.log("Setting up the market...");
  
  // Setup parameters as specified
  const questionId = "0x728a0aa23bd0b9acce3ae6f28cda3a1deb72f89659244c15e7927dfd44731f18";
  const numOutcomes = 2;
  const bInput = 10000000000000000000000n;
  const initialSubsidy = 6932000000000000000000n;
  const overround = 200n;
  
  try {
    // Call the setup function with your parameters
    await lmsr.write.setup([
      questionId,           // _questionId
      numOutcomes,          // _numOutcomes
      bInput,               // _b (liquidity parameter)
      initialSubsidy,       // _initialSubsidy
      overround             // _overround
    ]);
    
    console.log("Market setup successful!");
    console.log("Question ID:", questionId);
    console.log("Number of outcomes:", numOutcomes);
    console.log("B input (liquidity):", bInput.toString());
    console.log("Initial subsidy:", initialSubsidy.toString());
    console.log("Overround:", overround.toString());
    
  } catch (error) {
    console.error("Error setting up market:", error);
  }
  
  console.log("LMSR deployment, setup, and configuration complete!");
  
  // Summary of all deployed contracts and actions
  console.log("\n=== Deployment Summary ===");
  console.log("Nash:", nash.address);
  console.log("ConditionalTokens:", conditionalTokens.address);
  console.log("LMSR Contract:", lmsr.address);
  console.log("Deployer:", deployer.account.address);
  console.log("Nash Minted:", "1,000,000 Nash");
  console.log("LMSR Approved to spend:", "1,000,000 Nash");
  console.log("\n=== Market Configuration ===");
  console.log("Question ID:", questionId);
  console.log("Outcomes:", numOutcomes);
  console.log("Liquidity (B):", bInput.toString());
  console.log("Initial Subsidy:", initialSubsidy.toString());
  console.log("Overround:", overround.toString());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });