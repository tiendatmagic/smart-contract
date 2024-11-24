// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IERC20 {
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract BitcoinButtonGame {
    address public owner;
    uint256 public gameEndTime;
    address public winner;
    uint256 public rewardAmount;
    uint256 public pressFee;
    bool public gameStarted;
    uint256 public currentGameId;
    mapping(uint256 => address[]) public gamePlayers;
    mapping(uint256 => mapping(address => uint256)) public lastPressTime;
    mapping(uint256 => mapping(address => bool)) public isTimeFrozen;

    event GameStarted(uint256 endTime, uint256 gameId);
    event ButtonPressed(address indexed player, uint256 resetTime, uint256 fee, uint256 gameId);
    event GameEnded(address indexed winner, uint256 reward, uint256 gameId);
    event Withdraw(address indexed recipient, uint256 amount);
    event ERC20Withdraw(address indexed recipient, address indexed token, uint256 amount);

    constructor(uint256 _rewardAmount, uint256 _pressFee) {
        owner = msg.sender;
        rewardAmount = _rewardAmount;
        pressFee = _pressFee;
        currentGameId = 0;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    modifier onlyDuringGame() {
        require(gameStarted, "Game has not started");
        require(block.timestamp < gameEndTime, "Game has already ended");
        _;
    }

    function startGame() external onlyOwner {
        require(!gameStarted, "Game is already started");
        gameStarted = true;
        gameEndTime = block.timestamp + 60;
        winner = address(0);
        currentGameId++;
        delete gamePlayers[currentGameId];
        emit GameStarted(gameEndTime, currentGameId);
    }

    function pressButton() external payable onlyDuringGame {
        require(msg.value >= pressFee, "Incorrect press fee");

        gamePlayers[currentGameId].push(msg.sender);
        lastPressTime[currentGameId][msg.sender] = block.timestamp;

        for (uint256 i = 0; i < gamePlayers[currentGameId].length - 1; i++) {
            address previousPlayer = gamePlayers[currentGameId][i];
            isTimeFrozen[currentGameId][previousPlayer] = true;
        }

        uint256 fixedRemainingTime = 60;

        emit ButtonPressed(msg.sender, block.timestamp + fixedRemainingTime, msg.value, currentGameId);
    }

    function claimReward() external {
        require(gameStarted, "Game has not started");
        require(block.timestamp >= gameEndTime, "Game is still ongoing");
        require(gamePlayers[currentGameId].length > 0, "No player participated");

        address lastPlayer = gamePlayers[currentGameId][0];
        uint256 closestTime = block.timestamp - gameEndTime;

        for (uint256 i = 1; i < gamePlayers[currentGameId].length; i++) {
            uint256 playerPressTime = lastPressTime[currentGameId][gamePlayers[currentGameId][i]];
            if (playerPressTime < closestTime) {
                lastPlayer = gamePlayers[currentGameId][i];
                closestTime = playerPressTime;
            }
        }

        require(msg.sender == lastPlayer, "Only the winner can claim the reward");

        gameStarted = false;
        payable(lastPlayer).transfer(rewardAmount);
        emit GameEnded(lastPlayer, rewardAmount, currentGameId);
    }

    function setRewardAmount(uint256 _rewardAmount) external onlyOwner {
        rewardAmount = _rewardAmount;
    }

    function setPressFee(uint256 _pressFee) external onlyOwner {
        pressFee = _pressFee;
    }

    function withdrawNativeToken(uint256 amount) external onlyOwner {
        require(address(this).balance >= amount, "Insufficient balance");
        payable(owner).transfer(amount);
        emit Withdraw(owner, amount);
    }

    function withdrawERC20(address token, uint256 amount) external onlyOwner {
        IERC20 erc20 = IERC20(token);
        require(erc20.balanceOf(address(this)) >= amount, "Insufficient token balance");
        erc20.transfer(owner, amount);
        emit ERC20Withdraw(owner, token, amount);
    }

    function resetGame() external onlyOwner {
        require(block.timestamp >= gameEndTime, "Game is still ongoing");
        gameStarted = false;
    }

    function readTime() external view returns (uint256 remainingTime) {
        if (!gameStarted || block.timestamp >= gameEndTime) {
            return 0;
        }
        return gameEndTime - block.timestamp;
    }

    receive() external payable {}

    fallback() external payable {}

    function readPlayerTime(address player, uint256 _gameId) external view returns (uint256 remainingTime) {
        require(gamePlayers[_gameId].length > 0, "No players in this game");
        uint256 playerPressTime = lastPressTime[_gameId][player];
        require(playerPressTime > 0, "Player has not pressed the button");

        if (block.timestamp >= gameEndTime || isTimeFrozen[_gameId][player]) {
            return 0;
        }

        uint256 elapsedTime = block.timestamp - playerPressTime;
        if (elapsedTime >= 60) {
            return 0;
        }

        return 60 - elapsedTime;
    }
}
