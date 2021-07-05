const AvatarArtMarketPlace = artifacts.require('AvatarArtMarketPlace')

module.exports = async function (deployer) {
  await deployer.deploy(AvatarArtMarketPlace, "0xc8CC8f17371Ea652Be178f1DeC9Cca9e57BbdCe2", "0x009f0C08C8e0B424C4e5901809702779CDc45bf8")
};