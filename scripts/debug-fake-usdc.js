import { network } from "hardhat";

async function main() {
  console.log("Simple contract connection test...");
  
  const { viem } = await network.connect();
  
  const address = "0x5FbDB2315678afecb367f032d93F642f64180aa3";
  console.log("Trying to connect to:", address);
  
  try {
    // Try to get the contract
    console.log("Calling viem.getContractAt...");
    // const fakeUsdc = await viem.getContractAt("FakeUsdc", address);
    const fakeUsdc = await viem.deployContract("FakeUsdc");
    console.log("✅ getContractAt succeeded");
    console.log("Contract object:", fakeUsdc);
  } catch (error) {
    console.log("❌ Error occurred:");
    console.log("Error type:", error.constructor.name);
    console.log("Error message:", error.message);
    console.log("Full error:", error);
  }
}

main().catch(console.error);
