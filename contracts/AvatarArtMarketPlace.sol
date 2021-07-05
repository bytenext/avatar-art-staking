// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IERC20.sol";
import "./interfaces/IAvatarArtMarketPlace.sol";

contract AvatarArtMarketPlace is Ownable, IAvatarArtMarketPlace, IERC721Receiver{
    struct MarketHistory{
        address buyer;
        address seller;
        uint256 price;
        uint256 time;
    }
    
    uint256 public MULTIPLIER = 1000;
    
    address private _bnuTokenAddress;
    address private _avatarArtNFTAddress;
    
    uint256 private _feePercent;       //Multipled by 1000
    
    uint256[] internal _tokens;
    
    //Mapping between tokenId and token price
    mapping(uint256 => uint256) internal _tokenPrices;
    
    //Mapping between tokenId and owner of tokenId
    mapping(uint256 => address) internal _tokenOwners;
    
    mapping(uint256 => MarketHistory[]) internal _marketHistories;
    
    constructor(address bnuTokenAddress, address bnuNftAddress){
        _bnuTokenAddress = bnuTokenAddress;
        _avatarArtNFTAddress = bnuNftAddress;
        _feePercent = 100;        //0.1%
    }
    
    /**
     * @dev Create a sell order to sell BNU category
     */
    function createSellOrder(uint256 tokenId, uint256 price) external override returns(bool){
        //Validate
        require(_tokenOwners[tokenId] == address(0), "Can not create sell order for this token");
        IERC721 bnuContract = IERC721(_avatarArtNFTAddress);
        require(bnuContract.ownerOf(tokenId) == _msgSender(), "You have no permission to create sell order for this token");
        
        //Transfer Bnu NFT to contract
        bnuContract.safeTransferFrom(_msgSender(), address(this), tokenId);
        
        _tokenOwners[tokenId] = _msgSender();
        _tokenPrices[tokenId] = price;
        _tokens.push(tokenId);
        
        emit NewSellOrderCreated(_msgSender(), tokenId, price);
        
        return true;
    }
    
    /**
     * @dev User that created sell order can cancel that order
     */ 
    function cancelSellOrder(uint256 tokenId) external override returns(bool){
        require(_tokenOwners[tokenId] == _msgSender(), "Forbidden to cancel sell order");

        IERC721 bnuContract = IERC721(_avatarArtNFTAddress);
        //Transfer Bnu NFT from contract to sender
        bnuContract.safeTransferFrom(address(this), _msgSender(), tokenId);
        
        _tokenOwners[tokenId] = address(0);
        _tokenPrices[tokenId] = 0;
        _tokens = _removeFromTokens(tokenId);
        
        return true;
    }
    
    /**
     * @dev Set BNU token address 
     */
    function getBnuTokenAddress() external view override returns(address){
        return _bnuTokenAddress;
    }
    
    /**
     * @dev Set BNU token address 
     */
    function getBnuContractAddress() external view override returns(address){
        return _avatarArtNFTAddress;
    }
    
    /**
     * @dev Get all active tokens that can be purchased 
     */ 
    function getTokens() external view returns(uint256[] memory){
        return _tokens;
    }
    
    /**
     * @dev Get token info about price and owner
     */ 
    function getTokenInfo(uint tokenId) external view returns(address, uint){
        return (_tokenOwners[tokenId], _tokenPrices[tokenId]);
    }
    
    /**
     * @dev Get purchase fee percent, this fee is for seller
     */ 
    function getFeePercent() external view override returns(uint){
        return _feePercent;
    }
    
    function getMarketHistories(uint256 tokenId) external view returns(MarketHistory[] memory){
        return _marketHistories[tokenId];
    }
    
    /**
     * @dev Get token price
     */ 
    function getTokenPrice(uint256 tokenId) external view returns(uint){
        return _tokenPrices[tokenId];
    }
    
    /**
     * @dev Get token's owner
     */ 
    function getTokenOwner(uint256 tokenId) external view returns(address){
        return _tokenOwners[tokenId];
    }
    
    /**
     * @dev User purchases a BNU category
     */ 
    function purchase(uint tokenId) external override returns(uint){
        address tokenOwner = _tokenOwners[tokenId];
        require(tokenOwner != address(0),"Token has not been added");
        
        uint256 tokenPrice = _tokenPrices[tokenId];
        
        if(tokenPrice > 0){
            IERC20 bnuTokenContract = IERC20(_bnuTokenAddress);    
            require(bnuTokenContract.transferFrom(_msgSender(), address(this), tokenPrice));
            uint256 feeAmount = 0;
            if(_feePercent > 0){
                feeAmount = tokenPrice * _feePercent / 100 / MULTIPLIER;
                require(bnuTokenContract.transfer(owner(), feeAmount));
            }
            require(bnuTokenContract.transfer(tokenOwner, tokenPrice - feeAmount));
        }
        
        //Transfer Bnu NFT from contract to sender
        IERC721(_avatarArtNFTAddress).transferFrom(address(this),_msgSender(), tokenId);
        
        _marketHistories[tokenId].push(MarketHistory({
            buyer: _msgSender(),
            seller: _tokenOwners[tokenId],
            price: tokenPrice,
            time: block.timestamp
        }));
        
        _tokenOwners[tokenId] = address(0);
        _tokenPrices[tokenId] = 0;
        _tokens = _removeFromTokens(tokenId);
        
        emit Purchased(_msgSender(), tokenId, tokenPrice);
        
        return tokenPrice;
    }
    
    /**
     * @dev Set BNU contract address 
     */
    function setBnuContractAddress(address newAddress) external override onlyOwner{
        require(newAddress != address(0), "Zero address");
        _avatarArtNFTAddress = newAddress;
    }
    
    /**
     * @dev Set BNU token address 
     */
    function setBnuTokenAddress(address newAddress) external override onlyOwner{
        require(newAddress != address(0), "Zero address");
        _bnuTokenAddress = newAddress;
    }
    
    /**
     * @dev Get BNU token address 
     */
    function setFeePercent(uint feePercent) external override onlyOwner{
        _feePercent = feePercent;
    }
    
    /**
     * @dev Remove token item by value from _tokens and returns new list _tokens
     */ 
    function _removeFromTokens(uint tokenId) internal view returns(uint256[] memory){
        uint256 tokenCount = _tokens.length;
        uint256[] memory result = new uint256[](tokenCount-1);
        uint256 resultIndex = 0;
        for(uint tokenIndex = 0; tokenIndex < tokenCount; tokenIndex++){
            uint tokenItemId = _tokens[tokenIndex];
            if(tokenItemId != tokenId){
                result[resultIndex] = tokenItemId;
                resultIndex++;
            }
        }
        
        return result;
    }
    
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external view override returns (bytes4){
        return bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
    }
    
    event NewSellOrderCreated(address indexed seller, uint256 tokenId, uint256 price);
    event Purchased(address indexed buyer, uint256 tokenId, uint256 price);
}