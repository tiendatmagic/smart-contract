// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// ERC20 Token Interface
interface IERC20 {
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);

    function approve(address spender, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);
}

contract P2POTC {
    IERC20 public bettingToken;
    address public owner;
    uint256 private orderIdCounter;
    uint256 public platformFeePercentage = 50; // 5% platform fee by default
    address public platformFeeRecipient; // Address to receive platform fees

    uint256 public minSellAmount;
    uint256 public maxSellAmount;

    // Enum to represent the different statuses of an order
    enum OrderStatus {
        Open,
        Processing,
        Completed,
        Cancelled,
        RefundRequested
    }

    // Struct to represent an order
    struct Order {
        address seller;
        address buyer;
        uint256 fullAmount;
        uint256 netAmount;
        uint256 price;
        OrderStatus status;
        uint256 createdAt;
        uint256 confirmedAt;
        BankDetails sellerBankDetails;
    }

    // Struct to represent seller's bank details
    struct BankDetails {
        string bankName;
        string accountNumber;
        string note;
    }

    mapping(uint256 => Order) private orders;
    mapping(address => BankDetails) private sellerBankDetails;

    // Events
    event OrderCreated(
        uint256 orderId,
        address seller,
        uint256 amount,
        uint256 price
    );
    event OrderCancelled(uint256 orderId);
    event OrderProcessing(uint256 orderId);
    event OrderCompleted(uint256 orderId, address buyer);
    event OrderCompletedByAdmin(uint256 orderId, address buyer);
    event OrderCancelledByAdmin(uint256 orderId);
    event TokenUpdated(address newToken);
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );
    event PlatformFeeUpdated(uint256 newFeePercentage);
    event PlatformFeeRecipientUpdated(address newRecipient);
    event BankDetailsUpdated(
        address seller,
        string bankName,
        string accountNumber,
        string note
    );
    event MinSellAmountUpdated(uint256 newMinSellAmount);
    event MaxSellAmountUpdated(uint256 newMaxSellAmount);

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
        minSellAmount = 0;
        maxSellAmount = 0;
    }

    // Function to create a new order
    function sellerCreateOrder(uint256 _amount, uint256 _price) external {
        require(_amount > 0, "Amount must be greater than 0");
        require(_price > 0, "Price must be greater than 0");
        require(
            _amount >= minSellAmount,
            "Amount must be greater than or equal to the minimum sell amount"
        );
        require(
            _amount <= maxSellAmount,
            "Amount must be less than or equal to the maximum sell amount"
        );

        uint256 orderId = orderIdCounter++;
        uint256 platformFee = (_amount * platformFeePercentage) / 10000;
        uint256 netAmount = _amount - platformFee;

        BankDetails memory bankDetails = sellerBankDetails[msg.sender];

        orders[orderId] = Order({
            seller: msg.sender,
            buyer: address(0),
            fullAmount: _amount,
            netAmount: netAmount,
            price: _price,
            status: OrderStatus.Open,
            createdAt: block.timestamp,
            confirmedAt: 0,
            sellerBankDetails: bankDetails
        });

        require(
            bettingToken.transferFrom(msg.sender, address(this), _amount),
            "Transfer failed"
        );

        emit OrderCreated(orderId, msg.sender, _amount, _price);
    }

    // Function to set the minimum sell amount
    function setMinSellAmount(uint256 _minSellAmount) external onlyOwner {
        require(
            _minSellAmount > 0,
            "Minimum sell amount must be greater than 0"
        );
        minSellAmount = _minSellAmount;
        emit MinSellAmountUpdated(_minSellAmount);
    }

    // Function to set the maximum sell amount
    function setMaxSellAmount(uint256 _maxSellAmount) external onlyOwner {
        require(
            _maxSellAmount > 0,
            "Maximum sell amount must be greater than 0"
        );
        maxSellAmount = _maxSellAmount;
        emit MaxSellAmountUpdated(_maxSellAmount);
    }

    // Function to cancel an order by the seller
    function sellerCancelOrder(uint256 _orderId) external {
        Order storage order = orders[_orderId];
        require(order.seller == msg.sender, "Not the seller");
        require(order.status == OrderStatus.Open, "Order not open");

        // Refund the full amount to the seller
        require(
            bettingToken.transfer(order.seller, order.fullAmount),
            "Transfer failed"
        );

        order.status = OrderStatus.Cancelled;
        emit OrderCancelled(_orderId);
    }

    // Function to cancel an order by the admin
    function sellerCancelOrderByAdmin(uint256 _orderId) external onlyOwner {
        Order storage order = orders[_orderId];
        require(order.status == OrderStatus.Processing, "Order not processing");
        require(order.confirmedAt != 0, "Order not confirmed");

        require(
            bettingToken.transfer(order.seller, order.fullAmount),
            "Transfer failed"
        );

        order.status = OrderStatus.Cancelled;
        emit OrderCancelledByAdmin(_orderId);
    }

    // Function for the buyer to confirm an order
    function buyerConfirmOrder(uint256 _orderId) external {
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
    function sellerCompleteOrder(uint256 _orderId) external {
        Order storage order = orders[_orderId];
        require(order.seller == msg.sender, "Not the seller");
        require(order.status == OrderStatus.Processing, "Order not processing");

        // Transfer the net amount to the buyer
        require(
            bettingToken.transfer(order.buyer, order.netAmount),
            "Transfer failed"
        );

        // Transfer the platform fee to the designated recipient
        uint256 platformFee = order.fullAmount - order.netAmount;
        require(
            bettingToken.transfer(platformFeeRecipient, platformFee),
            "Transfer failed"
        );

        order.status = OrderStatus.Completed;
        emit OrderCompleted(_orderId, order.buyer);
    }

    // Function to complete an order by the admin
    function sellerCompleteOrderByAdmin(uint256 _orderId) external onlyOwner {
        Order storage order = orders[_orderId];
        require(order.status == OrderStatus.Processing, "Order not processing");

        // Transfer the net amount to the buyer
        require(
            bettingToken.transfer(order.buyer, order.netAmount),
            "Transfer failed"
        );

        // Transfer the platform fee to the designated recipient
        uint256 platformFee = order.fullAmount - order.netAmount;
        require(
            bettingToken.transfer(platformFeeRecipient, platformFee),
            "Transfer failed"
        );

        order.status = OrderStatus.Completed;
        emit OrderCompletedByAdmin(_orderId, order.buyer);
    }

    // Function to withdraw tokens from the contract to the owner's address
    function withdraw(uint256 _amount) external onlyOwner {
        require(
            bettingToken.balanceOf(address(this)) >= _amount,
            "Insufficient balance"
        );
        require(bettingToken.transfer(owner, _amount), "Transfer failed");
    }

    // Function to withdraw any token from the contract to the owner's address
    function withdrawToken(address _token, uint256 _amount) external onlyOwner {
        IERC20 token = IERC20(_token);
        require(
            token.balanceOf(address(this)) >= _amount,
            "Insufficient balance"
        );
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
        require(_percentage <= 10000, "Fee percentage too high");
        platformFeePercentage = _percentage;
        emit PlatformFeeUpdated(_percentage);
    }

    // Function to set the bank details for a seller
    function updateBankDetails(
        string memory _bankName,
        string memory _accountNumber,
        string memory _note
    ) external {
        // Check if the seller has any open or processing orders
        bool hasActiveOrders = false;
        for (uint256 i = 0; i < orderIdCounter; i++) {
            Order storage order = orders[i];
            if (
                order.seller == msg.sender &&
                (order.status == OrderStatus.Open ||
                    order.status == OrderStatus.Processing)
            ) {
                hasActiveOrders = true;
                break;
            }
        }
        require(
            !hasActiveOrders,
            "Cannot update bank details with active orders"
        );

        sellerBankDetails[msg.sender] = BankDetails({
            bankName: _bankName,
            accountNumber: _accountNumber,
            note: _note
        });

        emit BankDetailsUpdated(msg.sender, _bankName, _accountNumber, _note);
    }

    // Function to get the details of an order
    function getOrderDetails(
        uint256 _orderId
    )
        external
        view
        returns (
            address seller,
            address buyer,
            uint256 fullAmount,
            uint256 netAmount,
            uint256 price,
            string memory status,
            uint256 createdAt,
            uint256 confirmedAt,
            string memory bankName,
            string memory accountNumber,
            string memory note
        )
    {
        Order storage order = orders[_orderId];
        BankDetails memory bankDetails = order.sellerBankDetails;

        // Chuyển đổi trạng thái từ enum sang chuỗi
        string memory orderStatus;
        if (order.status == OrderStatus.Open) {
            orderStatus = "Open";
        } else if (order.status == OrderStatus.Processing) {
            orderStatus = "Processing";
        } else if (order.status == OrderStatus.Completed) {
            orderStatus = "Completed";
        } else if (order.status == OrderStatus.Cancelled) {
            orderStatus = "Cancelled";
        } else if (order.status == OrderStatus.RefundRequested) {
            orderStatus = "RefundRequested";
        }

        return (
            order.seller,
            order.buyer,
            order.fullAmount,
            order.netAmount,
            order.price,
            orderStatus,
            order.createdAt,
            order.confirmedAt,
            bankDetails.bankName,
            bankDetails.accountNumber,
            bankDetails.note
        );
    }

    // Function to get bank details for a seller
    function getBankDetails(
        address _seller
    )
        external
        view
        returns (
            string memory bankName,
            string memory accountNumber,
            string memory note
        )
    {
        BankDetails memory details = sellerBankDetails[_seller];
        return (details.bankName, details.accountNumber, details.note);
    }

    // Function to count the total number of orders created
    function countOrders() external view returns (uint256) {
        return orderIdCounter;
    }
}
