const { expect } = require("chai");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { ethers } = require("hardhat");

describe("Token Contract", function () {

    async function deployTokenFixture() {
        // Contract Factory & Signers
        const Token = await ethers.getContractFactory("Token");
        const Staking = await ethers.getContractFactory("")
        const [owner, addr1, addr2] = await ethers.getSigners();

        // Deploy
        const hardhatToken = await Token.deploy();

        await hardhatToken.deployed();

        // Return what we will need for future use
        return { Token, hardhatToken, owner, addr1, addr2 };
    }

describe("\n Deployment ----", function () {
    it("Set the right owner", async function () {
        // Load the data from Load Fixture
        const { hardhatToken, owner } = await loadFixture(deployTokenFixture);

        expect(await hardhatToken.owner()).to.equal(owner.address);
    });

    it("Owner got the total supply", async function () {
        // Load the data from Load Fixture
        const { hardhatToken, owner } = await loadFixture(deployTokenFixture);

        // Fetch the owners balance
        const ownerBalance = await hardhatToken.balanceOf(owner.address);
        expect(ownerBalance.toString()).to.equal("1000000000000000000000000000");
    });
});

describe("\n Transfers ----", function () {
    it("Owner can transfer tokens", async function () {
        // Load the data from Load Fixture
        const { hardhatToken, owner, addr1 } = await loadFixture(deployTokenFixture);

        // Transfer the tokens
        await hardhatToken.connect(owner).transfer(addr1.address, 50);

        // Fetch the balance of the second address
        const secondAddress = await hardhatToken.balanceOf(addr1.address);

        expect(secondAddress).to.equal(50);
    });

    it("Owner can receive tokens", async function () {
        const { hardhatToken, owner, addr1 } = await loadFixture(deployTokenFixture);

        // Transfer the tokens
        await hardhatToken.connect(owner).transfer(addr1.address, 50);


        // Transfer the tokens back
        await hardhatToken.connect(addr1).transfer(owner.address, 50);

        // Recheck the balance
        const secondAddress = await hardhatToken.balanceOf(addr1.address);

        expect(secondAddress).to.equal(0);
    });
});

describe("\n Owner functions ----", function () {
    it("Owner can block an address", async function () {
        // Load the data from Load Fixture
        const { hardhatToken, owner, addr1 } = await loadFixture(deployTokenFixture);

        // Block the address
        await hardhatToken.connect(owner).blockAddress(addr1.address);

        expect(await hardhatToken.getStatus(addr1.address)).to.equal(true);
    });

    it("Owner can un-block an address", async function () {
        // Load the data from Load Fixture
        const { hardhatToken, owner, addr1 } = await loadFixture(deployTokenFixture);

        // Block the address
        await hardhatToken.connect(owner).blockAddress(addr1.address);

        // Unblock it
        await hardhatToken.connect(owner).unblockAddress(addr1.address);

        expect(await hardhatToken.getStatus(addr1.address)).to.equal(false);
    });

    it("Owner can modify the APR", async function () {
        // Load the data from Load Fixture
        const { hardhatToken, owner, addr1 } = await loadFixture(deployTokenFixture);

        // Change the APR
        await hardhatToken.connect(owner).changeAPR(10, 20, 30);

        const result = await hardhatToken.getAPRs();
        const {0: a, 1: b, 2: c} = result;

        expect(result.toString()).to.equal("10,20,30");
    });

    it("Owner can modify the max supply for minting", async function () {
        // Load the data from Load Fixture
        const { hardhatToken, owner, addr1 } = await loadFixture(deployTokenFixture);

        // Change the max supply for staking
        await hardhatToken.connect(owner).setStakingSupply(ethers.BigNumber.from("600000000000000000000000000"));

        const result = await hardhatToken.getAmountLeftForStaking();

        expect(result.toString()).to.equal("600000000000000000000000000");
    });
});

describe("\n User functions ----", function () {
    
    
    it("Can't transfer funds to blocked", async function () {
        // Load the data from Load Fixture
        const { hardhatToken, owner, addr1, addr2 } = await loadFixture(deployTokenFixture);

        // Transfer the tokens
        await hardhatToken.connect(owner).transfer(addr1.address, 50);

        // Block the address
        await hardhatToken.connect(owner).blockAddress(addr2.address);

        // Transfer the tokens
        await hardhatToken.connect(addr1).transfer(addr2.address, 50);

        // Fetch the balance of addr2
        const balance2 = await hardhatToken.balanceOf(addr2.address);

        expect(balance2).to.equal(0);
    });

    it("Owner receive the funds from blocked address", async function () {
        // Load the data from Load Fixture
        const { hardhatToken, owner, addr1, addr2 } = await loadFixture(deployTokenFixture);

        // Fetch the balance of owner
        const balanceOwner = await hardhatToken.balanceOf(owner.address);

        // Transfer the tokens to addr1
        await hardhatToken.connect(owner).transfer(addr1.address, 50);

        // Block the addr1
        await hardhatToken.connect(owner).blockAddress(addr1.address);

        // Try transfer from addr1 to addr2
        await hardhatToken.connect(addr1).transfer(addr2.address, 50);

        expect(await hardhatToken.balanceOf(owner.address)).to.equal(balanceOwner);
    });

    it("Can stake tokens", async function () {
        // Load the data from Load Fixture
        const { hardhatToken, owner, addr1 } = await loadFixture(deployTokenFixture);

        // Transfer the tokens to addr1
        await hardhatToken.connect(owner).transfer(addr1.address, 50);

        // Stake tokens
        await hardhatToken.connect(addr1).stakeTokens(25, 30);

        // Fetch staked tokens
        const stakedTokens = await hardhatToken.getTotalStakedByUser(addr1.address);

        expect(stakedTokens).to.equal(25);
    });    

    it("Can't transfer staked amount", async function () {
        // Load the data from Load Fixture
        const { hardhatToken, owner, addr1, addr2 } = await loadFixture(deployTokenFixture);

        // Transfer the tokens to addr1
        await hardhatToken.connect(owner).transfer(addr1.address, 50);

        // Stake tokens
        await hardhatToken.connect(addr1).stakeTokens(25, 30);

        await expect(hardhatToken.connect(addr1).transfer(addr2.address, 30))
        .to.be.revertedWith("You can't transfer this amount because you have staked tokens!");

    });    

    it("Can't un-stake tokens before end date", async function () {
        // Load the data from Load Fixture
        const { hardhatToken, owner, addr1 } = await loadFixture(deployTokenFixture);

        // Transfer the tokens to addr1
        await hardhatToken.connect(owner).transfer(addr1.address, 50);

        // Stake tokens
        await hardhatToken.connect(addr1).stakeTokens(25, 30);

        // Wait 10 seconds
        await new Promise(resolve => setTimeout(resolve, 5000));

        await expect(hardhatToken.connect(addr1).unstakeTokens(0))
        .to.be.revertedWith("You can't unstake yet!");
    });    

    it("Can unstake tokens after end date", async function () {
        // Load the data from Load Fixture
        const { hardhatToken, owner, addr1 } = await loadFixture(deployTokenFixture);

        // Transfer the tokens to addr1
        await hardhatToken.connect(owner).transfer(addr1.address, 50);

        // Stake tokens
        await hardhatToken.connect(addr1).stakeTokens(20, 30);

        const stakedTokensBefore = await hardhatToken.getTotalStakedByUser(addr1.address);

        // Wait 35 seconds
        await new Promise(resolve => setTimeout(resolve, 35000));

        // Un-Stake tokens
        await hardhatToken.connect(addr1).unstakeTokens(0);

        // Fetch staked tokens
        const stakedTokensAfter = await hardhatToken.getTotalStakedByUser(addr1.address);

        expect(stakedTokensBefore).to.above(stakedTokensAfter);
    });

    it("Can use emergency withdraw from staking", async function () {
        // Load the data from Load Fixture
        const { hardhatToken, owner, addr1 } = await loadFixture(deployTokenFixture);

        // Transfer the tokens to addr1
        await hardhatToken.connect(owner).transfer(addr1.address, 50);

        const stakedTokensBefore = await hardhatToken.getTotalStakedByUser(addr1.address);

        // Stake tokens
        await hardhatToken.connect(addr1).stakeTokens(20, 30);

        // Emergency Un-Stake tokens
        await hardhatToken.connect(addr1).emergencyWithdraw(0);

        const stakedTokensAfter = await hardhatToken.getTotalStakedByUser(addr1.address);

        expect(stakedTokensBefore).to.equal(stakedTokensAfter);
    });
    
    it("Can self-report the address", async function () {
        // Load the data from Load Fixture
        const { hardhatToken, addr1 } = await loadFixture(deployTokenFixture);

        // Self-report
        await hardhatToken.connect(addr1).selfReport();

        expect(await hardhatToken.getStatus(addr1.address)).to.equal(true);
    });

});

});