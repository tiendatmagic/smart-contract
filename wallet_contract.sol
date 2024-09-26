// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract WalletContract is Ownable {
    address public depositAddress;
    uint256 public minAmount;
    uint256 public timeLimit;
    uint256 public lastDepositTime;
    address public withdrawAddress;

    // Updated constructor to accept parameters for depositAddress, minAmount, timeLimit, and withdrawAddress
    constructor(
        address _depositAddress,
        uint256 _minAmount,
        uint256 _timeLimit,
        address _withdrawAddress
    ) Ownable(msg.sender) {
        require(_depositAddress != address(0), "Invalid deposit address");
        require(_withdrawAddress != address(0), "Invalid withdraw address");
        depositAddress = _depositAddress;
        minAmount = _minAmount;
        timeLimit = _timeLimit;
        withdrawAddress = _withdrawAddress;
    }

    receive() external payable {
        lastDepositTime = 0;
    }

    function depositToDepositAddress() external payable onlyOwner {
        require(msg.value >= minAmount, "Minimum deposit amount not met");
        payable(depositAddress).transfer(msg.value);
        lastDepositTime = block.timestamp;
    }

    function setDepositAddress(address _depositAddress) external onlyOwner {
        require(
            depositAddress == address(0) ||
                block.timestamp <= lastDepositTime + timeLimit,
            "Withdrawal time limit exceeded"
        );
        require(_depositAddress != address(0), "Invalid address");
        depositAddress = _depositAddress;
    }

    function setMinAmount(uint256 _minAmount) external onlyOwner {
        require(
            minAmount == 0 || block.timestamp <= lastDepositTime + timeLimit,
            "Withdrawal time limit exceeded"
        );
        minAmount = _minAmount;
    }

    function setTimeLimit(uint256 _timeLimit) external onlyOwner {
        require(
            timeLimit == 0 || block.timestamp <= lastDepositTime + timeLimit,
            "Withdrawal time limit exceeded"
        );
        timeLimit = _timeLimit;
    }

    function setWithdrawAddress(address _withdrawAddress) external onlyOwner {
        require(_withdrawAddress != address(0), "Invalid withdraw address");
        withdrawAddress = _withdrawAddress;
    }

    function withdrawToken(
        address tokenAddress,
        uint256 amount
    ) external onlyOwner {
        require(
            block.timestamp <= lastDepositTime + timeLimit,
            "Withdrawal time limit exceeded"
        );
        require(tokenAddress != address(0), "Invalid token address");
        IERC20 token = IERC20(tokenAddress);
        uint256 balance = token.balanceOf(address(this));
        require(balance >= amount, "Insufficient token balance in contract");
        token.transfer(withdrawAddress, amount);
    }

    function withdrawNativeToken(uint256 amount) external onlyOwner {
        require(
            block.timestamp <= lastDepositTime + timeLimit,
            "Withdrawal time limit exceeded"
        );
        require(
            address(this).balance >= amount,
            "Insufficient ETH balance in contract"
        );
        payable(withdrawAddress).transfer(amount);
    }

    function getTokenBalance(
        address tokenAddress
    ) external view returns (uint256) {
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
