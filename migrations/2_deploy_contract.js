const { deployProxy } = require('@openzeppelin/truffle-upgrades');

const contractBNU = artifacts.require('BNUToken')
const contractAvt = artifacts.require('AvatarArtStaking')

module.exports = async function (deployer) {
  await deployer.deploy(contractBNU)
  await deployProxy(contractAvt, [contractBNU.address], { deployer, initializer: 'initialize' });
};