// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CoinUSDT is Ownable {
    IERC20 public token;
    uint256 public houseFeePercentage; // Fee as a percentage (0-100)

    event BetPlaced(address indexed user, uint256 amount, uint256 fee, bool guess, bool outcome, bool won);
    event HouseFeeSet(uint256 newFeePercentage);

    constructor(IERC20 _token, address _initialOwner) Ownable(_initialOwner) {
        token = _token;
    }

    function setHouseFee(uint256 _feePercentage) external onlyOwner {
        require(_feePercentage >= 0 && _feePercentage <= 100, "Fee must be between 0 and 100");
        houseFeePercentage = _feePercentage;
        emit HouseFeeSet(_feePercentage);
    }

    function placeBet(uint256 amount, bool guess) external {
        require(amount > 0, "Bet amount must be greater than 0");

        uint256 walletBalance = token.balanceOf(msg.sender);
        require(walletBalance >= amount, "Insufficient token balance");

        uint256 allowance = token.allowance(msg.sender, address(this));
        require(allowance >= amount, "Check the token allowance");

        // Transfer the bet amount to the contract
        token.transferFrom(msg.sender, address(this), amount);

        // Determine the outcome of the coin flip
        bool outcome = _flipCoin();

        // Determine if the user won or lost
        bool won = (guess == outcome);

        uint256 fee = 0;
        if (won) {
            // Calculate the house fee as a percentage of the bet amount
            fee = (amount * houseFeePercentage) / 100;
            // Transfer the winnings minus the house fee
            token.transfer(msg.sender, amount * 2 - fee);
        }

        emit BetPlaced(msg.sender, amount, fee, guess, outcome, won);
    }

    function _flipCoin() private view returns (bool) {
        // Pseudo-random outcome of the coin flip
        return (block.timestamp + block.difficulty) % 2 == 0;
    }

    function withdrawBalance() external onlyOwner {
        uint256 contractBalance = token.balanceOf(address(this));
        token.transfer(msg.sender, contractBalance);
    }

    function setToken(IERC20 _token) external onlyOwner {
        token = _token;
    }
}
