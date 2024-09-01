// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// BEP20 Token Interface
interface IBEP20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract P2POTC {
    IBEP20 public usdtToken;

    // Enum to represent the different statuses of an order
    enum OrderStatus { Open, Processing, Completed, Cancelled, RefundRequested }

    // Struct to represent an order
    struct Order {
        address seller;         // Address of the seller
        address buyer;          // Address of the buyer
        uint256 amount;         // Amount of tokens in the order
        uint256 price;          // Price of the order in tokens
        OrderStatus status;     // Current status of the order
        uint256 createdAt;      // Timestamp when the order was created
        uint256 confirmedAt;    // Timestamp when the order was confirmed by the buyer
    }

    address public owner;          // Address of the contract owner
    uint256 private orderIdCounter; // Counter for generating unique order IDs

    mapping(uint256 => Order) private orders; // Mapping from order ID to Order struct

    // Events to log actions performed on orders
    event OrderCreated(uint256 orderId, address seller, uint256 amount, uint256 price);
    event OrderCancelled(uint256 orderId);
    event OrderProcessing(uint256 orderId);
    event OrderCompleted(uint256 orderId, address buyer);
    event OrderCompletedByAdmin(uint256 orderId, address buyer);
    event OrderCancelledByAdmin(uint256 orderId);

    // Modifier to restrict access to only the contract owner
    modifier onlyOwner() {
        require(msg.sender == owner, "Not the owner");
        _;
    }

    // Constructor to initialize the contract with the USDT token address
    constructor(address _usdtToken) {
        usdtToken = IBEP20(_usdtToken);
        owner = msg.sender;
        orderIdCounter = 0; // Start order ID counter from 0
    }

    // Function to create a new order
    function createOrder(uint256 _amount, uint256 _price) external {
        require(_amount > 0, "Amount must be greater than 0");
        require(_price > 0, "Price must be greater than 0");

        uint256 orderId = orderIdCounter++;
        orders[orderId] = Order({
            seller: msg.sender,
            buyer: address(0), // No buyer at the time of order creation
            amount: _amount,
            price: _price,
            status: OrderStatus.Open,
            createdAt: block.timestamp,
            confirmedAt: 0
        });

        // Transfer USDT from seller to the contract for security
        require(usdtToken.transferFrom(msg.sender, address(this), _amount), "Transfer failed");

        emit OrderCreated(orderId, msg.sender, _amount, _price);
    }

    // Function to cancel an order by the seller
    function cancelOrder(uint256 _orderId) external {
        Order storage order = orders[_orderId];
        require(order.seller == msg.sender, "Not the seller");
        require(order.status == OrderStatus.Open, "Order not open");
        
        // Return USDT to seller if order is cancelled
        require(usdtToken.transfer(order.seller, order.amount), "Transfer failed");

        order.status = OrderStatus.Cancelled;
        emit OrderCancelled(_orderId);
    }

    // Function to cancel an order by the admin
    function cancelOrderByAdmin(uint256 _orderId) external onlyOwner {
        Order storage order = orders[_orderId];
        require(order.status == OrderStatus.Processing, "Order not processing");
        require(order.confirmedAt != 0, "Order not confirmed");

        // Return USDT to seller if order is cancelled by admin
        require(usdtToken.transfer(order.seller, order.amount), "Transfer failed");

        order.status = OrderStatus.Cancelled;
        emit OrderCancelledByAdmin(_orderId);
    }

    // Function for the buyer to confirm an order
    function confirmOrder(uint256 _orderId) external {
        Order storage order = orders[_orderId];
        
        // Check if the order has already been confirmed
        require(order.confirmedAt == 0, "Order already confirmed");
        
        // Check if the seller exists and is not a null address
        require(order.seller != address(0), "Seller does not exist");
        
        // Check if the order status is "Open"
        require(order.status == OrderStatus.Open, "Order not open");
        
        // Check if the buyer has not already been set
        require(order.buyer == address(0), "Buyer already exists");
        
        // Set the buyer for the order
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

        // Transfer USDT to the buyer
        require(usdtToken.transfer(order.buyer, order.amount), "Transfer failed");

        order.status = OrderStatus.Completed;
        emit OrderCompleted(_orderId, order.buyer);
    }

    // Function to complete an order by the admin
    function completeOrderByAdmin(uint256 _orderId) external onlyOwner {
        Order storage order = orders[_orderId];
        require(order.status == OrderStatus.Processing, "Order not processing");

        // Complete the order and transfer USDT to the buyer if the seller does not complete it in time
        require(usdtToken.transfer(order.buyer, order.amount), "Transfer failed");
        order.status = OrderStatus.Completed;
        emit OrderCompletedByAdmin(_orderId, order.buyer);
    }

    // Function to withdraw USDT from the contract to the owner's address
    function withdraw(uint256 _amount) external onlyOwner {
        require(usdtToken.balanceOf(address(this)) >= _amount, "Insufficient balance");
        require(usdtToken.transfer(owner, _amount), "Transfer failed");
    }

    // Function to withdraw any token from the contract to the owner's address
    function withdrawToken(address _token, uint256 _amount) external onlyOwner {
        IBEP20 token = IBEP20(_token);
        require(token.balanceOf(address(this)) >= _amount, "Insufficient balance");
        require(token.transfer(owner, _amount), "Transfer failed");
    }

    // Function to get the details of an order
    function getOrderDetails(uint256 _orderId) external view returns (
        address seller, 
        address buyer, 
        uint256 amount, 
        uint256 price, 
        OrderStatus status, 
        uint256 createdAt, 
        uint256 confirmedAt
    ) {
        Order memory order = orders[_orderId];
        return (
            order.seller,
            order.buyer,
            order.amount,
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
