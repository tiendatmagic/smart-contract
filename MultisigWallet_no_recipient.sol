// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IERC20 {
    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);

    function balanceOf(address account) external view returns (uint256);
}

contract MultisigWallet is ReentrancyGuard {
    address[] private owners;
    mapping(address => bool) public isOwner;
    uint256 public requiredSignatures;
    struct Transaction {
        address to;
        uint256 value;
        bool executed;
        uint256 confirmations;
        uint256 createdAt;
        bool isTokenTransaction;
        address tokenAddress;
        mapping(address => bool) isConfirmed;
        uint256 requiredSignatures;
    }
    Transaction[] private transactions;
    event Deposit(address indexed sender, uint256 amount);
    event SubmitTransaction(address indexed owner, uint256 indexed txIndex);
    event ConfirmTransaction(address indexed owner, uint256 indexed txIndex);
    event ExecuteTransaction(address indexed owner, uint256 indexed txIndex);
    event RevokeConfirmation(address indexed owner, uint256 indexed txIndex);
    event CancelTransaction(address indexed owner, uint256 indexed txIndex);
    event RequiredSignaturesChanged(uint256 newRequiredSignatures);
    event OwnerAdded(address indexed newOwner);
    event OwnerRemoved(address indexed removedOwner);
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
        require(_owners.length <= 10, "Max 10 owners allowed");
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

    function getNativeTokenBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function getERC20TokenBalance(
        address tokenAddress
    ) public view returns (uint256) {
        require(tokenAddress != address(0), "Invalid token address");
        IERC20 token = IERC20(tokenAddress);
        return token.balanceOf(address(this));
    }

    function submitTokenTransaction(
        address _to,
        address _tokenAddress,
        uint256 _amount
    ) public onlyOwner {
        require(_to != address(0), "Invalid recipient address");
        require(isOwner[_to], "Recipient must be an owner");
        require(_amount > 0, "Amount must be greater than 0");
        require(_to.code.length == 0, "Recipient cannot be a smart contract");
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
        newTx.requiredSignatures = requiredSignatures;
        emit SubmitTransaction(msg.sender, txIndex);
    }

    function submitTransaction(address _to, uint256 _amount) public onlyOwner {
        require(_to != address(0), "Invalid recipient address");
        require(isOwner[_to], "Recipient must be an owner");
        require(_amount > 0, "Amount must be greater than 0");
        require(address(this).balance >= _amount, "Not enough Ether balance");
        require(_to.code.length == 0, "Recipient cannot be a smart contract");
        uint256 txIndex = transactions.length;
        transactions.push();
        Transaction storage newTx = transactions[txIndex];
        newTx.to = _to;
        newTx.value = _amount;
        newTx.executed = false;
        newTx.confirmations = 0;
        newTx.createdAt = block.timestamp;
        newTx.isTokenTransaction = false;
        newTx.requiredSignatures = requiredSignatures;
        emit SubmitTransaction(msg.sender, txIndex);
    }

    function confirmTransaction(
        uint256 _txIndex
    )
        public
        onlyOwner
        txExists(_txIndex)
        notExecuted(_txIndex)
        notConfirmed(_txIndex)
    {
        Transaction storage transaction = transactions[_txIndex];
        require(
            block.timestamp <= transaction.createdAt + 1 days,
            "Transaction expired"
        );
        require(
            transaction.confirmations < requiredSignatures,
            "Transaction already has enough confirmations"
        );
        transaction.isConfirmed[msg.sender] = true;
        transaction.confirmations += 1;
        emit ConfirmTransaction(msg.sender, _txIndex);
    }

    function executeTransaction(
        uint256 _txIndex
    ) public onlyOwner txExists(_txIndex) notExecuted(_txIndex) nonReentrant {
        Transaction storage transaction = transactions[_txIndex];
        require(
            transaction.confirmations >= requiredSignatures,
            "Not enough confirmations"
        );
        require(
            block.timestamp <= transaction.createdAt + 1 days,
            "Transaction expired"
        );
        require(
            transaction.to.code.length == 0,
            "Recipient cannot be a smart contract"
        );
        transaction.executed = true;
        if (transaction.isTokenTransaction) {
            IERC20 token = IERC20(transaction.tokenAddress);
            require(
                token.transfer(transaction.to, transaction.value),
                "Token transfer failed"
            );
        } else {
            require(
                address(this).balance >= transaction.value,
                "Insufficient contract balance"
            );
            (bool success, ) = transaction.to.call{value: transaction.value}(
                ""
            );
            require(success, "Ether transaction to recipient failed");
        }
        emit ExecuteTransaction(msg.sender, _txIndex);
    }

    function revokeConfirmation(
        uint256 _txIndex
    ) public onlyOwner txExists(_txIndex) notExecuted(_txIndex) {
        Transaction storage transaction = transactions[_txIndex];
        require(
            transaction.isConfirmed[msg.sender],
            "Transaction not confirmed"
        );
        transaction.isConfirmed[msg.sender] = false;
        transaction.confirmations -= 1;
        emit RevokeConfirmation(msg.sender, _txIndex);
    }

    function cancelTransaction(
        uint256 _txIndex
    ) public onlyOwner txExists(_txIndex) notExecuted(_txIndex) {
        Transaction storage transaction = transactions[_txIndex];
        require(
            block.timestamp > transaction.createdAt + 1 days,
            "Transaction is still valid"
        );
        transaction.confirmations = 0;
        emit CancelTransaction(msg.sender, _txIndex);
    }

    function submitAddOwner(address _newOwner) public onlyOwner {
        require(_newOwner != address(0), "Invalid owner address");
        require(!isOwner[_newOwner], "Owner already exists");
        require(
            _newOwner.code.length == 0,
            "New owner cannot be a smart contract"
        );
        uint256 txIndex = transactions.length;
        transactions.push();
        Transaction storage newTx = transactions[txIndex];
        newTx.to = _newOwner;
        newTx.value = 0;
        newTx.executed = false;
        newTx.confirmations = 0;
        newTx.createdAt = block.timestamp;
        newTx.isTokenTransaction = false;
        newTx.requiredSignatures = requiredSignatures;
        emit SubmitTransaction(msg.sender, txIndex);
    }

    function confirmAddOwner(
        uint256 _txIndex
    )
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

    function executeAddOwner(
        uint256 _txIndex
    ) public onlyOwner txExists(_txIndex) notExecuted(_txIndex) {
        Transaction storage transaction = transactions[_txIndex];
        require(owners.length < 10, "Max 10 owners allowed");
        require(
            transaction.confirmations >= requiredSignatures,
            "Not enough confirmations"
        );
        require(!isOwner[transaction.to], "Address is already an owner");
        isOwner[transaction.to] = true;
        owners.push(transaction.to);
        transaction.executed = true;
        emit OwnerAdded(transaction.to);
        emit ExecuteTransaction(msg.sender, _txIndex);
    }

    function submitRemoveOwner(address _owner) public onlyOwner {
        require(isOwner[_owner], "Not an owner");
        require(owners.length > 1, "Cannot remove the last owner");
        uint256 txIndex = transactions.length;
        transactions.push();
        Transaction storage newTx = transactions[txIndex];
        newTx.to = _owner;
        newTx.value = 0;
        newTx.executed = false;
        newTx.confirmations = 0;
        newTx.createdAt = block.timestamp;
        newTx.isTokenTransaction = false;
        newTx.requiredSignatures = requiredSignatures;
        emit SubmitTransaction(msg.sender, txIndex);
    }

    function confirmRemoveOwner(
        uint256 _txIndex
    )
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

    function executeRemoveOwner(
        uint256 _txIndex
    ) public onlyOwner txExists(_txIndex) notExecuted(_txIndex) {
        Transaction storage transaction = transactions[_txIndex];
        require(
            transaction.confirmations >= requiredSignatures,
            "Not enough confirmations"
        );
        address ownerToRemove = transaction.to;
        isOwner[ownerToRemove] = false;
        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] == ownerToRemove) {
                owners[i] = owners[owners.length - 1];
                owners.pop();
                break;
            }
        }
        requiredSignatures = requiredSignatures > owners.length
            ? owners.length
            : requiredSignatures;
        transaction.executed = true;
        emit OwnerRemoved(ownerToRemove);
        emit ExecuteTransaction(msg.sender, _txIndex);
    }

    function submitSetRequiredSignatures(
        uint256 _newRequiredSignatures
    ) public onlyOwner {
        require(
            _newRequiredSignatures > 0 &&
                _newRequiredSignatures <= owners.length,
            "Invalid number of required signatures"
        );
        uint256 txIndex = transactions.length;
        transactions.push();
        Transaction storage newTx = transactions[txIndex];
        newTx.to = address(this);
        newTx.value = 0;
        newTx.executed = false;
        newTx.confirmations = 0;
        newTx.createdAt = block.timestamp;
        newTx.isTokenTransaction = false;
        newTx.requiredSignatures = _newRequiredSignatures;
        emit SubmitTransaction(msg.sender, txIndex);
    }

    function confirmSetRequiredSignatures(
        uint256 _txIndex
    )
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

    function executeSetRequiredSignatures(
        uint256 _txIndex
    ) public onlyOwner txExists(_txIndex) notExecuted(_txIndex) {
        Transaction storage transaction = transactions[_txIndex];
        require(
            transactions[_txIndex].requiredSignatures != 0,
            "Invalid Transaction"
        );
        require(
            transactions[_txIndex].requiredSignatures <= owners.length,
            "Invalid required signatures"
        );
        require(
            transaction.confirmations >= requiredSignatures,
            "Not enough confirmations"
        );
        require(
            transaction.requiredSignatures <= owners.length,
            "Invalid required signatures"
        );
        requiredSignatures = transaction.requiredSignatures;
        transaction.executed = true;
        emit RequiredSignaturesChanged(requiredSignatures);
        emit ExecuteTransaction(msg.sender, _txIndex);
    }

    function getTransactionCount() public view returns (uint256) {
        return transactions.length;
    }

    function getTransaction(
        uint256 _txIndex
    )
        public
        view
        returns (
            address to,
            uint256 value,
            bool executed,
            uint256 confirmations,
            uint256 createdAt,
            bool isTokenTransaction,
            address tokenAddress,
            uint256 txRequiredSignatures
        )
    {
        Transaction storage transaction = transactions[_txIndex];
        return (
            transaction.to,
            transaction.value,
            transaction.executed,
            transaction.confirmations,
            transaction.createdAt,
            transaction.isTokenTransaction,
            transaction.tokenAddress,
            transaction.requiredSignatures
        );
    }

    function getOwners() public view returns (address[] memory) {
        return owners;
    }
}
