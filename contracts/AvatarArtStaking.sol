// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./interfaces/IAvatarArtStaking.sol";
import "./interfaces/IERC20.sol";
import "./core/Runnable.sol";

contract AvatarArtStaking is IAvatarArtStaking, Runnable{
    struct NftStage{
        uint duration;
        uint minAmount;
        uint annualProfit;
        bool isActive;
    }
    
    struct TransactionHistory{
        uint time;
        uint amount;
    }
    
    address internal _bnuTokenAddress;
    uint internal _stopTime;
    
    //Store all BNU token amount that is staked in contract
    uint internal _totalStakedAmount;
    uint public constant APR_MULTIPLIER = 1000;
    uint public constant ONE_YEAR = 365 days;
    uint public constant ONE_DAY = 1 days;
    
    //Store all BNU token amount that is staked by user
    //Mapping NftStage index => user account => token amount
    mapping(uint => mapping(address => uint)) internal _userStakeds;
    
    //Store all earned BNU token amount that will be reward for user when he stakes
    //Mapping user account => token amount
    mapping(address => uint) internal _userEarneds;
    
    //Store the last time user received reward
    //Mapping stage index => user account => time
    mapping(uint => mapping(address => uint)) internal _userLastEarnedTimes;
    
    //Store the last time user staked
    //Mapping stage index => user account => time
    mapping(uint => mapping(address => uint)) internal _userLastStakingTimes;
    
    //Store user's staking histories
    //Mapping nft stage index =>  user account => Staking history
    mapping(uint => mapping(address => TransactionHistory[])) internal _stakingHistories;
    
    //Store user's withdrawal histories
    //Mapping nft stage index => user account => withdrawal history
    mapping(uint => mapping(address => TransactionHistory[])) internal _withdrawHistories;
    
    //List of staking users from staking NftStage
    //Mapping: _nftStages index => user address
    mapping(uint => address[]) internal _stakingUsers;
    
    //NFT
    //Store to check whether NFT is running or not
    NftStage[] internal _nftStages;
    
    constructor(address bnuTokenAddress){
        _bnuTokenAddress = bnuTokenAddress;
    }
    
    /**
     * @dev Create new NFT stage
    */ 
    function createNftStage(uint duration, uint minAmount, uint annualProfit) external onlyOwner{
        require(duration > 0, "Duration is zero");
        _nftStages.push(NftStage(duration, minAmount, annualProfit, true));
    }
    
    /**
     * @dev Get annual profit of `nftStage` by index
    */
    function getAnnualProfit(uint nftStageIndex) external override view returns(uint){
        require(nftStageIndex < _nftStages.length, "Out of length");
        return _nftStages[nftStageIndex].annualProfit;
    }
    
    /**
     * @dev Get BNU token address
    */
    function getBnuTokenAddress() external view returns(address){
        return _bnuTokenAddress;
    }
    
    function getNftStages() external view returns(NftStage[] memory){
        return _nftStages;
    }
    
    function getStopTime() external view returns(uint){
        return _stopTime;
    }
    
    /**
     * @dev Get total BNU token amount staked in contract
     */ 
    function getTotalStaked() external override view returns(uint){
        return _totalStakedAmount;
    }
    
    /**
     * @dev Get user's BNU earned
     * It includes stored interest and pending interest
     */ 
    function getUserEarnedAmount(address account) external override view returns(uint){
        uint earnedAmount = _userEarneds[account];
        
        //Calculate pending amount
        for(uint nftStageIndex = 0; nftStageIndex < _nftStages.length; nftStageIndex ++){
            NftStage memory nftStage = _nftStages[nftStageIndex];
            if(nftStage.isActive){
                uint userStakedAmount = _userStakeds[nftStageIndex][account];
                if(userStakedAmount > 0){
                    earnedAmount += _calculatePendingEarned(nftStageIndex, userStakedAmount, _getUserRewardPendingTime(nftStageIndex, account));
                }
            }
        }
        
        return earnedAmount;
    }
    
    /**
     * @dev Get list of users who are staking
     */ 
    function getStakingUsers(uint nftStageIndex) external override view returns(address[] memory){
        return _stakingUsers[nftStageIndex];
    }
    
    /**
     * @dev Get staking histories of `account`
     */ 
    function getStakingHistories(uint nftStageIndex, address account) external view returns(TransactionHistory[] memory){
        return _stakingHistories[nftStageIndex][account];
    }
    
    function getUserLastEarnedTime(uint nftStageIndex, address account) external view returns(uint){
        return _getUserLastEarnedTime(nftStageIndex, account);
    }
    
    function getUserRewardPendingTime(uint nftStageIndex, address account) external view returns(uint){
        return _getUserRewardPendingTime(nftStageIndex, account);
    }
    
    /**
     * @dev Get total BNU token amount staked by `account`
     */ 
    function getUserStakedAmount(uint nftStageIndex, address account) external override view returns(uint){
        return _userStakeds[nftStageIndex][account];
    }
    
    /**
     * @dev Get withdrawal histories of `account`
     */ 
    function getWithdrawalHistories(uint nftStageIndex, address account) external view returns(TransactionHistory[] memory){
        return _withdrawHistories[nftStageIndex][account];
    }
    
    /**
     * @dev Remove NFT stage from data
     */ 
    function setNftStage(uint index, uint duration, uint minAmount) external onlyOwner returns(bool){
        uint nftStageLength = _nftStages.length;
        require(index < nftStageLength, "Index is invalid");
        
        _nftStages[index].duration = duration;
        _nftStages[index].minAmount = minAmount;
        
        return true;
    }
    
    /**
     * @dev Remove NFT stage from data
     */ 
    function setNftStageActiveStatus(uint nftStageIndex, bool isActive) external onlyOwner returns(bool){
        require(nftStageIndex < _nftStages.length, "Index is invalid");
        require(_nftStages[nftStageIndex].isActive != isActive, "Status is the same");
        
        if(!isActive){
            for(uint userIndex = 0; userIndex < _stakingUsers[nftStageIndex].length; userIndex++){
                _calculateInterest(_stakingUsers[nftStageIndex][userIndex]);
            }
        }else{
            for(uint userIndex = 0; userIndex < _stakingUsers[nftStageIndex].length; userIndex++){
                _userLastEarnedTimes[nftStageIndex][_stakingUsers[nftStageIndex][userIndex]] = _now();
            }
        }
        
        _nftStages[nftStageIndex].isActive = isActive;
        
        return true;
    }
    
    /**
     * @dev Set BNU token address
    */
    function setBnuTokenAddress(address tokenAddress) external onlyOwner{
        require(tokenAddress != address(0), "Zero address");
        _bnuTokenAddress = tokenAddress;
    }
    
    /**
     * @dev Set APR
     * Before set APR with new value, contract should process to calculate all current users' profit 
     * to reset interest
    */
    function setAnnualProfit(uint nftStageIndex, uint annualProfit) external onlyOwner{
        require(nftStageIndex < _nftStages.length, "Out of length");
        for(uint userIndex = 0; userIndex < _stakingUsers[nftStageIndex].length; userIndex++){
            _calculateInterest(_stakingUsers[nftStageIndex][userIndex]);
        }
        _nftStages[nftStageIndex].annualProfit = annualProfit;
    }
    
    /**
     * @dev See IAvatarArtStaking
     */ 
    function stake(uint nftStageIndex, uint amount) external override isRunning returns(bool){
        //CHECK REQUIREMENTS
        require(nftStageIndex < _nftStages.length, "Out of length");
        require(amount > 0, "Amount should be greater than zero");
        
        //Check for minimum staking amount
        NftStage memory nftStage = _nftStages[nftStageIndex];
        require(nftStage.isActive, "This staking stage is inactive");
        if(nftStage.minAmount > 0){
            require(amount >= nftStage.minAmount, "Not enough mininum amount to stake");
        }
        
        //Transfer token from user address to contract
        require(IERC20(_bnuTokenAddress).transferFrom(_msgSender(), address(this), amount), "Can not transfer token to contract");
        
        //Calculate interest and store with extra interest
        _calculateInterest(_msgSender());
        
        //Create staking history
        TransactionHistory[] storage stakingHistories = _stakingHistories[nftStageIndex][_msgSender()];
        stakingHistories.push(TransactionHistory(_now(), amount));
        
        //Update user staked amount and contract staked amount
        _userStakeds[nftStageIndex][_msgSender()] += amount;
        _totalStakedAmount += amount;
        
        if(!_isUserStaked(nftStageIndex, _msgSender()))
            _stakingUsers[nftStageIndex].push(_msgSender());
        
        //Store the last time user staked
        _userLastStakingTimes[nftStageIndex][_msgSender()] = _now();
        
        //Emit events
        emit Staked(_msgSender(), amount);
        
        return true;
    }
    
    /**
     * @dev Stop staking program
     */ 
    function stop() external onlyOwner{
        _isRunning = false;
        _stopTime = _now();

        IERC20 bnuTokenContract = IERC20(_bnuTokenAddress);
        if(bnuTokenContract.balanceOf(address(this)) > _totalStakedAmount)
            bnuTokenContract.transfer(_owner, bnuTokenContract.balanceOf(address(this)) - _totalStakedAmount);
        
        emit Stopped(_now());
    }
    
    /**
     * @dev See IAvatarArtStaking
     */ 
    function withdraw(uint nftStageIndex, uint amount) external override returns(bool){
        require(nftStageIndex < _nftStages.length, "Out of length");
        //Calculate interest and store with extra interest
        _calculateInterest(_msgSender());
        
        IERC20 bnuTokenContract = IERC20(_bnuTokenAddress);
        
        //Calculate to withdraw staked amount
        if(amount > 0){
            uint lastStakingTime = _userLastStakingTimes[nftStageIndex][_msgSender()];
            if(lastStakingTime + _nftStages[nftStageIndex].duration < _now()){
                _userStakeds[nftStageIndex][_msgSender()] -= amount;    //Do not need to check `amount` <= user staked
                _totalStakedAmount -= amount;
                
                require(bnuTokenContract.transfer(_msgSender(), amount), "Can not pay staked amount for user");
            }
        }
        
        uint eanedAmount = _userEarneds[_msgSender()];
        
        //Pay all interest
        if(eanedAmount > 0){
            //Make sure that user can withdraw all their staked amount
            if(bnuTokenContract.balanceOf(address(this)) - _totalStakedAmount >= eanedAmount){
                require(bnuTokenContract.transfer(_msgSender(), eanedAmount), "Can not pay interest for user");
                _userEarneds[_msgSender()] = 0;
            }
        }
        
        if(amount > 0)
            _withdrawHistories[nftStageIndex][_msgSender()].push(TransactionHistory(_now(), amount));
        
        //Emit events 
        emit Withdrawn(_msgSender(), amount);
        
        return true;
    }
    
    /**
     * @dev Calculate and update user pending interest
     */ 
    function _calculateInterest(address account) internal{
        for(uint nftStageIndex = 0; nftStageIndex < _nftStages.length; nftStageIndex++){
            NftStage memory nftStage = _nftStages[nftStageIndex];
            if(nftStage.isActive){
                uint userStakedAmount = _userStakeds[nftStageIndex][account];
                if(userStakedAmount > 0){
                    uint earnedAmount = _calculatePendingEarned(nftStageIndex, userStakedAmount, _getUserRewardPendingTime(nftStageIndex, account));
                    _userEarneds[account] += earnedAmount;
                }
                _userLastEarnedTimes[nftStageIndex][account] = _now();
            }
        }
    }
    
    /**
     * @dev Calculate interest for user from `lastStakingTime` to  `now`
     * based on user staked amount and annualProfit
     */ 
    function _calculatePendingEarned(uint nftStageIndex, uint userStakedAmount, uint pendingTime) internal view returns(uint){
        return userStakedAmount * pendingTime * _nftStages[nftStageIndex].annualProfit / APR_MULTIPLIER / ONE_YEAR / 100;
    }
    
    /**
     * @dev Check user has staked or not
     */
    function _isUserStaked(uint nftStageIndex, address account) internal view returns(bool){
        for(uint index = 0; index < _stakingUsers[nftStageIndex].length; index++){
            if(_stakingUsers[nftStageIndex][index] == account)
                return true;
        }
        
        return false;
    }
    
    function _getUserLastEarnedTime(uint nftStageIndex, address account) internal view returns(uint){
        return _userLastEarnedTimes[nftStageIndex][account];
    }
    
    function _getUserRewardPendingTime(uint nftStageIndex, address account) internal view returns(uint){
        if(!_isRunning && _stopTime > 0)
            return _stopTime - _getUserLastEarnedTime(nftStageIndex, account);
        return _now() - _getUserLastEarnedTime(nftStageIndex, account);
    }
    
    event Staked(address account, uint amount);
    event Withdrawn(address account, uint amount);
    event Stopped(uint time);
}