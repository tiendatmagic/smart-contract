// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CoinFlip is VRFConsumerBase {
    bytes32 internal keyHash;
    uint256 internal fee;
    address public owner;
    uint256 public houseFee;
    IERC20 public token;

    mapping(bytes32 => address) public requestToSender;
    mapping(bytes32 => uint256) public requestToBetAmount;
    mapping(bytes32 => bool) public requestToGuess;

    event CoinFlipped(address indexed player, uint256 betAmount, bool guess);
    event BetResult(address indexed player, uint256 betAmount, bool result);

    constructor(address _vrfCoordinator, address _linkToken, bytes32 _keyHash, uint256 _fee, address _token) 
        VRFConsumerBase(_vrfCoordinator, _linkToken) 
    {
        keyHash = _keyHash;
        fee = _fee; // Fee in LINK token
        owner = msg.sender;
        token = IERC20(_token);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the owner");
        _;
    }

    function setHouseFee(uint256 _fee) external onlyOwner {
        require(_fee >= 0 && _fee <= 100, "Invalid fee");
        houseFee = _fee;
    }

    function setToken(address _token) external onlyOwner {
        token = IERC20(_token);
    }

    function placeBet(uint256 _betAmount, bool _guess) external {
        require(token.balanceOf(msg.sender) >= _betAmount, "Insufficient balance");
        require(token.allowance(msg.sender, address(this)) >= _betAmount, "Token allowance too low");
        require(LINK.balanceOf(address(this)) >= fee, "Not enough LINK");

        token.transferFrom(msg.sender, address(this), _betAmount);

        bytes32 requestId = requestRandomness(keyHash, fee);

        requestToSender[requestId] = msg.sender;
        requestToBetAmount[requestId] = _betAmount;
        requestToGuess[requestId] = _guess;

        emit CoinFlipped(msg.sender, _betAmount, _guess);
    }

    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        address player = requestToSender[requestId];
        uint256 betAmount = requestToBetAmount[requestId];
        bool guess = requestToGuess[requestId];

        bool result = (randomness % 2 == 0);
        if (result == guess) {
            uint256 winAmount = betAmount * (100 - houseFee) / 100;
            token.transfer(player, winAmount);
        }
        emit BetResult(player, betAmount, result);
    }

    function withdrawBalance() external onlyOwner {
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, "No balance to withdraw");
        token.transfer(owner, balance);
    }

    function withdrawLINK() external onlyOwner {
        uint256 linkBalance = LINK.balanceOf(address(this));
        require(linkBalance > 0, "No LINK balance to withdraw");
        LINK.transfer(owner, linkBalance);
    }

    function fundContractWithLINK(uint256 amount) external onlyOwner {
        LINK.transferFrom(msg.sender, address(this), amount);
    }
}
