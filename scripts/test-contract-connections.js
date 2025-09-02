//test-contract-connections.js file
// scripts/test-contract-connections.js
import { network } from "hardhat";

async function main() {
  console.log("Testing Contract Connections...");
  
  const { viem } = await network.connect();
  
  // Get the deployer account
  const [deployer] = await viem.getWalletClients();
  console.log("Deployer address:", deployer.account.address);
  
  // We'll need to replace these with actual addresses
  const FAKE_USDC_ADDRESS = "0x5fbdb2315678afecb367f032d93f642f64180aa3";
  const CONDITIONAL_TOKENS_ADDRESS = "0xe7f1725e7734ce288f8367e1bb143e90bb3f0512";
  const LMSR_ADDRESS = "0x9fe46736679d2d9a65f0992f2272de9f3c7fa6e0";
  
  console.log("\n=== Testing Contract Connections ===");
  
  // Test 1: FakeUSDC Contract
  console.log("\n1. Testing FakeUSDC Contract...");
  try {
    const fakeUsdc = await viem.getContractAt("FakeUsdc", FAKE_USDC_ADDRESS);
    console.log("✓ Connected to FakeUSDC at:", fakeUsdc.address);
    
    // Test read functions
    const name = await fakeUsdc.read.name();
    const symbol = await fakeUsdc.read.symbol();
    const decimals = await fakeUsdc.read.decimals();
    const totalSupply = await fakeUsdc.read.totalSupply();
    
    console.log("  Name:", name);
    console.log("  Symbol:", symbol);
    console.log("  Decimals:", decimals);
    console.log("  Total Supply:", totalSupply / 10n**6n, "USDC");
    
  } catch (error) {
    console.error("✗ FakeUSDC connection failed:", error.message);
  }
  
  // Test 2: ConditionalTokens Contract
  console.log("\n2. Testing ConditionalTokens Contract...");
  try {
    const conditionalTokens = await viem.getContractAt("ConditionalTokens", CONDITIONAL_TOKENS_ADDRESS);
    console.log("✓ Connected to ConditionalTokens at:", conditionalTokens.address);
    
    // Test read functions (if available)
    console.log("  Contract connected successfully");
    
  } catch (error) {
    console.error("✗ ConditionalTokens connection failed:", error.message);
  }
  
  // Test 3: LMSR Contract
  console.log("\n3. Testing LMSR Contract...");
  try {
    const lmsr = await viem.getContractAt("LsLMSR", LMSR_ADDRESS);
    console.log("✓ Connected to LMSR at:", lmsr.address);
    
    // Test read functions
    const owner = await lmsr.read.owner();
    const condition = await lmsr.read.condition();
    const numOutcomes = await lmsr.read.numOutcomes();
    const b = await lmsr.read.b();
    
    console.log("  Owner:", owner);
    console.log("  Condition:", condition);
    console.log("  Number of outcomes:", numOutcomes);
    console.log("  Liquidity parameter (b):", b.toString());
    
  } catch (error) {
    console.error("✗ LMSR connection failed:", error.message);
  }
  
  // Test 4: Cross-Contract Interactions
  console.log("\n4. Testing Cross-Contract Interactions...");
  try {
    const fakeUsdc = await viem.getContractAt("FakeUsdc", FAKE_USDC_ADDRESS);
    const lmsr = await viem.getContractAt("LsLMSR", LMSR_ADDRESS);
    
    // Check user balance
    const userBalance = await fakeUsdc.read.balanceOf([deployer.account.address]);
    console.log("  User USDC balance:", userBalance / 10n**6n, "USDC");
    
    // Check allowance
    const allowance = await fakeUsdc.read.allowance([deployer.account.address, lmsr.address]);
    console.log("  LMSR allowance:", allowance / 10n**6n, "USDC");
    
    // Check LMSR USDC balance
    const lmsrBalance = await fakeUsdc.read.balanceOf([lmsr.address]);
    console.log("  LMSR USDC balance:", lmsrBalance / 10n**6n, "USDC");
    
  } catch (error) {
    console.error("✗ Cross-contract interaction failed:", error.message);
  }
  
  console.log("\n=== Contract Connection Test Complete ===");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });