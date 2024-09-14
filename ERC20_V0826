// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract USDT_Token is ERC20 {
    uint256 private _totalSupply;
    address private _owner;
    uint8 private _decimals;

    constructor() ERC20("USDT Token", "USDT") {
        _decimals = 6;
        _totalSupply = 1000000 * 10**_decimals;
        address msgSender = _msgSender();
        _owner = msgSender;
        _mint(msg.sender, _totalSupply);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    // // Mint new tokens, only the owner can call this function
    function mint(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "ERC20: mint to the zero address");
        _totalSupply += amount;
        _mint(to, amount);
    }

    // Burn tokens, any holder can call this function to destroy their tokens
    function burn(uint256 amount) external onlyOwner {
        _totalSupply -= amount;
        _burn(msg.sender, amount);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }
}
