// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// ERC20 Token Interface
interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract P2POTC {
    IERC20 public bettingToken;
    address public owner;
    uint256 private orderIdCounter;
    uint256 public platformFeePercentage = 50; // 5% platform fee by default
    address public platformFeeRecipient; // Address to receive platform fees

    // Enum to represent the different statuses of an order
    enum OrderStatus { Open, Processing, Completed, Cancelled, RefundRequested }

    // Struct to represent an order
    struct Order {
        address seller;
        address buyer;
        uint256 fullAmount; // Full amount provided by the seller
        uint256 netAmount;  // Amount after fee deduction (used for buyer transfer)
        uint256 price;
        OrderStatus status;
        uint256 createdAt;
        uint256 confirmedAt;
    }

    mapping(uint256 => Order) private orders;

    // Events
    event OrderCreated(uint256 orderId, address seller, uint256 amount, uint256 price);
    event OrderCancelled(uint256 orderId);
    event OrderProcessing(uint256 orderId);
    event OrderCompleted(uint256 orderId, address buyer);
    event OrderCompletedByAdmin(uint256 orderId, address buyer);
    event OrderCancelledByAdmin(uint256 orderId);
    event TokenUpdated(address newToken);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event PlatformFeeUpdated(uint256 newFeePercentage);
    event PlatformFeeRecipientUpdated(address newRecipient);

    // Modifier to restrict access to only the contract owner
    modifier onlyOwner() {
        require(msg.sender == owner, "Not the owner");
        _;
    }

    // Constructor to initialize the contract with the ERC20 token address
    constructor(address _bettingToken) {
        bettingToken = IERC20(_bettingToken);
        owner = msg.sender;
        orderIdCounter = 0;
    }

    // Function to create a new order
    function createOrder(uint256 _amount, uint256 _price) external {
        require(_amount > 0, "Amount must be greater than 0");
        require(_price > 0, "Price must be greater than 0");

        uint256 orderId = orderIdCounter++;
        uint256 platformFee = (_amount * platformFeePercentage) / 10000;
        uint256 netAmount = _amount - platformFee;

        orders[orderId] = Order({
            seller: msg.sender,
            buyer: address(0),
            fullAmount: _amount,  // Store the full amount provided by the seller
            netAmount: netAmount, // Store the net amount after fee deduction
            price: _price,
            status: OrderStatus.Open,
            createdAt: block.timestamp,
            confirmedAt: 0
        });

        // Transfer tokens from seller to the contract for security
        require(bettingToken.transferFrom(msg.sender, address(this), _amount), "Transfer failed");

        emit OrderCreated(orderId, msg.sender, _amount, _price);
    }

    // Function to cancel an order by the seller
    function cancelOrder(uint256 _orderId) external {
        Order storage order = orders[_orderId];
        require(order.seller == msg.sender, "Not the seller");
        require(order.status == OrderStatus.Open, "Order not open");
        
        // Refund the full amount to the seller
        require(bettingToken.transfer(order.seller, order.fullAmount), "Transfer failed");

        order.status = OrderStatus.Cancelled;
        emit OrderCancelled(_orderId);
    }

    // Function to cancel an order by the admin
    function cancelOrderByAdmin(uint256 _orderId) external onlyOwner {
        Order storage order = orders[_orderId];
        require(order.status == OrderStatus.Processing, "Order not processing");
        require(order.confirmedAt != 0, "Order not confirmed");

        require(bettingToken.transfer(order.seller, order.fullAmount), "Transfer failed");

        order.status = OrderStatus.Cancelled;
        emit OrderCancelledByAdmin(_orderId);
    }

    // Function for the buyer to confirm an order
    function confirmOrder(uint256 _orderId) external {
        Order storage order = orders[_orderId];
        require(order.confirmedAt == 0, "Order already confirmed");
        require(order.seller != address(0), "Seller does not exist");
        require(order.status == OrderStatus.Open, "Order not open");
        require(order.buyer == address(0), "Buyer already exists");

        order.buyer = msg.sender;
        order.status = OrderStatus.Processing;
        order.confirmedAt = block.timestamp;

        emit OrderProcessing(_orderId);
    }

    // Function to complete an order by the seller
    function completeOrder(uint256 _orderId) external {
        Order storage order = orders[_orderId];
        require(order.seller == msg.sender, "Not the seller");
        require(order.status == OrderStatus.Processing, "Order not processing");

        // Transfer the net amount to the buyer
        require(bettingToken.transfer(order.buyer, order.netAmount), "Transfer failed");

        // Transfer the platform fee to the designated recipient
        uint256 platformFee = order.fullAmount - order.netAmount;
        require(bettingToken.transfer(platformFeeRecipient, platformFee), "Transfer failed");

        order.status = OrderStatus.Completed;
        emit OrderCompleted(_orderId, order.buyer);
    }

    // Function to complete an order by the admin
    function completeOrderByAdmin(uint256 _orderId) external onlyOwner {
        Order storage order = orders[_orderId];
        require(order.status == OrderStatus.Processing, "Order not processing");

        // Transfer the net amount to the buyer
        require(bettingToken.transfer(order.buyer, order.netAmount), "Transfer failed");

        // Transfer the platform fee to the designated recipient
        uint256 platformFee = order.fullAmount - order.netAmount;
        require(bettingToken.transfer(platformFeeRecipient, platformFee), "Transfer failed");

        order.status = OrderStatus.Completed;
        emit OrderCompletedByAdmin(_orderId, order.buyer);
    }

    // Function to withdraw tokens from the contract to the owner's address
    function withdraw(uint256 _amount) external onlyOwner {
        require(bettingToken.balanceOf(address(this)) >= _amount, "Insufficient balance");
        require(bettingToken.transfer(owner, _amount), "Transfer failed");
    }

    // Function to withdraw any token from the contract to the owner's address
    function withdrawToken(address _token, uint256 _amount) external onlyOwner {
        IERC20 token = IERC20(_token);
        require(token.balanceOf(address(this)) >= _amount, "Insufficient balance");
        require(token.transfer(owner, _amount), "Transfer failed");
    }

    // Function to set a new token address
    function setToken(address _newToken) external onlyOwner {
        require(_newToken != address(0), "Invalid token address");
        bettingToken = IERC20(_newToken);
        emit TokenUpdated(_newToken);
    }

    // Function to transfer ownership of the contract
    function transferOwnership(address _newOwner) external onlyOwner {
        require(_newOwner != address(0), "New owner is the zero address");
        emit OwnershipTransferred(owner, _newOwner);
        owner = _newOwner;
    }

    // Function to set the platform fee recipient address
    function setPlatformFeeRecipient(address _recipient) external onlyOwner {
        require(_recipient != address(0), "Invalid address");
        platformFeeRecipient = _recipient;
        emit PlatformFeeRecipientUpdated(_recipient);
    }

    // Function to update the platform fee percentage
    function setPlatformFeePercentage(uint256 _percentage) external onlyOwner {
        require(_percentage <= 10000, "Fee percentage too high"); // Max is 100% = 10000
        platformFeePercentage = _percentage;
        emit PlatformFeeUpdated(_percentage);
    }

    // Function to get the details of an order
    function getOrderDetails(uint256 _orderId) external view returns (
        address seller, 
        address buyer, 
        uint256 fullAmount, 
        uint256 price, 
        OrderStatus status, 
        uint256 createdAt, 
        uint256 confirmedAt
    ) {
        Order memory order = orders[_orderId];
        return (
            order.seller,
            order.buyer,
            order.fullAmount, // Full amount, without fee deduction
            order.price,
            order.status,
            order.createdAt,
            order.confirmedAt
        );
    }

    // Function to count the total number of orders created
    function countOrders() external view returns (uint256) {
        return orderIdCounter; 
    }
}
