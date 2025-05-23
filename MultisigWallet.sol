// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IERC20 {
    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);

    function balanceOf(address account) external view returns (uint256);
}

interface IERC721 {
    function ownerOf(uint256 tokenId) external view returns (address);

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;
}

interface IERC1155 {
    function balanceOf(
        address account,
        uint256 id
    ) external view returns (uint256);

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes calldata data
    ) external;
}

contract MultisigWallet is ReentrancyGuard {
    address[] private owners;
    mapping(address => bool) public isOwner;
    mapping(uint256 => uint256) private cancelVotes;
    mapping(uint256 => mapping(address => bool)) private hasVotedCancel;
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
    event NativeTokenSent(address indexed recipient, uint256 amount);
    event WithdrawERC721(
        address indexed owner,
        address indexed to,
        address indexed tokenAddress,
        uint256 tokenId
    );
    event WithdrawERC1155(
        address indexed owner,
        address indexed to,
        address indexed tokenAddress,
        uint256 tokenId,
        uint256 amount
    );
    uint256 public nativeTokenAmount;
    address public recipientWallet;
    modifier onlyOwner() {
        require(isOwner[msg.sender], "Not an owner");
        _;
    }
    modifier validRecipientWallet() {
        require(
            recipientWallet != address(0) && isOwner[recipientWallet],
            "Recipient wallet must be a valid owner"
        );
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

    constructor(
        address[] memory _owners,
        uint256 _requiredSignatures,
        address _recipientWallet,
        uint256 _nativeTokenAmount
    ) {
        require(_owners.length > 0, "Owners required");
        require(_owners.length <= 10, "Max 10 owners allowed");
        require(
            _requiredSignatures > 0 && _requiredSignatures <= _owners.length,
            "Invalid number of required signatures"
        );
        require(_nativeTokenAmount <= 100000000000000000, "Amount exceeds 0.1");
        bool isValidRecipient = false;
        for (uint256 i = 0; i < _owners.length; i++) {
            if (_owners[i] == _recipientWallet) {
                isValidRecipient = true;
                break;
            }
        }
        require(isValidRecipient, "Recipient wallet must be an owner");
        for (uint256 i = 0; i < _owners.length; i++) {
            address owner = _owners[i];
            require(owner != address(0), "Invalid owner");
            require(!isOwner[owner], "Owner not unique");
            isOwner[owner] = true;
            owners.push(owner);
        }
        recipientWallet = _recipientWallet;
        nativeTokenAmount = _nativeTokenAmount;
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
    ) public onlyOwner validRecipientWallet {
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

    function submitTransaction(
        address _to,
        uint256 _amount
    ) public onlyOwner validRecipientWallet {
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
    )
        public
        payable
        onlyOwner
        txExists(_txIndex)
        notExecuted(_txIndex)
        nonReentrant
        validRecipientWallet
    {
        require(
            msg.value >= nativeTokenAmount,
            "msg.value must be greater than or equal to nativeTokenAmount"
        );
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
        if (recipientWallet != address(0)) {
            (bool success, ) = recipientWallet.call{value: msg.value}("");
            require(success, "Transfer of msg.value to recipient failed");
            emit NativeTokenSent(recipientWallet, msg.value);
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
            transaction.confirmations < requiredSignatures,
            "Cannot cancel fully confirmed tx"
        );
        require(
            cancelVotes[_txIndex] < requiredSignatures,
            "Already enough votes to cancel"
        );
        require(
            !hasVotedCancel[_txIndex][msg.sender],
            "Already voted to cancel"
        );
        hasVotedCancel[_txIndex][msg.sender] = true;
        cancelVotes[_txIndex] += 1;
        if (cancelVotes[_txIndex] >= requiredSignatures) {
            for (uint256 i = 0; i < owners.length; i++) {
                transaction.isConfirmed[owners[i]] = false;
            }
            transaction.confirmations = 0;
            cancelVotes[_txIndex] = 0;
        }
        emit CancelTransaction(msg.sender, _txIndex);
    }

    function submitAddOwner(address _newOwner) public onlyOwner {
        require(_newOwner != address(0), "Invalid owner address");
        require(!isOwner[_newOwner], "Owner already exists");
        require(
            _newOwner.code.length == 0,
            "New owner cannot be a smart contract"
        );
        require(owners.length < 10, "Max 10 owners allowed");
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
        require(
            block.timestamp <= transaction.createdAt + 1 days,
            "Transaction expired"
        );
        require(owners.length < 10, "Max 10 owners allowed");
        require(
            transaction.confirmations >= requiredSignatures,
            "Not enough confirmations"
        );
        require(!isOwner[transaction.to], "Address is already an owner");
        require(
            transaction.to.code.length == 0,
            "New owner cannot be a smart contract"
        );
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
            block.timestamp <= transaction.createdAt + 1 days,
            "Transaction expired"
        );
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
            block.timestamp <= transaction.createdAt + 1 days,
            "Transaction expired"
        );
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

    function setNativeTokenAmount(uint256 _amount) public onlyOwner {
        require(_amount <= 100000000000000000, "Amount exceeds 0.1");
        nativeTokenAmount = _amount;
    }

    function setRecipientWallet(address _recipient) public onlyOwner {
        require(_recipient != address(0), "Invalid recipient address");
        require(isOwner[_recipient], "Recipient must be an owner");
        require(
            _recipient.code.length == 0,
            "Recipient cannot be a smart contract"
        );
        recipientWallet = _recipient;
    }

    function withdrawTokenERC721(
        address _to,
        address _tokenAddress,
        uint256 _tokenId
    ) public onlyOwner nonReentrant {
        require(_to != address(0), "Invalid recipient address");
        require(isOwner[_to], "Recipient must be an owner");
        require(_to.code.length == 0, "Recipient cannot be a smart contract");
        require(_tokenAddress != address(0), "Invalid token address");

        IERC721 token = IERC721(_tokenAddress);
        require(
            token.ownerOf(_tokenId) == address(this),
            "Contract does not own this token"
        );

        token.safeTransferFrom(address(this), _to, _tokenId);
        emit WithdrawERC721(msg.sender, _to, _tokenAddress, _tokenId);
    }

    function withdrawTokenERC1155(
        address _to,
        address _tokenAddress,
        uint256 _tokenId,
        uint256 _amount
    ) public onlyOwner nonReentrant {
        require(_to != address(0), "Invalid recipient address");
        require(isOwner[_to], "Recipient must be an owner");
        require(_to.code.length == 0, "Recipient cannot be a smart contract");
        require(_tokenAddress != address(0), "Invalid token address");
        require(_amount > 0, "Amount must be greater than 0");

        IERC1155 token = IERC1155(_tokenAddress);
        require(
            token.balanceOf(address(this), _tokenId) >= _amount,
            "Insufficient token balance"
        );

        token.safeTransferFrom(address(this), _to, _tokenId, _amount, "");
        emit WithdrawERC1155(msg.sender, _to, _tokenAddress, _tokenId, _amount);
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
