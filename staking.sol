// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract FlexibleStaking is Ownable {
    IERC20 public token;
    uint8 public tokenDecimals;

    struct StakeInfo {
        uint256 amount;
        uint256 lastUpdated;
        uint256 rewardDebt;
    }

    mapping(address => StakeInfo) public stakes;
    uint256 public totalStaked;
    uint256 public apr;
    uint256 public constant SECONDS_IN_YEAR = 365 * 24 * 60 * 60;

    event Stake(address indexed user, uint256 amount);
    event Unstake(address indexed user, uint256 amount);
    event Claim(address indexed user, uint256 reward);
    event SetAPR(uint256 newAPR);
    event SetToken(address newToken);
    event WithdrawAnyToken(address token, address to, uint256 amount);

    constructor(address _token, uint256 _initialAPR) Ownable(msg.sender) {
        require(_token != address(0), "Invalid token");
        token = IERC20(_token);
        tokenDecimals = IERC20Metadata(_token).decimals();
        apr = _initialAPR;
    }

    function stake(uint256 _amount) external {
        require(_amount >= 10**tokenDecimals, "Minimum stake is 1 token");

        StakeInfo storage user = stakes[msg.sender];
        _updateReward(msg.sender);

        token.transferFrom(msg.sender, address(this), _amount);
        user.amount += _amount;
        totalStaked += _amount;

        emit Stake(msg.sender, _amount);
    }

    function unstake(uint256 _amount) external {
        StakeInfo storage user = stakes[msg.sender];
        require(user.amount > 0, "Nothing to unstake");

        _updateReward(msg.sender);

        uint256 unstakeAmount = _amount;

        if (_amount == 0) {
            unstakeAmount = user.amount;
        } else {
            require(user.amount >= _amount, "Not enough staked");
        }

        uint256 reward = user.rewardDebt;
        user.amount -= unstakeAmount;
        user.rewardDebt = 0;
        user.lastUpdated = block.timestamp;
        totalStaked -= unstakeAmount;

        token.transfer(msg.sender, unstakeAmount);

        if (reward > 0) {
            token.transfer(msg.sender, reward);
        }

        emit Unstake(msg.sender, unstakeAmount);
        emit Claim(msg.sender, reward);
    }

    function claimReward() external {
        _updateReward(msg.sender);

        uint256 reward = stakes[msg.sender].rewardDebt;
        require(reward > 0, "No reward to claim");

        stakes[msg.sender].rewardDebt = 0;
        token.transfer(msg.sender, reward);

        emit Claim(msg.sender, reward);
    }

    function pendingReward(address userAddr) external view returns (uint256) {
        StakeInfo memory user = stakes[userAddr];
        uint256 reward = user.rewardDebt;

        if (user.amount > 0) {
            uint256 timeDiff = block.timestamp - user.lastUpdated;
            reward += (user.amount * apr * timeDiff) / (100 * SECONDS_IN_YEAR);
        }

        return reward;
    }

    function simulateReward(uint256 amount, uint256 durationSeconds)
        external
        view
        returns (uint256)
    {
        return (amount * apr * durationSeconds) / (100 * SECONDS_IN_YEAR);
    }

    function _updateReward(address userAddr) internal {
        StakeInfo storage user = stakes[userAddr];

        if (user.amount > 0) {
            uint256 timeDiff = block.timestamp - user.lastUpdated;
            uint256 reward = (user.amount * apr * timeDiff) /
                (100 * SECONDS_IN_YEAR);
            user.rewardDebt += reward;
        }

        user.lastUpdated = block.timestamp;
    }

    function setAPR(uint256 _newAPR) external onlyOwner {
        require(_newAPR <= 1000, "APR too high");
        apr = _newAPR;
        emit SetAPR(_newAPR);
    }

    function setTokenAddress(address _newToken) external onlyOwner {
        require(totalStaked == 0, "Cannot change token while staking active");
        require(_newToken != address(0), "Invalid token address");

        token = IERC20(_newToken);
        tokenDecimals = IERC20Metadata(_newToken).decimals();

        emit SetToken(_newToken);
    }

    function fundRewardPool(uint256 amount) external onlyOwner {
        token.transferFrom(msg.sender, address(this), amount);
    }

    function withdrawAnyToken(
        address tokenAddress,
        address recipient,
        uint256 amount
    ) external onlyOwner {
        require(tokenAddress != address(0), "Invalid token");
        require(recipient != address(0), "Invalid recipient");

        IERC20 erc20 = IERC20(tokenAddress);
        uint256 balance = erc20.balanceOf(address(this));

        if (amount == 0) {
            amount = balance;
        } else {
            require(amount <= balance, "Not enough balance");
        }

        require(amount > 0, "Nothing to withdraw");

        erc20.transfer(recipient, amount);
        emit WithdrawAnyToken(tokenAddress, recipient, amount);
    }

    function renounceOwnership() public view override onlyOwner {
        revert("Disabled");
    }
}
