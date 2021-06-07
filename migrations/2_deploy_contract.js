const contractBNU = artifacts.require('BNUToken')
const contractAvt = artifacts.require('AvatarArtStaking')

module.exports = function (deployer) {
  deployer.deploy(contractBNU)
    .then(() => {
      return deployer.deploy(contractAvt, contractBNU.address)
    })
};