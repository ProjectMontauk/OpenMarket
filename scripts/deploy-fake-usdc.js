import { network } from "hardhat";

async function main() {
  console.log("Deploying FakeUSDC...");
  
  const { viem } = await network.connect();
  const fakeUsdc = await viem.deployContract("FakeUsdc");
  
  console.log("FakeUSDC deployed to:", fakeUsdc.address);
  
  // Mint some tokens to the deployer for testing
  const [deployer] = await viem.getWalletClients();
  const mintAmount = 2000000n * 10n**6n; // 1M USDC (6 decimals)
  
  await fakeUsdc.write.mint([deployer.account.address, mintAmount]);
  console.log("Minted 1000000 USDC to deployer");
  
  const balance = await fakeUsdc.read.balanceOf([deployer.account.address]);
  const name = await fakeUsdc.read.name();
  console.log("Deployer balance:", balance / 10n**6n, "USDC");
  console.log("Name:", name);
  console.log("Deployer address:", deployer.account.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });