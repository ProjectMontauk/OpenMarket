const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("LMSR Contract", function () {
  let lmsrContract;
  let conditionalTokens;
  let fakeDai;
  let owner;
  let user1;
  let user2;

  beforeEach(async function () {
    [owner, user1, user2] = await ethers.getSigners();

    // Deploy FakeDai
    const FakeDai = await ethers.getContractFactory("FakeDai");
    fakeDai = await FakeDai.deploy();

    // Deploy ConditionalTokens
    const ConditionalTokens = await ethers.getContractFactory("ConditionalTokens");
    conditionalTokens = await ConditionalTokens.deploy();

    // Deploy LMSR
    const LMSR = await ethers.getContractFactory("LsLMSR");
    lmsrContract = await LMSR.deploy(
      await conditionalTokens.getAddress(),
      await fakeDai.getAddress(),
      owner.address
    );

    // Mint some DAI to users for testing
    await fakeDai.mint(user1.address, ethers.parseEther("1000"));
    await fakeDai.mint(user2.address, ethers.parseEther("1000"));
  });

  describe("Setup", function () {
    it("Should initialize correctly", async function () {
      expect(await lmsrContract.owner()).to.equal(owner.address);
      expect(await lmsrContract.token()).to.equal(await fakeDai.getAddress());
    });

    it("Should setup market correctly", async function () {
      const questionId = ethers.keccak256(ethers.toUtf8Bytes("Will BTC reach $100k in 2024?"));
      const bInput = ethers.parseEther("10000"); // 10k DAI liquidity
      const initialSubsidy = ethers.parseEther("1000"); // 1k DAI initial subsidy
      const overround = 200; // 2% overround

      await fakeDai.mint(owner.address, initialSubsidy);
      await fakeDai.approve(await lmsrContract.getAddress(), initialSubsidy);

      await lmsrContract.setup(
        owner.address,
        questionId,
        2, // binary market
        bInput,
        initialSubsidy,
        overround
      );

      expect(await lmsrContract.numOutcomes()).to.equal(2);
    });
  });

  describe("Buy Function", function () {
    beforeEach(async function () {
      // Setup market first
      const questionId = ethers.keccak256(ethers.toUtf8Bytes("Test Question"));
      const bInput = ethers.parseEther("10000");
      const initialSubsidy = ethers.parseEther("1000");
      const overround = 200;

      await fakeDai.mint(owner.address, initialSubsidy);
      await fakeDai.approve(await lmsrContract.getAddress(), initialSubsidy);

      await lmsrContract.setup(
        owner.address,
        questionId,
        2,
        bInput,
        initialSubsidy,
        overround
      );
    });

    it("Should allow buying shares", async function () {
      const betAmount = ethers.parseEther("100"); // 100 DAI bet
      
      await fakeDai.connect(user1).approve(await lmsrContract.getAddress(), betAmount);
      
      const sharesReceived = await lmsrContract.connect(user1).buy(0, betAmount);
      
      expect(sharesReceived).to.be.gt(0);
    });
  });
}); 