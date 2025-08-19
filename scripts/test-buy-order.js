import { network } from "hardhat";

async function main() {
  console.log("Testing Buy Order Function...");
  
  const { viem } = await network.connect();
  
  // Get the deployer account
  const [deployer] = await viem.getWalletClients();
  console.log("Deployer address:", deployer.account.address);
  
  // Get contract addresses (you'll need to update these with your actual addresses)
  // You can either hardcode them or get them from a previous deployment
  const fakeUsdcAddress = "0x5FbDB2315678afecb367f032d93F642f64180aa3"; // Update this
  const conditionalTokensAddress = "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512"; // Update this
  const lmsrAddress = "0x9fE46736679d2D9a65F0992F2272dE9c3C7f6db0"; // Update this
  
  console.log("Using contracts:");
  console.log("FakeUSDC:", fakeUsdcAddress);
  console.log("ConditionalTokens:", conditionalTokensAddress);
  console.log("LMSR:", lmsrAddress);
  
  // Get contract instances
  const fakeUsdc = await viem.getContractAt("FakeUsdc", fakeUsdcAddress);
  const conditionalTokens = await viem.getContractAt("ConditionalTokens", conditionalTokensAddress);
  const lmsr = await viem.getContractAt("LsLMSR", lmsrAddress);
  
  // Check deployer's USDC balance
  console.log("\n=== Checking Balances ===");
  const usdcBalance = await fakeUsdc.read.balanceOf([deployer.account.address]);
  console.log("Deployer USDC balance:", usdcBalance / 10n**6n, "USDC");
  
  // Check LMSR allowance
  const allowance = await fakeUsdc.read.allowance([deployer.account.address, lmsrAddress]);
  console.log("LMSR allowance:", allowance / 10n**6n, "USDC");
  
  // Test a simple buy order
  console.log("\n=== Testing Buy Order ===");
  
  try {
    // Buy $100 USDC worth of outcome 0 (first outcome)
    const buyAmount = 100n * 10n**6n; // $100 USDC (6 decimals)
    const outcome = 0; // First outcome (index 0)
    
    console.log(`Attempting to buy $100 USDC worth of outcome ${outcome}...`);
    
    // Call the buy function
    const tx = await lmsr.write.buy([
      outcome,           // _outcome
      buyAmount          // _cost
    ]);
    
    console.log("Buy order successful!");
    console.log("Transaction hash:", tx);
    
    // Check new balances
    const newUsdcBalance = await fakeUsdc.read.balanceOf([deployer.account.address]);
    console.log("New USDC balance:", newUsdcBalance / 10n**6n, "USDC");
    
    // Check if we received outcome tokens
    // You might need to check the ConditionalTokens contract for this
    console.log("Buy order completed successfully!");
    
  } catch (error) {
    console.error("Error executing buy order:", error);
    
    // Try to get more details about the error
    if (error.message) {
      console.error("Error message:", error.message);
    }
  }
  
  console.log("\n=== Buy Order Test Complete ===");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
