// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract WalletContract is Ownable {
    address public depositAddress;
    uint256 public depositMinAmount;
    uint256 public timeLimit;
    uint256 public lastDepositTime;
    address public withdrawAddress;
    uint256 public withdrawMinAmount;
    uint256 public withdrawTimeLimit;
    uint256 public withdrawLastDepositTime;

    constructor(
        address _depositAddress,
        uint256 _depositMinAmount,
        uint256 _timeLimit,
        address _withdrawAddress,
        uint256 _withdrawMinAmount,
        uint256 _withdrawTimeLimit
    ) Ownable(msg.sender) {
        require(_depositAddress != address(0), "Invalid deposit address");
        require(_withdrawAddress != address(0), "Invalid withdraw address");
        depositAddress = _depositAddress;
        depositMinAmount = _depositMinAmount;
        timeLimit = _timeLimit;
        withdrawAddress = _withdrawAddress;
        withdrawMinAmount = _withdrawMinAmount;
        withdrawTimeLimit = _withdrawTimeLimit;
    }

    receive() external payable {
        if (msg.sender == withdrawAddress) {
            withdrawLastDepositTime = block.timestamp;
        } else {
            lastDepositTime = 0;
            withdrawLastDepositTime = 0;
        }
    }

    function depositToDepositAddress() external payable onlyOwner {
        require(
            msg.value >= depositMinAmount,
            "Minimum deposit amount not met"
        );
        payable(depositAddress).transfer(msg.value);
        lastDepositTime = block.timestamp;
    }

    function setDepositAddress(address _depositAddress) external onlyOwner {
        require(
            depositAddress == address(0) ||
                block.timestamp <= lastDepositTime + timeLimit,
            "Deposit time limit exceeded"
        );
        require(_depositAddress != address(0), "Invalid deposit address");
        depositAddress = _depositAddress;
    }

    function setDepositMinAmount(uint256 _depositMinAmount) external onlyOwner {
        require(_depositMinAmount >= 60, "Minimum amount must be at least 60");
        require(
            depositMinAmount == 0 ||
                block.timestamp <= lastDepositTime + timeLimit,
            "Deposit time limit exceeded"
        );
        depositMinAmount = _depositMinAmount;
    }

    function setTimeLimit(uint256 _timeLimit) external onlyOwner {
        require(
            timeLimit == 0 || block.timestamp <= lastDepositTime + timeLimit,
            "Deposit time limit exceeded"
        );
        timeLimit = _timeLimit;
    }

    function setWithdrawAddress(address _withdrawAddress) external onlyOwner {
        require(_withdrawAddress != address(0), "Invalid withdraw address");
        require(
            address(this).balance >= withdrawMinAmount &&
                block.timestamp <= withdrawLastDepositTime + withdrawTimeLimit,
            "Withdraw address did not meet conditions"
        );
        withdrawAddress = _withdrawAddress;
    }

    function setWithdrawConditions(
        uint256 _withdrawMinAmount,
        uint256 _withdrawTimeLimit
    ) external onlyOwner {
        require(_withdrawMinAmount >= 60, "Minimum amount must be at least 60");
        require(
            address(this).balance >= _withdrawMinAmount &&
                block.timestamp <= withdrawLastDepositTime + _withdrawTimeLimit,
            "Withdraw address did not meet conditions"
        );
        withdrawMinAmount = _withdrawMinAmount;
        withdrawTimeLimit = _withdrawTimeLimit;
    }

    function withdrawToken(address tokenAddress, uint256 amount)
        external
        onlyOwner
    {
        require(
            block.timestamp <= lastDepositTime + timeLimit,
            "Withdrawal time limit exceeded"
        );

        require(
            address(this).balance >= withdrawMinAmount &&
                block.timestamp <= withdrawLastDepositTime + withdrawTimeLimit,
            "Withdraw address did not meet conditions"
        );

        require(tokenAddress != address(0), "Invalid token address");
        IERC20 token = IERC20(tokenAddress);
        uint256 balance = token.balanceOf(address(this));
        require(balance >= amount, "Insufficient token balance");
        token.transfer(withdrawAddress, amount);
    }

    function withdrawNativeToken(uint256 amount) external onlyOwner {
        require(
            block.timestamp <= lastDepositTime + timeLimit,
            "Withdrawal time limit exceeded"
        );

        require(
            address(this).balance >= withdrawMinAmount &&
                block.timestamp <= withdrawLastDepositTime + withdrawTimeLimit,
            "Withdraw address did not meet conditions"
        );

        require(address(this).balance >= amount, "Insufficient ETH balance");
        payable(withdrawAddress).transfer(amount);
    }

    function getTokenBalance(address tokenAddress)
        external
        view
        returns (uint256)
    {
        require(tokenAddress != address(0), "Invalid token address");
        return IERC20(tokenAddress).balanceOf(address(this));
    }

    function getNativeTokenBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function renounceOwnership() public virtual override onlyOwner {
        revert("Ownership renouncement is disabled");
    }
}
