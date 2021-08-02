// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IAvatarArtExchange{
    /**
     * @dev Allow or disallow `itemAddress` to be traded on AvatarArtOrderBook
    */
    function toogleTradableStatus(address itemAddress) external returns(bool);
    
    /**
     * @dev Buy `itemAddress` with `price` and `amount`
     */ 
    function buy(address itemAddress, uint256 price, uint256 amount) external returns(bool);
    
    /**
     * @dev Sell `itemAddress` with `price` and `amount`
     */ 
    function sell(address itemAddress, uint256 price, uint256 amount) external returns(bool);
    
    /**
     * @dev Cancel an open trading order for `itemAddress` by `orderId`
     */ 
    function cancel(address itemAddress, uint256 orderId, uint256 orderType) external returns(bool);
}