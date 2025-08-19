// scripts/mint-usdc.js
import { network } from "hardhat";
// import { getContractAt } from "hardhat";

async function main() {
  const { viem } = await network.connect();
  const [deployer] = await viem.getWalletClients();
  
  // Connect to existing contract
  const fakeUsdc = await viem.getContractAt("FakeUsdc", "0x5fbdb2315678afecb367f032d93f642f64180aa3");
  
  // Mint more tokens
  const mintAmount = 1000000n * 10n**6n;
  await fakeUsdc.write.mint([deployer.account.address, mintAmount]);
  
  console.log("FakeUSDC Address:", fakeUsdc.address);
  console.log("Deployer address:", deployer.account.address);
  console.log("Does name work", fakeUsdc.name);
  const balance = await fakeUsdc.read.balanceOf([deployer.account.address]);
  console.log("New balance:", balance / 10n**6n, "USDC");
}

main()
