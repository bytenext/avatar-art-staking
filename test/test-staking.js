const contractBNU = artifacts.require('BNUToken')
const contractAvt = artifacts.require('AvatarArtStaking')
const { time } = require("@openzeppelin/test-helpers");

let token,stakeContract;
contract('contract stake', (accounts) => {
  const owner = accounts[0];
  const balOwner = 10000;
  const bob = accounts[1];
  const balBob = 10000;

  const APR_MULTIPLIER = 1000;
  const STAGE_1 = {
    min: 1000,
    duration: 5*24*60*60, // 5 days
    profit: 150*APR_MULTIPLIER,
  }
  const STAGE_2 = {
    min: 5000,
    duration: 2*24*60*60, // 2 days
    profit: 200*APR_MULTIPLIER,
  }
  const DAY_ONE_YEAR = 365;
  const HOUR_ONE_DAY = 24;

  const STAGE1 = 0;
  const STAGE2 = 1;

  beforeEach(async () => {
    token = await contractBNU.new({ from: owner });
    stakeContract = await contractAvt.new(token.address, { from: owner });
    // set balance for owner
    await token.mint(owner, balOwner, { from: owner });
    await token.mint(bob, balBob, { from: owner });
    await token.approve(stakeContract.address, 50000000000000, { from: bob });
    await token.approve(stakeContract.address, 50000000000000, { from: owner });
    await token.mint(stakeContract.address, 5000, { from: owner });
    // create stage 1
    await stakeContract.createNftStage(STAGE_1.duration, STAGE_1.min, STAGE_1.profit)
    // create stage 2
    await stakeContract.createNftStage(STAGE_2.duration, STAGE_2.min, STAGE_2.profit)
  })

  it('check balance init earch user and stage', async () => {
    const resBalOwner = await token.balanceOf(owner);
    assert.strictEqual(resBalOwner.toNumber(), balOwner);
    const resBal = await token.balanceOf(bob);
    assert.strictEqual(resBal.toNumber(), balBob);

    const listStage = await stakeContract.getNftStages();
    assert.strictEqual(listStage.length, 2);
    assert.equal(listStage[0].minAmount, STAGE_1.min);
  });

  it('user 1 staking 2 stage, check total stake, interest of user', async () => {
    //stake for stage 1, min 1000 BNU
    let amountStake1 = 500;
    let resultStake;
    try {
      await stakeContract.stake(0, amountStake1, { from: bob });
      resultStake = true;
    } catch (error) {
      resultStake = false;
    }
    //stake value not enough
    assert.strictEqual(resultStake, false);
    const res = await stakeContract.getUserStakedAmount(STAGE1, bob);
    assert.strictEqual(res.toString(), '0');
    // stake 1000 to stake 1
    amountStake1 = 1000;
    await stakeContract.stake(STAGE1, amountStake1, { from: bob });
    const resStake1 = await stakeContract.getUserStakedAmount(STAGE1, bob);
    assert.strictEqual(resStake1.toNumber(), amountStake1);
    
    //stake 7000 BNU to stake 2 for 2 turn 5000 and 2000
    const amountStake21 = 5000;
    const amountStake22 = 2000;
    await stakeContract.stake(STAGE2, amountStake21, { from: bob });
    await stakeContract.stake(STAGE2, amountStake22, { from: bob });
    const resStake2 = await stakeContract.getUserStakedAmount(STAGE2, bob);
    assert.strictEqual(resStake2.toNumber(), amountStake21+amountStake22);

    //owner stake 2000 BNU to stage 1
    const ownerStake = 1000;
    await stakeContract.stake(STAGE1, ownerStake, { from: owner });
    const resStakeOw = await stakeContract.getUserStakedAmount(STAGE1, owner);
    assert.strictEqual(resStakeOw.toNumber(), ownerStake);

    // checking for interest
    const timeInterest = 24; // 24 hours
    await time.increase(time.duration.hours(timeInterest))
    const timePendding = await stakeContract.getUserRewardPendingTime(STAGE2, bob);
    assert.strictEqual(parseInt(timePendding.toNumber()/60/60), parseInt(timeInterest));
    const interestStage1 = (amountStake1*STAGE_1.profit/APR_MULTIPLIER/100)/DAY_ONE_YEAR/HOUR_ONE_DAY*timeInterest;
    const interestStage2 = ((amountStake21+amountStake22)*STAGE_2.profit/APR_MULTIPLIER/100)/DAY_ONE_YEAR/HOUR_ONE_DAY*timeInterest;
    const interest = await stakeContract.getUserEarnedAmount(bob);
    assert.strictEqual(parseInt(interest.toNumber()), parseInt(interestStage1+interestStage2));

    // check total stake
    const totalStaked = await stakeContract.getTotalStaked();
    assert.strictEqual(totalStaked.toNumber(), amountStake1 + amountStake21 + amountStake22 + ownerStake);

    //=== withdraw
    // withdraw interest
    const balBefore = await token.balanceOf(bob);
    await stakeContract.withdraw(STAGE1, 1000, {from: bob});
    const balAfter = await token.balanceOf(bob);
    // only ern interest, can't withdraw stake because lock time.
    assert.strictEqual(balBefore.toNumber()+ interest.toNumber(), balAfter.toNumber());
    // reset interest
    const interestAfterWd = await stakeContract.getUserEarnedAmount(bob);
    assert.strictEqual(0, interestAfterWd.toNumber());

    // withdraw 3000 bnu
    const pushTime = 24; // push 24h, can be withdraw stage 2
    await time.increase(time.duration.hours(pushTime))
    const amountWithdraw = 3000;
    await stakeContract.withdraw(STAGE2, amountWithdraw, {from: bob});
    const amountStakeRes = await stakeContract.getUserStakedAmount(STAGE2, bob);
    assert.strictEqual(amountStakeRes.toNumber(), (amountStake21+amountStake22)-amountWithdraw);
    const resReset = await stakeContract.getUserEarnedAmount(bob);
    assert.strictEqual(0, resReset.toNumber());
  });
})