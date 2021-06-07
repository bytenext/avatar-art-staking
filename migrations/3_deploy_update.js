const { upgradeProxy } = require('@openzeppelin/truffle-upgrades');

const contractAvt = artifacts.require('AvatarArtStaking')
const contractAvtV2 = artifacts.require('AvatarArtStakingV2')

module.exports = async function (deployer) {
const existing = await contractAvt.deployed();
  await upgradeProxy(existing.address, contractAvtV2, { deployer });
};