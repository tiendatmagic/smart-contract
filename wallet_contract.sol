// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract WalletContract is Ownable {
    address public depositAddress;
    uint256 public depositMinAmount;
    uint256 public depositTimeLimit;
    uint256 public lastDepositTime;
    address public withdrawAddress;
    uint256 public withdrawMinAmount;
    uint256 public withdrawTimeLimit;
    uint256 public withdrawLastDepositTime;

    constructor(
        address _depositAddress,
        uint256 _depositMinAmount,
        uint256 _depositTimeLimit,
        address _withdrawAddress,
        uint256 _withdrawMinAmount,
        uint256 _withdrawTimeLimit
    ) Ownable(msg.sender) {
        require(_depositAddress != address(0), "Invalid deposit address");
        require(_withdrawAddress != address(0), "Invalid withdraw address");
        depositAddress = _depositAddress;
        depositMinAmount = _depositMinAmount;
        depositTimeLimit = _depositTimeLimit;
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
        require(msg.value >= depositMinAmount, "Minimum deposit amount not met");
        payable(depositAddress).transfer(msg.value);
    }

    function setDepositAddress(address _depositAddress) external onlyOwner {
        require(block.timestamp <= lastDepositTime + depositTimeLimit, "Deposit time limit exceeded");
        require(address(this).balance >= withdrawMinAmount && block.timestamp <= withdrawLastDepositTime + withdrawTimeLimit, "Deposit time limit exceeded");
        require(_depositAddress != address(0), "Invalid deposit address");
        depositAddress = _depositAddress;
    }

    function setDepositMinAmount(uint256 _depositMinAmount) external onlyOwner {
        require(block.timestamp <= lastDepositTime + depositTimeLimit, "Deposit time limit exceeded");
        require(address(this).balance >= withdrawMinAmount && block.timestamp <= withdrawLastDepositTime + withdrawTimeLimit, "Deposit time limit exceeded");
        require(_depositMinAmount <= 500000000000000000, "Deposit amount must not exceed 0.5 of the native token");
        depositMinAmount = _depositMinAmount;
    }

    function setDepositTimeLimit(uint256 _depositTimeLimit) external onlyOwner {
        require(block.timestamp <= lastDepositTime + depositTimeLimit, "Deposit time limit exceeded");
        require(address(this).balance >= withdrawMinAmount && block.timestamp <= withdrawLastDepositTime + withdrawTimeLimit, "Deposit time limit exceeded");
        require(_depositTimeLimit >= 60, "Minimum time limit must be at least 60 seconds");
        depositTimeLimit = _depositTimeLimit;
    }

    function setWithdrawAddress(address _withdrawAddress) external onlyOwner {
        require(block.timestamp <= lastDepositTime + depositTimeLimit, "Withdraw address did not meet conditions");
        require(address(this).balance >= withdrawMinAmount && block.timestamp <= withdrawLastDepositTime + withdrawTimeLimit, "Withdraw address did not meet conditions");
        require(_withdrawAddress != address(0), "Invalid withdraw address");
        withdrawAddress = _withdrawAddress;
    }

    function setWithdrawConditions(
        uint256 _withdrawMinAmount,
        uint256 _withdrawTimeLimit
    ) external onlyOwner {
        require(block.timestamp <= lastDepositTime + depositTimeLimit, "Withdraw address did not meet conditions");
        require(address(this).balance >= withdrawMinAmount && block.timestamp <= withdrawLastDepositTime + withdrawTimeLimit, "Withdraw address did not meet conditions");
        require(_withdrawMinAmount <= 500000000000000000, "Withdraw amount must not exceed 0.5 of the native token");
        require(_withdrawTimeLimit >= 60, "Minimum time limit must be at least 60 seconds");
        withdrawMinAmount = _withdrawMinAmount;
        withdrawTimeLimit = _withdrawTimeLimit;
    }

    function withdrawToken(address tokenAddress, uint256 amount) external onlyOwner {
        require(block.timestamp <= lastDepositTime + depositTimeLimit, "Withdrawal time limit exceeded");
        require(address(this).balance >= withdrawMinAmount && block.timestamp <= withdrawLastDepositTime + withdrawTimeLimit, "Withdrawal time limit exceeded");
        require(tokenAddress != address(0), "Invalid token address");
        IERC20 token = IERC20(tokenAddress);
        uint256 balance = token.balanceOf(address(this));
        require(balance >= amount, "Insufficient token balance");
        token.transfer(withdrawAddress, amount);
    }

    function withdrawNativeToken(uint256 amount) external onlyOwner {
        require(block.timestamp <= lastDepositTime + depositTimeLimit, "Withdrawal time limit exceeded");
        require(address(this).balance >= withdrawMinAmount && block.timestamp <= withdrawLastDepositTime + withdrawTimeLimit, "Withdrawal time limit exceeded");
        require(address(this).balance >= amount, "Insufficient native token balance");
        payable(withdrawAddress).transfer(amount);
    }

    function getTokenBalance(address tokenAddress) external view returns (uint256) {
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
