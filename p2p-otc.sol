// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// ERC20 Token Interface
interface IERC20 {
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function approve(address spender, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);
}

contract P2POTC {
    IERC20 public bettingToken;
    address public owner;
    uint256 private orderIdCounter;

    PlatformConfig public platformConfig;

    struct PlatformConfig {
        uint256 feePercentage;
        address feeRecipient;
        uint256 minSellAmount;
        uint256 maxSellAmount;
        uint256 minBuyAmount;
        uint256 maxBuyAmount;
    }

    struct OrderDetails {
        uint256 orderId;
        address seller;
        address buyer;
        uint256 fullAmount;
        uint256 netAmount;
        uint256 price;
        string status;
        string orderType;
        uint256 createdAt;
        uint256 confirmedAt;
        string bankName;
        string accountNumber;
        string note;
    }

    // Enum to represent the different statuses of an order
    enum OrderStatus {
        Open,
        Processing,
        Completed,
        Cancelled,
        RefundRequested,
        Paid,
        PaymentConfirmed
    }

    enum OrderType {
        Buy,
        Sell
    }

    // Struct to represent an order
    struct Order {
        address seller;
        address buyer;
        uint256 fullAmount;
        uint256 netAmount;
        uint256 price;
        OrderStatus status;
        OrderType orderType;
        uint256 createdAt;
        uint256 confirmedAt;
        uint256 paymentAt;
        BankDetails bankDetail;
    }

    // Struct to represent seller's bank details
    struct BankDetails {
        string bankName;
        string accountNumber;
        string note;
    }

    mapping(uint256 => Order) private orders;
    mapping(address => BankDetails) private bankDetail;

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
    event OrderPaid(uint256 orderId);
    event OrderPaymentConfirmed(uint256 orderId);

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

    event MinBuyAmountUpdated(uint256 newMinBuyAmount);
    event MaxBuyAmountUpdated(uint256 newMaxBuyAmount);

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

        // minSellAmount = 0;
        // maxSellAmount = 0;
        // minBuyAmount = 0;
        // maxBuyAmount = 0;

        platformConfig = PlatformConfig({
            feePercentage: 50, // 5% platform fee by default
            feeRecipient: address(0),
            minSellAmount: 0,
            maxSellAmount: 0,
            minBuyAmount: 0,
            maxBuyAmount: 0
        });
    }

    // Function to create a new order
    function sellerCreateOrder(uint256 _amount, uint256 _price) external {
        require(_amount > 0, "Amount must be greater than 0");
        require(_price > 0, "Price must be greater than 0");
        require(
            _amount >= platformConfig.minSellAmount,
            "Amount must be greater than or equal to the minimum sell amount"
        );
        require(
            _amount <= platformConfig.maxSellAmount,
            "Amount must be less than or equal to the maximum sell amount"
        );

        uint256 orderId = orderIdCounter;
        orderIdCounter++;

        uint256 platformFee = (_amount * platformConfig.feePercentage) / 10000;
        uint256 netAmount = _amount - platformFee;

        // Get the bank details of the seller at the time of order creation
        BankDetails memory bankDetails = bankDetail[msg.sender];

        orders[orderId] = Order({
            seller: msg.sender,
            buyer: address(0),
            fullAmount: _amount,
            netAmount: netAmount,
            price: _price,
            status: OrderStatus.Open,
            orderType: OrderType.Sell,
            createdAt: block.timestamp,
            confirmedAt: 0,
            paymentAt: 0,
            bankDetail: bankDetails // Store bank details at the time of order creation
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
        platformConfig.minSellAmount = _minSellAmount;
        emit MinSellAmountUpdated(_minSellAmount);
    }

    // Function to set the maximum sell amount
    function setMaxSellAmount(uint256 _maxSellAmount) external onlyOwner {
        require(
            _maxSellAmount > 0,
            "Maximum sell amount must be greater than 0"
        );
        platformConfig.maxSellAmount = _maxSellAmount;
        emit MaxSellAmountUpdated(_maxSellAmount);
    }

    function setMinBuyAmount(uint256 _minBuyAmount) external onlyOwner {
        require(_minBuyAmount > 0, "Minimum buy amount must be greater than 0");
        platformConfig.minBuyAmount = _minBuyAmount;
        emit MinBuyAmountUpdated(_minBuyAmount);
    }

    function setMaxBuyAmount(uint256 _maxBuyAmount) external onlyOwner {
        require(_maxBuyAmount > 0, "Maximum buy amount must be greater than 0");
        platformConfig.maxBuyAmount = _maxBuyAmount;
        emit MaxBuyAmountUpdated(_maxBuyAmount);
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
        require(order.orderType == OrderType.Sell, "Not a sell order");
        require(
            order.status == OrderStatus.Open ||
                order.status == OrderStatus.Processing ||
                order.status == OrderStatus.Paid,
            "Order cannot be cancelled"
        );

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
        require(order.seller != msg.sender, "Not the buyer");
        require(order.confirmedAt == 0, "Order already confirmed");
        require(order.orderType == OrderType.Sell, "Not a sell order");
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

        require(order.status == OrderStatus.Paid, "Order not paid");

        // Transfer the net amount to the buyer
        require(
            bettingToken.transfer(order.buyer, order.netAmount),
            "Transfer failed"
        );

        // Transfer the platform fee to the designated recipient
        uint256 platformFee = order.fullAmount - order.netAmount;
        require(
            bettingToken.transfer(platformConfig.feeRecipient, platformFee),
            "Transfer failed"
        );

        order.status = OrderStatus.Completed;
        emit OrderCompleted(_orderId, order.buyer);
    }

    // Function to complete an order by the admin
    function sellerCompleteOrderByAdmin(uint256 _orderId) external onlyOwner {
        Order storage order = orders[_orderId];
        require(order.orderType == OrderType.Sell, "Not a sell order");
        require(order.status == OrderStatus.Paid, "Order not paid");

        // Transfer the net amount to the buyer
        require(
            bettingToken.transfer(order.buyer, order.netAmount),
            "Transfer failed"
        );

        // Transfer the platform fee to the designated recipient
        uint256 platformFee = order.fullAmount - order.netAmount;
        require(
            bettingToken.transfer(platformConfig.feeRecipient, platformFee),
            "Transfer failed"
        );

        order.status = OrderStatus.Completed;
        emit OrderCompletedByAdmin(_orderId, order.buyer);
    }

    function buyerCreateOrder(uint256 _amount, uint256 _price) external {
        require(_amount > 0, "Amount must be greater than 0");
        require(_price > 0, "Price must be greater than 0");

        require(
            _amount >= platformConfig.minBuyAmount,
            "Amount must be greater than or equal to the minimum buy amount"
        );
        require(
            _amount <= platformConfig.maxBuyAmount,
            "Amount must be less than or equal to the maximum buy amount"
        );

        uint256 orderId = orderIdCounter;
        orderIdCounter++;

        uint256 platformFee = (_amount * platformConfig.feePercentage) / 10000;
        uint256 netAmount = _amount - platformFee;

        // Get the bank details of the buyer at the time of order creation
        BankDetails memory bankDetails = bankDetail[msg.sender];

        orders[orderId] = Order({
            seller: address(0),
            buyer: msg.sender,
            fullAmount: _amount,
            netAmount: netAmount,
            price: _price,
            status: OrderStatus.Open,
            orderType: OrderType.Buy,
            createdAt: block.timestamp,
            confirmedAt: 0,
            paymentAt: 0,
            bankDetail: bankDetails
        });

        emit OrderCreated(orderId, msg.sender, _amount, _price);
    }

    function sellerConfirmOrder(uint256 _orderId) external {
        Order storage order = orders[_orderId];
        require(order.buyer != msg.sender, "Not the seller");
        require(order.confirmedAt == 0, "Order already confirmed");
        require(order.orderType == OrderType.Buy, "Not a buy order");
        require(order.seller == address(0), "Seller already exists");
        require(order.status == OrderStatus.Open, "Order not open");
        require(order.buyer != address(0), "Buyer does not exist");

        order.seller = msg.sender;
        order.status = OrderStatus.Processing;
        order.confirmedAt = block.timestamp;

        require(
            bettingToken.transferFrom(
                msg.sender,
                address(this),
                order.fullAmount
            ),
            "Transfer failed"
        );

        emit OrderProcessing(_orderId);
    }

    function buyerCompleteOrder(uint256 _orderId) external {
        Order storage order = orders[_orderId];
        require(order.orderType == OrderType.Buy, "Not a buy order");
        require(
            order.status == OrderStatus.PaymentConfirmed,
            "Payment not confirmed"
        );

        // Transfer the net amount to the buyer
        require(
            bettingToken.transfer(msg.sender, order.netAmount),
            "Transfer failed"
        );

        // Transfer the platform fee to the designated recipient
        uint256 platformFee = order.fullAmount - order.netAmount;
        require(
            bettingToken.transfer(platformConfig.feeRecipient, platformFee),
            "Transfer failed"
        );

        order.status = OrderStatus.Completed;
        emit OrderCompleted(_orderId, msg.sender);
    }

    function buyerCancelOrder(uint256 _orderId) external {
        Order storage order = orders[_orderId];
        require(order.buyer == msg.sender, "Not the buyer");
        require(order.status == OrderStatus.Open, "Order not open");

        order.status = OrderStatus.Cancelled;
        emit OrderCancelled(_orderId);
    }

    function buyerCompleteOrderByAdmin(uint256 _orderId) external onlyOwner {
        Order storage order = orders[_orderId];
        require(order.orderType == OrderType.Buy, "Not a buy order");
        require(
            order.status == OrderStatus.PaymentConfirmed ||
                order.status == OrderStatus.Paid,
            "Payment not confirmed"
        );

        // Transfer the net amount to the buyer
        require(
            bettingToken.transfer(order.buyer, order.netAmount),
            "Transfer failed"
        );

        // Transfer the platform fee to the designated recipient
        uint256 platformFee = order.fullAmount - order.netAmount;
        require(
            bettingToken.transfer(platformConfig.feeRecipient, platformFee),
            "Transfer failed"
        );

        order.status = OrderStatus.Completed;
        emit OrderCompletedByAdmin(_orderId, order.buyer);
    }

    function buyerCancelOrderByAdmin(uint256 _orderId) external onlyOwner {
        Order storage order = orders[_orderId];

        require(order.orderType == OrderType.Buy, "Not a buy order");

        require(
            order.status == OrderStatus.Open ||
                order.status == OrderStatus.Processing ||
                order.status == OrderStatus.Paid,
            "Order cannot be cancelled"
        );

        if (
            order.status == OrderStatus.Processing ||
            order.status == OrderStatus.Paid
        ) {
            require(
                bettingToken.transfer(order.seller, order.fullAmount),
                "Transfer failed"
            );
        }

        order.status = OrderStatus.Cancelled;
        emit OrderCancelledByAdmin(_orderId);
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
        platformConfig.feeRecipient = _recipient;
        emit PlatformFeeRecipientUpdated(_recipient);
    }

    // Function to update the platform fee percentage
    function setPlatformFeePercentage(uint256 _percentage) external onlyOwner {
        require(_percentage <= 10000, "Fee percentage too high");
        platformConfig.feePercentage = _percentage;
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

        bankDetail[msg.sender] = BankDetails({
            bankName: _bankName,
            accountNumber: _accountNumber,
            note: _note
        });

        emit BankDetailsUpdated(msg.sender, _bankName, _accountNumber, _note);
    }

    // Function to get the details of an order
    function getOrderDetails(uint256 _orderId)
        external
        view
        returns (
            address seller,
            address buyer,
            uint256 fullAmount,
            uint256 netAmount,
            uint256 price,
            string memory status,
            string memory orderType,
            uint256 createdAt,
            uint256 confirmedAt,
            string memory bankName,
            string memory accountNumber,
            string memory note
        )
    {
        Order storage order = orders[_orderId];

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
        } else if (order.status == OrderStatus.Paid) {
            orderStatus = "Paid";
        } else if (order.status == OrderStatus.PaymentConfirmed) {
            orderStatus = "PaymentConfirmed";
        }

        string memory orderTypeStr = order.orderType == OrderType.Buy
            ? "Buy"
            : "Sell";

        // Return the bank details stored in the order
        BankDetails memory bankDetails = order.bankDetail;

        return (
            order.seller,
            order.buyer,
            order.fullAmount,
            order.netAmount,
            order.price,
            orderStatus,
            orderTypeStr,
            order.createdAt,
            order.confirmedAt,
            bankDetails.bankName,
            bankDetails.accountNumber,
            bankDetails.note
        );
    }

    function getOtherOrderDetails(uint256 _orderId)
        external
        view
        returns (
            string memory orderType,
            uint256 createdAt,
            uint256 confirmedAt,
            uint256 paymentAt,
            string memory bankName,
            string memory accountNumber,
            string memory note
        )
    {
        Order storage order = orders[_orderId];

        string memory orderTypeStr = order.orderType == OrderType.Buy
            ? "Buy"
            : "Sell";

        // Return the bank details stored in the order
        BankDetails memory bankDetails = order.bankDetail;

        return (
            orderTypeStr,
            order.createdAt,
            order.confirmedAt,
            order.paymentAt,
            bankDetails.bankName,
            bankDetails.accountNumber,
            bankDetails.note
        );
    }

    // Function to get bank details for a seller
    function getBankDetails(address _seller)
        external
        view
        returns (
            string memory bankName,
            string memory accountNumber,
            string memory note
        )
    {
        BankDetails memory details = bankDetail[_seller];
        return (details.bankName, details.accountNumber, details.note);
    }

    function payment(uint256 _orderId) external {
        Order storage order = orders[_orderId];
        require(order.buyer == msg.sender, "Not the buyer");
        require(order.status == OrderStatus.Processing, "Order not processing");
        require(
            order.orderType == OrderType.Buy ||
                order.orderType == OrderType.Sell,
            "Invalid order type"
        );

        order.paymentAt = block.timestamp;

        // Move the order to the 'Paid' status
        order.status = OrderStatus.Paid;

        emit OrderPaid(_orderId);
    }

    // Function for the seller to confirm receipt of payment
    function paymentConfirm(uint256 _orderId) external {
        Order storage order = orders[_orderId];
        require(order.seller == msg.sender, "Not the seller");
        require(order.orderType == OrderType.Buy, "Not a buy order");
        require(order.status == OrderStatus.Paid, "Order not paid");

        order.status = OrderStatus.PaymentConfirmed;

        emit OrderPaymentConfirmed(_orderId);
    }

    // Function to count the total number of orders created
    function countOrders() external view returns (uint256) {
        return orderIdCounter;
    }

    function getOrdersByTypeAndStatus(
        OrderType _orderType,
        OrderStatus _status,
        string memory _sortBy,
        bool _ascending,
        uint256 _page
    ) external view returns (OrderDetails[] memory) {
        uint256 itemsPerPage = 10;
        uint256 start = (_page - 1) * itemsPerPage;
        uint256 end = start + itemsPerPage;

        // First pass: Collect all matching orders into a temporary array
        OrderDetails[] memory tempResults = new OrderDetails[](orderIdCounter);
        uint256 count = 0;

        for (uint256 i = 0; i < orderIdCounter; i++) {
            if (
                orders[i].orderType == _orderType && orders[i].status == _status
            ) {
                tempResults[count] = OrderDetails({
                    orderId: i,
                    seller: orders[i].seller,
                    buyer: orders[i].buyer,
                    fullAmount: orders[i].fullAmount,
                    netAmount: orders[i].netAmount,
                    price: orders[i].price,
                    status: _orderStatusToString(orders[i].status),
                    orderType: _orderType == OrderType.Buy ? "Buy" : "Sell",
                    createdAt: orders[i].createdAt,
                    confirmedAt: orders[i].confirmedAt,
                    bankName: orders[i].bankDetail.bankName,
                    accountNumber: orders[i].bankDetail.accountNumber,
                    note: orders[i].bankDetail.note
                });
                count++;
            }
        }

        // Resize the array to the actual number of matching orders
        OrderDetails[] memory filteredResults = new OrderDetails[](count);
        for (uint256 j = 0; j < count; j++) {
            filteredResults[j] = tempResults[j];
        }

        // Sort the filtered results
        _sortOrders(filteredResults, _sortBy, _ascending);

        // Adjust the end to ensure it does not exceed the total count
        if (end > count) {
            end = count;
        }

        // Prepare the result array
        OrderDetails[] memory results = new OrderDetails[](end - start);
        for (uint256 k = start; k < end; k++) {
            results[k - start] = filteredResults[k];
        }

        return results;
    }

    function _sortOrders(
        OrderDetails[] memory ordersArray,
        string memory _sortBy,
        bool _ascending
    ) internal pure {
        for (uint256 i = 0; i < ordersArray.length - 1; i++) {
            for (uint256 j = i + 1; j < ordersArray.length; j++) {
                bool swap = false;
                if (
                    keccak256(abi.encodePacked(_sortBy)) ==
                    keccak256(abi.encodePacked("createdAt"))
                ) {
                    if (
                        _ascending
                            ? ordersArray[i].createdAt >
                                ordersArray[j].createdAt
                            : ordersArray[i].createdAt <
                                ordersArray[j].createdAt
                    ) {
                        swap = true;
                    }
                } else if (
                    keccak256(abi.encodePacked(_sortBy)) ==
                    keccak256(abi.encodePacked("price"))
                ) {
                    if (
                        _ascending
                            ? ordersArray[i].price > ordersArray[j].price
                            : ordersArray[i].price < ordersArray[j].price
                    ) {
                        swap = true;
                    }
                }

                if (swap) {
                    OrderDetails memory temp = ordersArray[i];
                    ordersArray[i] = ordersArray[j];
                    ordersArray[j] = temp;
                }
            }
        }
    }

    function _orderStatusToString(OrderStatus status)
        internal
        pure
        returns (string memory)
    {
        if (status == OrderStatus.Open) return "Open";
        if (status == OrderStatus.Processing) return "Processing";
        if (status == OrderStatus.Completed) return "Completed";
        if (status == OrderStatus.Cancelled) return "Cancelled";
        if (status == OrderStatus.RefundRequested) return "RefundRequested";
        if (status == OrderStatus.Paid) return "Paid";
        if (status == OrderStatus.PaymentConfirmed) return "PaymentConfirmed";
        revert("Invalid status");
    }
}
