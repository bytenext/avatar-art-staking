// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./AvatarArtERC20.sol";
import "../AvatarArtBase.sol";
import ".././core/Ownable.sol";
import ".././interfaces/IAvatarArtExchange.sol";

contract AvatarArtTokenDeployer is AvatarArtBase{
    struct TokenInfo{
        string name;
        string symbol;
        uint256 totalSupply;
        address tokenOwner;
        address tokenAddress;
        address pairToAddress;
        bool isApproved;
    }

    IERC721 public _avatarArtNft;
    IAvatarArtExchange public _avatarArtExchange;

    mapping(uint256 => TokenInfo) public _tokenInfos;

    constructor(address avatarNftAddress, address exchangeAddress){
        _avatarArtNft = IERC721(avatarNftAddress);
        _avatarArtExchange = IAvatarArtExchange(exchangeAddress);
    }

    function setAvatarArtNft(address avatarNftAddress) external onlyOwner {
        _avatarArtNft = IERC721(avatarNftAddress);
    }

    function approve(
        uint256 tokenId,
        string memory name,
        string memory symbol,
        uint256 totalSupply,
        address tokenOwner,
        address pairToAddress) external onlyOwner{
        require(tokenOwner != address(0), "Token owner is address zero");

        _tokenInfos[tokenId] = TokenInfo({
            name: name,
            symbol: symbol,
            totalSupply: totalSupply,
            tokenOwner: tokenOwner,
            tokenAddress: address(0),
            pairToAddress: pairToAddress,
            isApproved: true
        });
    }

    function deployContract(uint256 tokenId) public returns(address){
        TokenInfo storage tokenInfo = _tokenInfos[tokenId];
        require(tokenInfo.isApproved, "NFT has not been approved");

        _avatarArtNft.safeTransferFrom(tokenInfo.tokenOwner, address(this), tokenId);

        AvatarArtERC20 deployedContract = new AvatarArtERC20(tokenInfo.name, tokenInfo.symbol, tokenInfo.totalSupply, tokenInfo.tokenOwner, _owner);
        tokenInfo.tokenAddress = address(deployedContract);

        //Allow to trade this pair
        require(_avatarArtExchange.toogleTradableStatus(tokenInfo.tokenAddress, tokenInfo.pairToAddress));
        
        emit NftTokenDeployed(tokenInfo.tokenAddress, _msgSender());
        return tokenInfo.tokenAddress;
    }

    function burnToken(uint256 tokenId) external{
        TokenInfo storage tokenInfo = _tokenInfos[tokenId];
        require(tokenInfo.tokenAddress != address(0));

        IERC20 token = IERC20(tokenInfo.tokenAddress);
        require(token.balanceOf(_msgSender()) == token.totalSupply());

        token.transferFrom(_msgSender(), address(0), token.totalSupply());
        _avatarArtNft.safeTransferFrom(address(this), _msgSender(), tokenId);

        tokenInfo.name = "";
        tokenInfo.symbol = "";
        tokenInfo.totalSupply = 0;
        tokenInfo.tokenAddress = address(0);
        tokenInfo.tokenOwner = address(0);
        tokenInfo.isApproved = false;

        emit NftTokenBurned(_msgSender(), tokenId);
    }

    function withdrawNft(uint256 tokenId, address receipent) external onlyOwner{
        _avatarArtNft.safeTransferFrom(address(this), receipent, tokenId);
    }
    
    event NftTokenDeployed(address contractAddress, address owner);
    event NftTokenBurned(address owner, uint256 tokenId);
}