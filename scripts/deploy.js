import { ethers } from "hardhat";

async function main() {
  console.log("Deploying FakeUSDC...");
  
  const FakeUsdc = await ethers.getContractFactory("FakeUsdc");
  const fakeUsdc = await FakeUsdc.deploy();
  await fakeUsdc.waitForDeployment();
  
  const address = await fakeUsdc.getAddress();
  console.log("FakeUSDC deployed to:", address);
  
  // Mint some tokens to the deployer for testing
  const deployer = (await ethers.getSigners())[0];
  const mintAmount = ethers.parseUnits("1000000", 6); // 1M USDC (6 decimals)
  await fakeUsdc.mint(deployer.address, mintAmount);
  
  console.log("Minted", ethers.formatUnits(mintAmount, 6), "USDC to deployer");
  
  return fakeUsdc;
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 