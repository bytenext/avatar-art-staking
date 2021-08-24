// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./AvatarArtERC20.sol";
import "../AvatarArtBase.sol";
import ".././core/Ownable.sol";

contract AvatarArtTokenDeployer is AvatarArtBase{
    struct TokenInfo{
        string name;
        string symbol;
        uint256 totalSupply;
        address tokenOwner;
        bool isApproved;
    }

    IERC721 public _avatarArtNft;

    mapping(uint256 => TokenInfo) public _tokenInfos;

    constructor(address avatarNftAddress){
        _avatarArtNft = IERC721(avatarNftAddress);
    }

    function setAvatarArtNft(address avatarNftAddress) external onlyOwner {
        _avatarArtNft = IERC721(avatarNftAddress);
    }

    function approve(
        uint256 tokenId,
        string memory name,
        string memory symbol,
        uint256 totalSupply,
        address tokenOwner) external onlyOwner{
        require(tokenOwner != address(0), "Token owner is address zero");

        _tokenInfos[tokenId] = TokenInfo({
            name: name,
            symbol: symbol,
            totalSupply: totalSupply,
            tokenOwner: tokenOwner,
            isApproved: true
        });
    }

    function deployContract(uint256 tokenId) public returns(address){
        TokenInfo storage tokenInfo = _tokenInfos[tokenId];
        require(tokenInfo.isApproved, "NFT has not been approved");

        _avatarArtNft.safeTransferFrom(tokenInfo.tokenOwner, address(this), tokenId);

        AvatarArtERC20 deployedContract = new AvatarArtERC20(tokenInfo.name, tokenInfo.symbol, tokenInfo.totalSupply, tokenInfo.tokenOwner, _owner);
        address newTokenAddress = address(deployedContract);
        
        emit NftTokenDeployed(newTokenAddress, _msgSender());
        return newTokenAddress;
    }

    function withdrawNft(uint256 tokenId, address receipent) external onlyOwner{
        _avatarArtNft.safeTransferFrom(address(this), receipent, tokenId);
    }
    
    event NftTokenDeployed(address contractAddress, address owner);
}