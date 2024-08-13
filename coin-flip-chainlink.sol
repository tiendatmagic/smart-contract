// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts@1.2.0/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts@1.2.0/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CoinFlipGame is VRFConsumerBaseV2Plus {
    event RequestSent(uint256 requestId, uint32 numWords);
    event RequestFulfilled(uint256 requestId, uint256[] randomWords);
    event CoinFlipResult(uint256 requestId, uint256 result);
    event BetPlaced(
        uint256 requestId,
        address bettor,
        uint256 betAmount,
        uint256 choice,
        address referral
    );
    event HouseFeeUpdated(uint256 newFeePercentage);
    event MaxBetAmountUpdated(uint256 newMaxBetAmount);
    event MinBetAmountUpdated(uint256 newMinBetAmount);
    event ReferralBonusUpdated(uint256 newReferralBonusPercentage);
    event BalanceWithdrawn(address owner, uint256 amount);

    struct Bet {
        address bettor;
        uint256 betAmount;
        uint256 choice;
        address referral;
    }

    struct RequestStatus {
        bool fulfilled;
        bool exists;
        uint256 result;
        Bet bet;
    }
    mapping(uint256 => RequestStatus) public s_requests;

    uint256 public s_subscriptionId;
    uint256[] public requestIds;
    uint256 public lastRequestId;

    uint256 public houseFeePercentage; // Fee percentage (0-100)
    uint256 public maxBetAmount;
    uint256 public minBetAmount;
    uint256 public referralBonusPercentage = 5;
    IERC20 public bettingToken;

    bytes32 public keyHash =
        0x8596b430971ac45bdf6088665b9ad8e8630c9d5049ab54b14dff711bee7c0e26;

    uint32 public callbackGasLimit = 250000;
    uint16 public requestConfirmations = 3;
    uint32 public numWords = 1; // Only need one word

    constructor(
        uint256 subscriptionId,
        address tokenAddress
    ) VRFConsumerBaseV2Plus(0xDA3b641D438362C440Ac5458c57e00a712b66700) {
        s_subscriptionId = subscriptionId;
        bettingToken = IERC20(tokenAddress);
    }

    function placeBet(
        uint256 betAmount, // Amount of the bet
        uint256 choice, // Choice of 0 or 1
        address referral // Referral address
    ) external returns (uint256 requestId) {
        require(
            betAmount >= minBetAmount,
            "Bet amount must be greater than or equal to the minimum bet amount"
        );
        require(choice == 0 || choice == 1, "Choice must be 0 or 1");
        require(
            betAmount <= maxBetAmount,
            "Bet amount exceeds the maximum limit"
        );

        uint256 potentialPayout = (betAmount * 2);
        require(
            bettingToken.balanceOf(address(this)) >= potentialPayout,
            "Contract balance is too low to cover the bet"
        );

        // Transfer tokens from the bettor to the contract
        require(
            bettingToken.transferFrom(msg.sender, address(this), betAmount),
            "Token transfer failed"
        );

        // Request random words from Chainlink VRF
        requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: keyHash,
                subId: s_subscriptionId,
                requestConfirmations: requestConfirmations,
                callbackGasLimit: callbackGasLimit,
                numWords: numWords,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            })
        );
        s_requests[requestId] = RequestStatus({
            result: 0,
            exists: true,
            fulfilled: false,
            bet: Bet({
                bettor: msg.sender,
                betAmount: betAmount,
                choice: choice,
                referral: referral
            })
        });
        requestIds.push(requestId);
        lastRequestId = requestId;
        emit RequestSent(requestId, numWords);
        emit BetPlaced(requestId, msg.sender, betAmount, choice, referral);
        return requestId;
    }

    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] calldata _randomWords
    ) internal override {
        require(s_requests[_requestId].exists, "request not found");

        // Determine the result
        uint256 result = _randomWords[0] % 2; // Map to 0 or 1
        s_requests[_requestId].fulfilled = true;
        s_requests[_requestId].result = result;

        // Handle bet result
        handleBetResult(_requestId, result);

        emit RequestFulfilled(_requestId, _randomWords);
        emit CoinFlipResult(_requestId, result);
    }

    function handleBetResult(uint256 requestId, uint256 result) internal {
        RequestStatus storage request = s_requests[requestId];
        require(request.fulfilled, "Request not fulfilled");

        Bet memory bet = request.bet;
        uint256 betAmount = bet.betAmount;

        if (bet.choice == result) {
            // Player wins
            uint256 fee = (betAmount * houseFeePercentage) / 100;
            uint256 payoutAmount = (betAmount * 2) - fee;

            // If there is a valid referral address, give extra to both
            if (bet.referral != address(0)) {
                uint256 referralBonus = (betAmount * referralBonusPercentage) /
                    1000; // Adjustable percentage
                payoutAmount += referralBonus;
                require(
                    bettingToken.transfer(bet.referral, referralBonus),
                    "Referral bonus transfer failed"
                );
            }

            require(
                bettingToken.transfer(bet.bettor, payoutAmount),
                "Token transfer failed"
            );
        }
    }

    function setHouseFee(uint256 _feePercentage) external onlyOwner {
        require(
            _feePercentage >= 0 && _feePercentage <= 100,
            "Invalid fee percentage"
        );
        houseFeePercentage = _feePercentage;
        emit HouseFeeUpdated(_feePercentage);
    }

    function setMaxBetAmount(uint256 _maxBetAmount) external onlyOwner {
        require(_maxBetAmount > 0, "Max bet amount must be greater than 0");
        maxBetAmount = _maxBetAmount;
        emit MaxBetAmountUpdated(_maxBetAmount);
    }

    function setMinBetAmount(uint256 _minBetAmount) external onlyOwner {
        require(_minBetAmount > 0, "Minimum bet amount must be greater than 0");
        minBetAmount = _minBetAmount;
        emit MinBetAmountUpdated(_minBetAmount);
    }

    function setReferralBonusPercentage(
        uint256 _bonusPercentage
    ) external onlyOwner {
        require(
            _bonusPercentage >= 0 && _bonusPercentage <= 100,
            "Invalid bonus percentage"
        );
        referralBonusPercentage = _bonusPercentage;
        emit ReferralBonusUpdated(_bonusPercentage);
    }

    function setToken(IERC20 _token) external onlyOwner {
        bettingToken = _token;
    }

    function getRequestStatus(
        uint256 _requestId
    ) external view returns (bool fulfilled, uint256 result) {
        require(s_requests[_requestId].exists, "request not found");
        RequestStatus memory request = s_requests[_requestId];
        return (request.fulfilled, request.result);
    }

    // Function to withdraw balance
    function withdrawBalance(uint256 amount) external onlyOwner {
        uint256 balance = bettingToken.balanceOf(address(this));
        require(amount > 0, "Amount must be greater than 0");
        require(amount <= balance, "Insufficient balance in the contract");

        require(bettingToken.transfer(msg.sender, amount), "Withdrawal failed");
        emit BalanceWithdrawn(msg.sender, amount);
    }
}
