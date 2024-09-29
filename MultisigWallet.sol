// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function balanceOf(address account) external view returns (uint256);
}

contract MultisigWallet {
    address[] public owners; // List of owners
    mapping(address => bool) public isOwner; // Check if an address is an owner
    uint256 public requiredSignatures; // Number of signatures required to execute a transaction

    struct Transaction {
        address to; // Address to receive funds or tokens
        uint256 value; // Amount of funds or tokens to send
        bool executed; // Transaction status
        uint256 confirmations; // Number of confirmations
        uint256 createdAt; // Creation time of the transaction
        bool isTokenTransaction; // Type of transaction: true for tokens, false for Ether
        address tokenAddress; // Token address in the transaction (if applicable)
        mapping(address => bool) isConfirmed; // Confirmation status of each owner
        uint256 requiredSignatures; // Number of signatures required for this transaction (if applicable)
    }

    Transaction[] public transactions; // List of transactions

    event Deposit(address indexed sender, uint256 amount);
    event SubmitTransaction(address indexed owner, uint256 indexed txIndex);
    event ConfirmTransaction(address indexed owner, uint256 indexed txIndex);
    event ExecuteTransaction(address indexed owner, uint256 indexed txIndex);
    event RevokeConfirmation(address indexed owner, uint256 indexed txIndex);
    event CancelTransaction(address indexed owner, uint256 indexed txIndex);
    event RequiredSignaturesChanged(uint256 newRequiredSignatures); // Event for changing required signatures
    event OwnerAdded(address indexed newOwner); // Event for adding an owner
    event OwnerRemoved(address indexed removedOwner); // Event for removing an owner

    modifier onlyOwner() {
        require(isOwner[msg.sender], "Not an owner");
        _;
    }

    modifier txExists(uint256 _txIndex) {
        require(_txIndex < transactions.length, "Transaction does not exist");
        _;
    }

    modifier notExecuted(uint256 _txIndex) {
        require(
            !transactions[_txIndex].executed,
            "Transaction already executed"
        );
        _;
    }

    modifier notConfirmed(uint256 _txIndex) {
        require(
            !transactions[_txIndex].isConfirmed[msg.sender],
            "Transaction already confirmed"
        );
        _;
    }

    constructor(address[] memory _owners, uint256 _requiredSignatures) {
        require(_owners.length > 0, "Owners required");
        require(
            _requiredSignatures > 0 && _requiredSignatures <= _owners.length,
            "Invalid number of required signatures"
        );

        for (uint256 i = 0; i < _owners.length; i++) {
            address owner = _owners[i];
            require(owner != address(0), "Invalid owner");
            require(!isOwner[owner], "Owner not unique");
            isOwner[owner] = true;
            owners.push(owner);
        }
        requiredSignatures = _requiredSignatures;
    }

    receive() external payable {
        emit Deposit(msg.sender, msg.value);
    }

    // Function to submit a token transaction with the recipient's address (_to)
    function submitTokenTransaction(
        address _to,
        address _tokenAddress,
        uint256 _amount
    ) public onlyOwner {
        require(_to != address(0), "Invalid recipient address");
        require(_amount > 0, "Amount must be greater than 0");

        // Check contract balance for the ERC20 token
        IERC20 token = IERC20(_tokenAddress);
        uint256 contractTokenBalance = token.balanceOf(address(this));
        require(contractTokenBalance >= _amount, "Not enough token balance");

        uint256 txIndex = transactions.length;
        transactions.push();
        Transaction storage newTx = transactions[txIndex];
        newTx.to = _to;
        newTx.value = _amount;
        newTx.executed = false;
        newTx.confirmations = 0;
        newTx.createdAt = block.timestamp;
        newTx.isTokenTransaction = true;
        newTx.tokenAddress = _tokenAddress;

        emit SubmitTransaction(msg.sender, txIndex);
    }

    // Function to submit a transaction to withdraw Ether
    function submitTransaction(address _to, uint256 _amount) public onlyOwner {
        require(_to != address(0), "Invalid recipient address");
        require(_amount > 0, "Amount must be greater than 0");

        // Check the contract balance (native token - Ether)
        require(address(this).balance >= _amount, "Not enough Ether balance");

        uint256 txIndex = transactions.length;
        transactions.push();
        Transaction storage newTx = transactions[txIndex];
        newTx.to = _to;
        newTx.value = _amount;
        newTx.executed = false;
        newTx.confirmations = 0;
        newTx.createdAt = block.timestamp;
        newTx.isTokenTransaction = false;

        emit SubmitTransaction(msg.sender, txIndex);
    }

    function confirmTransaction(uint256 _txIndex)
        public
        onlyOwner
        txExists(_txIndex)
        notExecuted(_txIndex)
        notConfirmed(_txIndex)
    {
        Transaction storage transaction = transactions[_txIndex];
        transaction.isConfirmed[msg.sender] = true;
        transaction.confirmations += 1;

        emit ConfirmTransaction(msg.sender, _txIndex);
    }

    function executeTransaction(uint256 _txIndex)
        public
        onlyOwner
        txExists(_txIndex)
        notExecuted(_txIndex)
    {
        Transaction storage transaction = transactions[_txIndex];
        require(
            transaction.confirmations >= requiredSignatures,
            "Not enough confirmations"
        );

        // Check expiration time (1 day)
        require(
            block.timestamp <= transaction.createdAt + 1 days,
            "Transaction expired"
        );

        transaction.executed = true;

        if (transaction.isTokenTransaction) {
            // If it's a token transaction, call the transfer function to send tokens to _to
            IERC20 token = IERC20(transaction.tokenAddress);
            require(
                token.transfer(transaction.to, transaction.value),
                "Token transfer failed"
            );
        } else {
            // If it's an Ether transaction, send Ether to _to
            (bool success, ) = transaction.to.call{value: transaction.value}(
                ""
            );
            require(success, "Ether transaction failed");
        }

        emit ExecuteTransaction(msg.sender, _txIndex);
    }

    function revokeConfirmation(uint256 _txIndex)
        public
        onlyOwner
        txExists(_txIndex)
        notExecuted(_txIndex)
    {
        Transaction storage transaction = transactions[_txIndex];
        require(
            transaction.isConfirmed[msg.sender],
            "Transaction not confirmed"
        );

        transaction.isConfirmed[msg.sender] = false;
        transaction.confirmations -= 1;

        emit RevokeConfirmation(msg.sender, _txIndex);
    }

    function cancelTransaction(uint256 _txIndex)
        public
        onlyOwner
        txExists(_txIndex)
        notExecuted(_txIndex)
    {
        Transaction storage transaction = transactions[_txIndex];
        require(
            block.timestamp > transaction.createdAt + 1 days,
            "Transaction is still valid"
        );

        // Reset transaction information
        transaction.confirmations = 0; // Or not reset, just do not execute it anymore
        emit CancelTransaction(msg.sender, _txIndex);
    }

    // Function to add a new owner
    function addOwner(address _newOwner) public onlyOwner {
        require(_newOwner != address(0), "Invalid owner address");
        require(!isOwner[_newOwner], "Owner already exists");

        isOwner[_newOwner] = true;
        owners.push(_newOwner);

        emit OwnerAdded(_newOwner);
    }

    // Function to remove an existing owner
    function removeOwner(address _owner) public onlyOwner {
        require(isOwner[_owner], "Not an owner");

        // Ensure at least one owner remains
        require(owners.length > 1, "Cannot remove the last owner");

        isOwner[_owner] = false;

        // Remove the owner from the owners array
        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] == _owner) {
                owners[i] = owners[owners.length - 1];
                owners.pop();
                break;
            }
        }

        emit OwnerRemoved(_owner);
    }

    // Function to submit a change in the required number of signatures
    function submitSetRequiredSignatures(uint256 _newRequiredSignatures)
        public
        onlyOwner
    {
        require(
            _newRequiredSignatures > 0 &&
                _newRequiredSignatures <= owners.length,
            "Invalid number of required signatures"
        );

        uint256 txIndex = transactions.length;
        transactions.push();
        Transaction storage newTx = transactions[txIndex];
        newTx.to = address(this); // This address will be called in execute
        newTx.value = 0; // No need to send Ether
        newTx.executed = false;
        newTx.confirmations = 0;
        newTx.createdAt = block.timestamp;
        newTx.isTokenTransaction = false; // Not a token transaction
        newTx.requiredSignatures = _newRequiredSignatures; // Store the new required signatures

        emit SubmitTransaction(msg.sender, txIndex);
    }

    // Function to execute the change in required signatures
    function executeSetRequiredSignatures(uint256 _txIndex)
        public
        onlyOwner
        txExists(_txIndex)
        notExecuted(_txIndex)
    {
        Transaction storage transaction = transactions[_txIndex];
        require(
            transaction.confirmations >= transaction.requiredSignatures,
            "Not enough confirmations for required signatures change"
        );

        requiredSignatures = transaction.requiredSignatures; // Update the required signatures

        transaction.executed = true;
        emit RequiredSignaturesChanged(requiredSignatures);
    }

    function getOwners() public view returns (address[] memory) {
        return owners;
    }
}
