const contractBNU = artifacts.require('BNUToken')
const contractKYC = artifacts.require('AvatarArtArtistKYC')
const contractNFT = artifacts.require('AvatarArtNFT')

module.exports = async function (deployer) {
  await deployer.deploy(contractBNU)
  await deployer.deploy(contractKYC)
  await deployer.deploy(contractNFT)    
};