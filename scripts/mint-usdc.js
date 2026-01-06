async function main() {
  console.log("Deploying LMSR Contract...");
  
  const { viem } = await network.connect();
  
  // Get the deployer account
  const [deployer] = await viem.getWalletClients();
  console.log("Deployer address:", deployer.account.address);
  
  // Deploy FakeUSDC first
  console.log("Deploying FakeUSDC...");
  const fakeUsdc = await viem.deployContract("FakeUsdc");
  console.log("FakeUSDC deployed to:", fakeUsdc.address);
  
  // Deploy ConditionalTokens
  console.log("Deploying ConditionalTokens...");
  const conditionalTokens = await viem.deployContract("ConditionalTokens");
  console.log("ConditionalTokens deployed to:", conditionalTokens.address);
  
  // Deploy LMSR contract with both addresses
  console.log("Deploying LMSR Contract...");
  const lmsr = await viem.deployContract("LsLMSR", [
    conditionalTokens.address,  // _ct parameter
    fakeUsdc.address,           // _token parameter
    deployer.account.address    // initialOwner parameter
  ]);
  
  console.log("LMSR Contract deployed to:", lmsr.address);
  
  // Mint 1,000,000 USDC to the deployer
  console.log("Minting 1,000,000 USDC to deployer...");
  const mintAmount = 1000000n * 10n**6n; // 1M USDC (6 decimals)
  
  try {
    await fakeUsdc.write.mint([deployer.account.address, mintAmount]);
    console.log("Successfully minted 1,000,000 USDC to deployer");
    
    // Check the balance
    const balance = await fakeUsdc.read.balanceOf([deployer.account.address]);
    console.log("Deployer USDC balance:", balance / 10n**6n, "USDC");
    
  } catch (error) {
    console.error("Error minting USDC:", error);
    return;
  }
  
  // Approve LMSR contract to spend USDC on behalf of deployer
  console.log("Approving LMSR contract to spend deployer's USDC...");
  
  try {
    await fakeUsdc.write.approve([lmsr.address, mintAmount]);
    console.log("Successfully approved LMSR contract to spend USDC");
    
    // Check the allowance
    const allowance = await fakeUsdc.read.allowance([deployer.account.address, lmsr.address]);
    console.log("LMSR allowance:", allowance / 10n**6n, "USDC");
    
  } catch (error) {
    console.error("Error approving USDC:", error);
    return;
  }
  
  // Setup the market using the setup function
  console.log("Setting up the market...");
  
  // Setup parameters as specified
  const questionId = "0x728a0aa23bd0b9acce3ae6f28cda3a1deb72f89659244c15e7927dfd44731f18";
  const numOutcomes = 2;
  const bInput = 10000000000n;
  const initialSubsidy = 6932000000n;
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
    

    
  } catch (error) {
    console.error("Error setting up market:", error);
  }
  
  console.log("LMSR deployment, setup, and configuration complete!");
  
  // Summary of all deployed contracts and actions
  console.log("\n=== Deployment Summary ===");
  console.log("FakeUSDC:", fakeUsdc.address);
  console.log("ConditionalTokens:", conditionalTokens.address);
  console.log("LMSR Contract:", lmsr.address);
  console.log("Deployer:", deployer.account.address);
  console.log("USDC Minted:", "1,000,000 USDC");
  console.log("LMSR Approved to spend:", "1,000,000 USDC");
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
