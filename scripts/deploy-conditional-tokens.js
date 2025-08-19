import { network } from "hardhat";

async function main() {
  console.log("Deploying ConditionalTokens...");
  
  const { viem } = await network.connect();
  
  // Deploy the ConditionalTokens contract
  const conditionalTokens = await viem.deployContract("ConditionalTokens");
  
  console.log("ConditionalTokens deployed to:", conditionalTokens.address);
  console.log("ConditionalTokens deployment successful!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });