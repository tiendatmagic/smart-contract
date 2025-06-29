// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract FlexibleStaking is Ownable, ReentrancyGuard {
    IERC20 public token;
    uint8 public tokenDecimals;

    struct StakeInfo {
        uint256 amount;
        uint256 lastUpdated;
        uint256 rewardDebt;
    }

    struct StakeInfoNative {
        uint256 amount;
        uint256 lastUpdated;
        uint256 rewardDebt;
    }

    mapping(address => StakeInfo) public stakes;
    mapping(address => StakeInfoNative) public stakesNative;

    uint256 public totalStaked;
    uint256 public totalStakedNative;
    uint256 public apr;
    uint256 public nativeApr;

    uint256 public maxStakeERC20;
    uint256 public maxStakeNative;

    uint256 private constant SECONDS_IN_YEAR = 365 * 24 * 60 * 60;
    uint256 private constant MIN_NATIVE_STAKE = 0.0001 ether;

    event Stake(address indexed user, uint256 amount);
    event Unstake(address indexed user, uint256 amount);
    event StakeNative(address indexed user, uint256 amount);
    event UnstakeNative(address indexed user, uint256 amount);
    event Claim(address indexed user, uint256 reward);
    event ClaimNative(address indexed user, uint256 reward);
    event SetAPR(uint256 newAPR);
    event SetNativeAPR(uint256 newAPR);
    event SetToken(address newToken);
    event WithdrawAnyToken(address token, address to, uint256 amount);
    event WithdrawTokenNative(address to, uint256 amount);
    event FundNativeRewardPool(address from, uint256 amount);
    event FundRewardPool(address from, uint256 amount);
    event SetMaxStakeERC20(uint256 amount);
    event SetMaxStakeNative(uint256 amount);

    constructor(
        address _token,
        uint256 _initialAPR,
        uint256 _initialNativeAPR
    ) Ownable(msg.sender) {
        require(_token != address(0), "Invalid token");
        token = IERC20(_token);
        tokenDecimals = IERC20Metadata(_token).decimals();
        apr = _initialAPR;
        nativeApr = _initialNativeAPR;
    }

    receive() external payable {
        emit FundNativeRewardPool(msg.sender, msg.value);
    }

    function stake(uint256 _amount) external nonReentrant {
        require(_amount >= 10**tokenDecimals, "Minimum stake is 1 token");

        StakeInfo storage user = stakes[msg.sender];
        _updateReward(msg.sender);

        require(
            user.amount + _amount <= maxStakeERC20,
            "Exceeds ERC20 stake limit"
        );

        token.transferFrom(msg.sender, address(this), _amount);
        user.amount += _amount;
        totalStaked += _amount;

        emit Stake(msg.sender, _amount);
    }

    function unstake(uint256 _amount) external nonReentrant {
        StakeInfo storage user = stakes[msg.sender];
        require(user.amount > 0, "Nothing to unstake");

        _updateReward(msg.sender);

        uint256 unstakeAmount = _amount == 0 ? user.amount : _amount;
        require(user.amount >= unstakeAmount, "Not enough staked");

        uint256 reward = user.rewardDebt;
        user.amount -= unstakeAmount;
        user.rewardDebt = 0;
        user.lastUpdated = block.timestamp;
        totalStaked -= unstakeAmount;

        token.transfer(msg.sender, unstakeAmount);
        if (reward > 0) token.transfer(msg.sender, reward);

        emit Unstake(msg.sender, unstakeAmount);
        emit Claim(msg.sender, reward);
    }

    function claimReward() external nonReentrant {
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

    function simulateRewardNative(uint256 amount, uint256 durationSeconds)
        external
        view
        returns (uint256)
    {
        return (amount * nativeApr * durationSeconds) / (100 * SECONDS_IN_YEAR);
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

    function stakeNative() external payable nonReentrant {
        require(msg.value >= MIN_NATIVE_STAKE, "Minimum stake is 0.0001 ETH");

        StakeInfoNative storage user = stakesNative[msg.sender];
        _updateRewardNative(msg.sender);

        require(
            user.amount + msg.value <= maxStakeNative,
            "Exceeds native stake limit"
        );

        user.amount += msg.value;
        totalStakedNative += msg.value;

        emit StakeNative(msg.sender, msg.value);
    }

    function unstakeNative(uint256 _amount) external nonReentrant {
        StakeInfoNative storage user = stakesNative[msg.sender];
        require(user.amount > 0, "Nothing to unstake");

        _updateRewardNative(msg.sender);

        uint256 unstakeAmount = _amount == 0 ? user.amount : _amount;
        require(user.amount >= unstakeAmount, "Not enough staked");

        uint256 reward = user.rewardDebt;
        user.amount -= unstakeAmount;
        user.rewardDebt = 0;
        user.lastUpdated = block.timestamp;
        totalStakedNative -= unstakeAmount;

        payable(msg.sender).transfer(unstakeAmount);
        if (reward > 0) payable(msg.sender).transfer(reward);

        emit UnstakeNative(msg.sender, unstakeAmount);
        emit ClaimNative(msg.sender, reward);
    }

    function claimRewardNative() external nonReentrant {
        _updateRewardNative(msg.sender);
        uint256 reward = stakesNative[msg.sender].rewardDebt;
        require(reward > 0, "No reward to claim");

        stakesNative[msg.sender].rewardDebt = 0;
        payable(msg.sender).transfer(reward);

        emit ClaimNative(msg.sender, reward);
    }

    function pendingRewardNative(address userAddr)
        external
        view
        returns (uint256)
    {
        StakeInfoNative memory user = stakesNative[userAddr];
        uint256 reward = user.rewardDebt;

        if (user.amount > 0) {
            uint256 timeDiff = block.timestamp - user.lastUpdated;
            reward +=
                (user.amount * nativeApr * timeDiff) /
                (100 * SECONDS_IN_YEAR);
        }

        return reward;
    }

    function _updateRewardNative(address userAddr) internal {
        StakeInfoNative storage user = stakesNative[userAddr];
        if (user.amount > 0) {
            uint256 timeDiff = block.timestamp - user.lastUpdated;
            uint256 reward = (user.amount * nativeApr * timeDiff) /
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

    function setNativeAPR(uint256 _newAPR) external onlyOwner {
        require(_newAPR <= 1000, "APR too high");
        nativeApr = _newAPR;
        emit SetNativeAPR(_newAPR);
    }

    function setMaxStakeERC20(uint256 _amount) external onlyOwner {
        maxStakeERC20 = _amount;
        emit SetMaxStakeERC20(_amount);
    }

    function setMaxStakeNative(uint256 _amount) external onlyOwner {
        maxStakeNative = _amount;
        emit SetMaxStakeNative(_amount);
    }

    function setTokenAddress(address _newToken) external onlyOwner {
        require(totalStaked == 0, "Cannot change token while staking active");
        require(_newToken != address(0), "Invalid token address");

        token = IERC20(_newToken);
        tokenDecimals = IERC20Metadata(_newToken).decimals();

        emit SetToken(_newToken);
    }

    function fundNativeRewardPool() external payable onlyOwner {
        require(msg.value > 0, "Must send ETH");
        emit FundNativeRewardPool(msg.sender, msg.value);
    }

    function fundRewardPool(uint256 amount) external onlyOwner {
        require(amount > 0, "Amount must be greater than 0");
        token.transferFrom(msg.sender, address(this), amount);
        emit FundRewardPool(msg.sender, amount);
    }

    function withdrawTokenNative(address recipient, uint256 amount)
        external
        onlyOwner
    {
        require(recipient != address(0), "Invalid recipient");

        uint256 balance = address(this).balance;
        if (amount == 0) {
            amount = balance;
        } else {
            require(amount <= balance, "Not enough ETH");
        }

        require(amount > 0, "Nothing to withdraw");

        payable(recipient).transfer(amount);
        emit WithdrawTokenNative(recipient, amount);
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

    function withdrawTokenERC721(
        address nftAddress,
        address recipient,
        uint256 tokenId
    ) external onlyOwner {
        require(nftAddress != address(0), "Invalid NFT address");
        require(recipient != address(0), "Invalid recipient");

        IERC721(nftAddress).safeTransferFrom(address(this), recipient, tokenId);
    }

    function withdrawTokenERC1155(
        address nftAddress,
        address recipient,
        uint256 tokenId,
        uint256 amount,
        bytes calldata data
    ) external onlyOwner {
        require(nftAddress != address(0), "Invalid NFT address");
        require(recipient != address(0), "Invalid recipient");

        IERC1155(nftAddress).safeTransferFrom(
            address(this),
            recipient,
            tokenId,
            amount,
            data
        );
    }

    function renounceOwnership() public view override onlyOwner {
        revert("Disabled");
    }
}
