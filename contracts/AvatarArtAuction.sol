// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IAvatarArtAuction.sol";
import "./AvatarArtBase.sol";

contract AvatarArtAuction is AvatarArtBase, IAvatarArtAuction{
    //Store information of specific auction
    struct Auction{
        uint256 startTime;
        uint256 endTime;
        uint256 tokenId;
        address tokenOwner;
        uint256 price;
        address winner;
        bool active;
    }
    
    //Store auction history when a user places
    struct AuctionHistory{
        uint256 time;
        uint256 price;
        address creator;
    }
    
    //AUCTION 
    Auction[] internal _auctions;       //List of auction
    
    //Mapping between specific auction and its histories
    mapping(uint256 => AuctionHistory[]) internal _auctionHistories;
    
    constructor(address bnuTokenAddress, address avatarArtNFTAddress) 
        AvatarArtBase(bnuTokenAddress, avatarArtNFTAddress){}
        
     /**
     * @dev {See - IAvatarArtAuction.createAuction}
     * 
     * IMPLEMENTATION
     *  1. Validate requirement
     *  2. Add new auction
     *  3. Transfer NFT to contract
     */ 
    function createAuction(uint256 tokenId, uint256 startTime, uint256 endTime, uint256 price, address tokenOwner) external override onlyOwner returns(uint256){
        require(_now() <= startTime, "Start time is invalid");
        require(startTime < endTime, "Time is invalid");
        (bool isExisted,) = getActiveAuctionByTokenId(tokenId);
        require(!isExisted, "Token is in other auction");
        
        IERC721 avatarArtNFT = getAvatarArtNFT();
        require(avatarArtNFT.ownerOf(tokenId) == tokenOwner, "Not token owner");
        
        avatarArtNFT.safeTransferFrom(tokenOwner, address(this), tokenId);
        
        _auctions.push(Auction(startTime, endTime, tokenId, tokenOwner, price, address(0), true));
        
        emit NewAuctionCreated(tokenId, startTime, endTime, price);
        
        return _auctions.length - 1;
    }
    
    /**
     * @dev {See - IAvatarArtAuction.deactivateAuction}
     * 
     */ 
    function deactivateAuction(uint256 auctionIndex) external override onlyOwner returns(bool){
        require(auctionIndex < getAuctionCount());
        _auctions[auctionIndex].active = false;
        return true;
    }
    
    /**
     * @dev {See - IAvatarArtAuction.distribute}
     * 
     *  IMPLEMENTATION
     *  1. Validate requirements
     *  2. Distribute NFT for winner
     *  3. Keep fee for dev and pay cost for token owner
     *  4. Update auction
     */ 
    function distribute(uint256 auctionIndex) external override returns(bool){       //Anyone can call this function
        require(auctionIndex < getAuctionCount());
        Auction storage auction = _auctions[auctionIndex];
        require(auction.active && auction.endTime < _now());
        
        //If have auction
        if(auction.winner != address(0)){
            IERC20 bnuToken = getBnuToken();
            
            //Pay fee for owner
            uint256 feeAmount = 0;
            uint256 feePercent = getFeePercent();
            if(feePercent > 0){
                feeAmount = auction.price * feePercent / 100 / MULTIPLIER;
                require(bnuToken.transfer(_owner, feeAmount));
            }
            
            //Pay cost for owner
            require(bnuToken.transfer(auction.tokenOwner, auction.price - feeAmount));
            
            //Transfer AvatarArtNFT from contract to winner
            getAvatarArtNFT().safeTransferFrom(address(this), auction.winner, auction.tokenId);
        }else{//No auction
            //Transfer AvatarArtNFT from contract to owner
            getAvatarArtNFT().safeTransferFrom(address(this), auction.tokenOwner, auction.tokenId);
        }
        
        auction.active = false;
        
        return true;
    }
    
    /**
     * @dev Get active auction by `tokenId`
     */ 
    function getActiveAuctionByTokenId(uint256 tokenId) public view returns(bool, Auction memory){
        for(uint256 index = _auctions.length; index > 0; index--){
            Auction memory auction = _auctions[index - 1];
            if(auction.tokenId == tokenId && auction.active && auction.startTime <= _now() && auction.endTime >= _now())
                return (true, auction);
        }
        
        return (false, Auction(0,0,0, address(0), 0, address(0), false));
    }
    
    /**
     * @dev Get auction count 
     */
    function getAuctionCount() public view returns(uint256){
        return _auctions.length;
    }
    
     /**
     * @dev Get auction infor by `auctionIndex` 
     */
    function getAuction(uint256 auctionIndex) external view returns(Auction memory){
        require(auctionIndex < getAuctionCount());
        return _auctions[auctionIndex];
    }
    
    /**
     * @dev {See - IAvatarArtAuction.place}
     * 
     *  IMPLEMENTATION
     *  1. Validate requirements
     *  2. Add auction histories
     *  3. Update auction
     */ 
    function place(uint256 auctionIndex, uint256 price) external override returns(bool){
        require(auctionIndex < getAuctionCount());
        Auction storage auction = _auctions[auctionIndex];
        require(auction.active && auction.startTime <= _now() && auction.endTime >= _now(), "Invalid auction");
        require(price > auction.price, "Invalid price");
        
        IERC20 bnuToken = getBnuToken();
        //Transfer BNU to contract
        require(bnuToken.transferFrom(_msgSender(), address(this), price),"BNU transferring failed");
        
        //Add auction history
        _auctionHistories[auctionIndex].push(AuctionHistory(_now(), price, _msgSender()));
        
        //If last user exised, pay back BNU token
        if(auction.winner != address(0)){
            require(bnuToken.transfer(auction.winner, auction.price), "Can not payback for last winner");
        }
        
        //Update auction
        auction.winner = _msgSender();
        auction.price = price;
        
        emit NewPlaceSetted(auctionIndex, _msgSender(), price);
        
        return true;
    }
    
     /**
     * @dev {See - IAvatarArtAuction.updateActionPrice}
     * 
     */ 
    function updateActionPrice(uint256 auctionIndex, uint256 price) external override onlyOwner returns(bool){
        require(auctionIndex < getAuctionCount());
        Auction storage auction = _auctions[auctionIndex];
        require(auction.startTime > _now());
        auction.price = price;
        
        emit AuctionPriceUpdated(auctionIndex, price);
        return true;
    }
    
    /**
     * @dev {See - IAvatarArtAuction.updateActionTime}
     * 
     */ 
    function updateActionTime(uint256 auctionIndex, uint256 startTime, uint256 endTime) external override onlyOwner returns(bool){
        require(auctionIndex < getAuctionCount());
        Auction storage auction = _auctions[auctionIndex];
        require(auction.startTime > _now());
        auction.startTime = startTime;
        auction.endTime = endTime;
        
        emit AuctionTimeUpdated(auctionIndex, startTime, endTime);
        return true;
    }
    
    event NewAuctionCreated(uint256 tokenId, uint256 startTime, uint256 endTime, uint256 price);
    event AuctionPriceUpdated(uint256 auctionIndex, uint256 price);
    event AuctionTimeUpdated(uint256 auctionIndex, uint256 startTime, uint256 endTime);
    event NewPlaceSetted(uint256 auctionIndex, address account, uint256 price);
}