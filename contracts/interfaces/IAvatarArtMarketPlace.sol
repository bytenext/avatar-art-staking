// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IAvatarArtMarketPlace{
    /**
     * @dev User that created sell order can cancel that order
     */ 
    function cancelSellOrder(uint256 tokenId) external returns(bool);
    
    /**
     * @dev Create a sell order to sell BNU category
     */
    function createSellOrder(uint tokenId, uint price) external returns(bool);
    
    /**
     * @dev Set BNU contract address 
     */
    function getBnuContractAddress() external view returns(address);
    
     /**
     * @dev Set BNU token address 
     */
    function getBnuTokenAddress() external returns(address);
    
    /**
     * @dev Get purchase fee percent, this fee is for seller
     */ 
    function getFeePercent() external returns(uint);
    
    /**
     * @dev User purchases a BNU category
     */ 
    function purchase(uint tokenId) external returns(uint);
    
     /**
     * @dev Get BNU token address 
     */
    function setBnuTokenAddress(address newAddress) external;
    
    /**
     * @dev Get BNU token address 
     */
    function setBnuContractAddress(address newAddress) external;
    
    /**
     * @dev Set fee percent
     */ 
    function setFeePercent(uint feePercent) external;
}