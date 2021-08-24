// SPDX-License-Identifier: MIT

import ".././interfaces/IERC20.sol";
import ".././interfaces/IAvatarArtExchange.sol";
import ".././core/Runnable.sol";

pragma solidity ^0.8.0;

contract AvatarArtOrderBook is Runnable, IAvatarArtExchange{
    modifier onlyAdmin{
        require(_msgSender() == deployerAddress || _msgSender() == _owner, "Forbidden");
        _;
    }
    enum EOrderType{
        Buy, 
        Sell
    }
    
    enum EOrderStatus{
        Open,
        Filled,
        Canceled
    }
    
    struct Order{
        uint256 orderId;
        address owner;
        uint256 price;
        uint256 quantity;
        uint256 filledQuantity;
        uint256 time;
        EOrderStatus status;
        uint256 fee;
    }
    
    uint256 constant public MULTIPLIER = 1000;
    
    //Address of contract that will generate token for specific NFT
    address public deployerAddress;
    
    uint256 public _fee;
    uint256 private _buyOrderIndex = 1;
    uint256 private _sellOrderIndex = 1;
    
    //Checks whether an `token0Address` can be tradable or not
    mapping(address => mapping(address => bool)) public _isTradable;
    
    //Stores users' orders for trading
    mapping(address => mapping(address => Order[])) public _buyOrders;
    mapping(address => mapping(address => Order[])) public _sellOrders;
    
    uint256 private _feeTotal = 0;
    
    constructor(uint256 fee){
        _fee = fee;
    }
    
    /**
     * @dev Get all open orders by `token0Address`
     */ 
    function getOpenOrders(address token0Address, address token1Address, EOrderType orderType) public view returns(Order[] memory){
        Order[] memory orders;
        if(orderType == EOrderType.Buy)
            orders = _buyOrders[token0Address][token1Address];
        else
            orders = _sellOrders[token0Address][token1Address];
        if(orders.length == 0)
            return orders;
        
        uint256 count = 0;
        Order[] memory tempOrders = new Order[](orders.length);
        for(uint256 index = 0; index < orders.length; index++){
            Order memory order = orders[index];
            if(order.status == EOrderStatus.Open){
                tempOrders[count] = order;
                count++;
            }
        }
        
        Order[] memory result = new Order[](count);
        for(uint256 index = 0; index < count; index++){
            result[index] = tempOrders[index];
        }
        
        return result;
    }
    
    /**
     * @dev Get buying orders that can be filled with `price` of `token0Address`
     */ 
    function getOpenBuyOrdersForPrice(address token0Address, address token1Address, uint256 price) public view returns(Order[] memory){
        Order[] memory orders = _buyOrders[token0Address][token1Address];
        if(orders.length == 0)
            return orders;
        
        uint256 count = 0;
        Order[] memory tempOrders = new Order[](orders.length);
        for(uint256 index = 0; index < orders.length; index++){
            Order memory order = orders[index];
            if(order.status == EOrderStatus.Open && order.price >= price){
                tempOrders[count] = order;
                count++;
            }
        }
        
        Order[] memory result = new Order[](count);
        for(uint256 index = 0; index < count; index++){
            result[index] = tempOrders[index];
        }
        
        return result;
    }
    
    function getOrders(address token0Address, address token1Address, EOrderType orderType) public view returns(Order[] memory){
        return orderType == EOrderType.Buy ? _buyOrders[token0Address][token1Address] : _sellOrders[token0Address][token1Address];
    }
    
    function getUserOrders(address token0Address, address token1Address, address account, EOrderType orderType) public view returns(Order[] memory){
        Order[] memory orders;
        if(orderType == EOrderType.Buy)
            orders = _buyOrders[token0Address][token1Address];
        else
            orders = _sellOrders[token0Address][token1Address];
        if(orders.length == 0)
            return orders;
        
        uint256 count = 0;
        Order[] memory tempOrders = new Order[](orders.length);
        for(uint256 index = 0; index < orders.length; index++){
            Order memory order = orders[index];
            if(order.owner == account){
                tempOrders[count] = order;
                count++;
            }
        }
        
        Order[] memory result = new Order[](count);
        for(uint256 index = 0; index < count; index++){
            result[index] = tempOrders[index];
        }
        
        return result;
    }
    
    /**
     * @dev Get selling orders that can be filled with `price` of `token0Address`
     */ 
    function getOpenSellOrdersForPrice(address token0Address, address token1Address, uint256 price) public view returns(Order[] memory){
        Order[] memory orders = _sellOrders[token0Address][token1Address];
        if(orders.length == 0)
            return orders;
        
        uint256 count = 0;
        Order[] memory tempOrders = new Order[](orders.length);
        for(uint256 index = 0; index < orders.length; index++){
            Order memory order = orders[index];
            if(order.status == EOrderStatus.Open && order.price <= price){
                tempOrders[count] = order;
                count++;
            }
        }
        
        Order[] memory result = new Order[](count);
        for(uint256 index = 0; index < count; index++){
            result[index] = tempOrders[index];
        }
        
        return result;
    }
    
    function setFee(uint256 fee) public onlyOwner{
        _fee = fee;
    }
    
    function setDeployerAddress(address newAddress) public onlyOwner{
        require(newAddress != address(0), "Zero address");
        deployerAddress = newAddress;
    }
    
   /**
     * @dev Allow or disallow `token0Address` to be traded on AvatarArtOrderBook
    */
    function toogleTradableStatus(address token0Address, address token1Address) public override onlyAdmin returns(bool){
        _isTradable[token0Address][token1Address] = !_isTradable[token0Address][token1Address];
        return true;
    }
    
    /**
     * @dev See {IAvatarArtOrderBook.buy}
     * 
     * IMPLEMENTATION
     *    1. Validate requirements
     *    2. Process buy order 
     */ 
    function buy(address token0Address, address token1Address, uint256 price, uint256 quantity) public override isRunning returns(bool){
        require(_isTradable[token0Address][token1Address], "Can not tradable");
        require(price > 0 && quantity > 0, "Zero input");
        
        uint256 matchedQuantity = 0;
        uint256 needToMatchedQuantity = quantity;
        
        Order memory order = Order({
            orderId: _buyOrderIndex,
            owner: _msgSender(),
            price: price,
            quantity: quantity,
            filledQuantity: 0,
            time: _now(),
            fee: _fee,
            status: EOrderStatus.Open
        });
        
        uint256 totalPaidAmount = 0;
        //Get all open sell orders that are suitable for `price`
        Order[] memory matchedOrders = getOpenSellOrdersForPrice(token0Address, token1Address, price);
        if (matchedOrders.length > 0){
            matchedQuantity = 0;
            uint256 changePrice = 0;
            for(uint256 index = 0; index < matchedOrders.length; index++)
            {
                Order memory matchedOrder = matchedOrders[index];
                uint256 matchedOrderRemainQuantity = matchedOrder.quantity - matchedOrder.filledQuantity;
                uint256 currentFilledQuantity = 0;
                if (needToMatchedQuantity < matchedOrderRemainQuantity)     //Filled
                {
                    matchedQuantity = quantity;
                    
                    //Update matchedOrder matched quantity
                    _increaseFilledQuantity(token0Address, token1Address, EOrderType.Sell, matchedOrder.orderId, needToMatchedQuantity);
                    
                    currentFilledQuantity = needToMatchedQuantity;
                    needToMatchedQuantity = 0;
                }
                else
                {
                    matchedQuantity += matchedOrderRemainQuantity;
                    needToMatchedQuantity -= matchedOrderRemainQuantity;
                    currentFilledQuantity = matchedOrderRemainQuantity;

                    //Update matchedOrder to completed
                    _updateOrderToBeFilled(token0Address, token1Address, matchedOrder.orderId, EOrderType.Sell);
                }

                if (matchedOrder.price != changePrice)
                {
                    changePrice = matchedOrder.price;
                    emit PriceChanged(token0Address, token1Address, changePrice, _now());
                }

                totalPaidAmount += currentFilledQuantity * matchedOrder.price;
                
                //Create matched order
                emit OrderFilled(token0Address, token1Address, order.orderId, matchedOrder.orderId, matchedOrder.price, currentFilledQuantity, _now());

                //Increase buy user token0 balance
                _feeTotal += currentFilledQuantity * _fee / 100 / MULTIPLIER;
                IERC20(token0Address).transfer(_msgSender(), currentFilledQuantity * (1 - _fee / 100 / MULTIPLIER));

                //Increase sell user token1 balance
                IERC20(token1Address).transfer(matchedOrder.owner, currentFilledQuantity * matchedOrder.price * (1 - matchedOrder.fee / 100 / MULTIPLIER));

                emit RefreshUserOrders(token0Address, token1Address, matchedOrder.owner);
                
                if (needToMatchedQuantity == 0)
                    break;
            }
        }

        totalPaidAmount += price * (quantity - matchedQuantity);
        if(totalPaidAmount > 0)
            IERC20(token1Address).transferFrom(_msgSender(), address(this), totalPaidAmount);

        //Create order
        order.filledQuantity = matchedQuantity;
        if(order.filledQuantity != quantity)
            order.status = EOrderStatus.Open;
        else
            order.status = EOrderStatus.Filled;
        _buyOrders[token0Address][token1Address].push(order);
        
        if(_feeTotal > 0){
            IERC20(token0Address).transfer(_owner, _feeTotal);
            _feeTotal = 0;
        }
        
        emit RefreshUserOrders(token0Address, token1Address, _msgSender());
        
        //Event for all user to refresh buy order
        emit RefreshOpenOrders(token0Address, token1Address, EOrderType.Buy);
        
        //If has matchedOrders, emit event for refresh sell order
        if (matchedOrders.length > 0)
            emit RefreshOpenOrders(token0Address, token1Address, EOrderType.Sell);
        
        _buyOrderIndex++;
        emit OrderCreated(_now(), _msgSender(), token0Address, token1Address, EOrderType.Buy, price, quantity);
        return true;
    }
    
    /**
     * @dev Sell `token0Address` with `price` and `amount`
     */ 
    function sell(address token0Address, address token1Address, uint256 price, uint256 quantity) public override isRunning returns(bool){
        require(_isTradable[token0Address][token1Address], "Can not tradable");
        require(price > 0 && quantity > 0, "Zero input");
        
        uint256 matchedQuantity = 0;
        uint256 needToMatchedQuantity = quantity;

        Order memory order = Order({
            orderId: _sellOrderIndex,
            owner: _msgSender(),
            price: price,
            quantity: quantity,
            filledQuantity: 0,
            time: _now(),
            fee: _fee,
            status: EOrderStatus.Open
        });
        
        IERC20(token0Address).transferFrom(_msgSender(), address(this), quantity);
        Order[] memory matchedOrders = getOpenBuyOrdersForPrice(token0Address, token1Address, price);
        if (matchedOrders.length > 0){
            matchedQuantity = 0;
            uint256 changedPrice = 0;
            for(uint index = 0; index < matchedOrders.length; index++)
            {
                Order memory matchedOrder = matchedOrders[index];
                uint256 matchedOrderRemainQuantity = matchedOrder.quantity - matchedOrder.filledQuantity;
                uint256 currentMatchedQuantity = 0;
                if (needToMatchedQuantity < matchedOrderRemainQuantity)     //Filled
                {
                    matchedQuantity = quantity;
                    
                     //Update matchedOrder matched quantity
                    _increaseFilledQuantity(token0Address, token1Address, EOrderType.Buy, matchedOrder.orderId, needToMatchedQuantity);

                    currentMatchedQuantity = needToMatchedQuantity;
                    needToMatchedQuantity = 0;
                }
                else
                {
                    matchedQuantity += matchedOrderRemainQuantity;
                    needToMatchedQuantity -= matchedOrderRemainQuantity;
                    currentMatchedQuantity = matchedOrderRemainQuantity;

                    //Update matchedOrder to completed
                    _updateOrderToBeFilled(token0Address, token1Address, matchedOrder.orderId, EOrderType.Buy);
                }
                
                emit OrderFilled(token0Address, token1Address, matchedOrder.orderId, order.orderId, matchedOrder.price, currentMatchedQuantity, _now());
               
                if (matchedOrder.price != changedPrice)
                    emit PriceChanged(token0Address, token1Address, changedPrice, _now());

                //Increase buy user token0 balance
                IERC20(token0Address).transfer(matchedOrder.owner, currentMatchedQuantity * (1 - matchedOrder.fee / 100 / MULTIPLIER));

                //Increase sell user token1 balance
                _feeTotal += currentMatchedQuantity * matchedOrder.price * _fee / 100 / MULTIPLIER;
                IERC20(token1Address).transfer(_msgSender(), currentMatchedQuantity * matchedOrder.price * (1 - _fee / 100 / MULTIPLIER));

                emit RefreshUserOrders(token0Address, token1Address, matchedOrder.owner);

                if (needToMatchedQuantity == 0)
                    break;
            }
        }

        order.filledQuantity = matchedQuantity;
        if(order.filledQuantity != quantity)
            order.status = EOrderStatus.Open;
        else
            order.status = EOrderStatus.Filled;
       
        _sellOrders[token0Address][token1Address].push(order);
        
        if(_feeTotal > 0){
            IERC20(token1Address).transfer(_owner, _feeTotal);
            _feeTotal = 0;
        }
        
        emit RefreshUserOrders(token0Address, token1Address, _msgSender());
        
        //Event for all user to refresh buy order
        emit RefreshOpenOrders(token0Address, token1Address, EOrderType.Sell);
        
        //If has matchedOrders, emit event for refresh sell order
        if (matchedOrders.length > 0)
            emit RefreshOpenOrders(token0Address, token1Address, EOrderType.Buy);

        _sellOrderIndex++;
        emit OrderCreated(_now(), _msgSender(), token0Address, token1Address, EOrderType.Sell, price, quantity);
        return true;
    }
    
    /**
     * @dev Cancel an open trading order for `token0Address` by `orderId`
     */ 
    function cancel(address token0Address, address token1Address, uint256 orderId, uint256 orderType) public override isRunning returns(bool){
        EOrderType eOrderType = EOrderType(orderType);
        require(eOrderType == EOrderType.Buy || eOrderType == EOrderType.Sell,"Invalid order type");
        
        if(eOrderType == EOrderType.Buy)
            return _cancelBuyOrder(token0Address, token1Address, orderId);
        else
            return _cancelSellOrder(token0Address, token1Address, orderId);
    }
    
    /**
     * @dev Cancel buy order
     */ 
    function _cancelBuyOrder(address token0Address, address token1Address, uint256 orderId) internal returns(bool){
        for(uint256 index = 0; index < _buyOrders[token0Address][token1Address].length; index++){
            Order storage order = _buyOrders[token0Address][token1Address][index];
            if(order.orderId == orderId){
                if(order.status != EOrderStatus.Open)
                    revert("Order is not open");
                
                order.status = EOrderStatus.Canceled;
                IERC20(token1Address).transfer(order.owner, (order.quantity - order.filledQuantity) * order.price);
                break;
            }
        }
        return true;
    }
    
    /**
     * @dev Cancel sell order
     */ 
    function _cancelSellOrder(address token0Address, address token1Address, uint256 orderId) internal returns(bool){
        for(uint256 index = 0; index < _sellOrders[token0Address][token1Address].length; index++){
            Order storage order = _sellOrders[token0Address][token1Address][index];
            if(order.orderId == orderId){
                if(order.status != EOrderStatus.Open)
                    revert("Order is not open");
                
                order.status = EOrderStatus.Canceled;
                IERC20(token0Address).transfer(order.owner, order.quantity - order.filledQuantity);
                break;
            }
        }
        return true;
    }
    
    /**
     * @dev Increase filled quantity of specific order
     */ 
    function _increaseFilledQuantity(address token0Address, address token1Address, EOrderType orderType, uint256 orderId, uint256 quantity) internal {
        if(orderType == EOrderType.Buy){
            for(uint256 index = 0; index < _buyOrders[token0Address][token1Address].length; index++){
                Order storage order = _buyOrders[token0Address][token1Address][index];
                if(order.orderId == orderId){
                    order.filledQuantity += quantity;
                    break;
                }
            }
        }else{
            for(uint256 index = 0; index < _sellOrders[token0Address][token1Address].length; index++){
                Order storage order = _buyOrders[token0Address][token1Address][index];
                if(order.orderId == orderId){
                    order.filledQuantity += quantity;
                    break;
                }
            }
        }
    }
    
    /**
     * @dev Update the order is filled all
     */ 
    function _updateOrderToBeFilled(address token0Address, address token1Address, uint256 orderId, EOrderType orderType) internal{
        if(orderType == EOrderType.Buy){
            for(uint256 index = 0; index < _buyOrders[token0Address][token1Address].length; index++){
                Order storage order = _buyOrders[token0Address][token1Address][index];
                if(order.orderId == orderId){
                    order.filledQuantity == order.quantity;
                    order.status = EOrderStatus.Filled;
                    break;
                }
            }
        }else{
            for(uint256 index = 0; index < _sellOrders[token0Address][token1Address].length; index++){
                Order storage order = _buyOrders[token0Address][token1Address][index];
                if(order.orderId == orderId){
                    order.filledQuantity == order.quantity;
                    order.status = EOrderStatus.Filled;
                    break;
                }
            }
        }
    }
    
    event OrderCreated(uint256 time, address indexed account, address token0Address, address token1Address, EOrderType orderType, uint256 price, uint256 quantity);
    event PriceChanged(address token0Address, address token1Address, uint256 price, uint256 time);
    event RefreshUserOrders(address token0Address, address token1Address, address account);
    event RefreshOpenOrders(address token0Address, address token1Address, EOrderType orderType);
    event OrderFilled(address token0Address, address token1Address, uint256 buyOrderId, uint256 sellOrderId, uint256 price, uint256 quantity, uint256 time);
}