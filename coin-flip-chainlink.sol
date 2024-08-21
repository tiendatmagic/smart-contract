// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts@1.2.0/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts@1.2.0/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CoinFlipGame is VRFConsumerBaseV2Plus {
    event RequestSent(uint256 requestId, uint32 numWords);
    event RequestFulfilled(uint256 requestId, uint256 result);
    event BetPlaced(
        uint256 requestId,
        address bettor,
        uint256 betAmount,
        uint8 choice,
        address referral
    );
    event HouseFeeUpdated(uint8 newFeePercentage);
    event MaxBetAmountUpdated(uint256 newMaxBetAmount);
    event MinBetAmountUpdated(uint256 newMinBetAmount);
    event ReferralBonusUpdated(uint16 newReferralBonusPercentage);
    event BalanceWithdrawn(address owner, uint256 amount);

    struct Bet {
        address bettor;
        uint256 betAmount;
        uint8 choice;
        address referral;
    }

    struct RequestStatus {
        bool fulfilled;
        uint256 result;
        Bet bet;
    }

    mapping(uint256 => RequestStatus) public s_requests;

    uint256 public s_subscriptionId;
    uint8 public houseFeePercentage; // Fee percentage (0-100)
    uint256 public maxBetAmount;
    uint256 public minBetAmount;
    uint16 public referralBonusPercentage = 0;
    IERC20 public bettingToken;

    bytes32 public keyHash =
        0x8596b430971ac45bdf6088665b9ad8e8630c9d5049ab54b14dff711bee7c0e26;
    uint32 public callbackGasLimit = 300000;
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
        uint256 betAmount,
        uint8 choice,
        address referral
    ) external returns (uint256 requestId) {
        require(
            betAmount >= minBetAmount && betAmount <= maxBetAmount,
            "Bet amount out of range"
        );

        uint256 potentialPayout = betAmount * 2;
        require(
            bettingToken.balanceOf(address(this)) >= potentialPayout,
            "Insufficient contract balance"
        );

        require(
            bettingToken.transferFrom(msg.sender, address(this), betAmount),
            "Token transfer failed"
        );

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
            fulfilled: false,
            bet: Bet({
                bettor: msg.sender,
                betAmount: betAmount,
                choice: choice,
                referral: referral
            })
        });

        emit RequestSent(requestId, numWords);
        emit BetPlaced(requestId, msg.sender, betAmount, choice, referral);
        return requestId;
    }

    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] calldata _randomWords
    ) internal override {
        RequestStatus storage request = s_requests[_requestId];
        require(request.fulfilled == false, "Request already fulfilled");

        request.result = _randomWords[0] % 2; // Map to 0 or 1
        request.fulfilled = true;

        handleBetResult(_requestId, request.result);

        emit RequestFulfilled(_requestId, request.result);
    }

    function handleBetResult(uint256 requestId, uint256 result) internal {
        RequestStatus storage request = s_requests[requestId];
        require(request.fulfilled, "Request not fulfilled");

        Bet memory bet = request.bet;
        uint256 betAmount = bet.betAmount;

        if (bet.choice == result) {
            uint256 fee = (betAmount * houseFeePercentage) / 100;
            uint256 payoutAmount = (betAmount * 2) - fee;

            if (referralBonusPercentage > 0 && bet.referral != address(0)) {
                uint256 referralBonus = (betAmount * referralBonusPercentage) /
                    1000;
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

    function setSubscriptionId(uint256 newSubscriptionId) external onlyOwner {
        s_subscriptionId = newSubscriptionId;
    }

    function setHouseFee(uint8 _feePercentage) external onlyOwner {
        require(_feePercentage <= 100, "Invalid fee percentage");
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
        uint16 _bonusPercentage
    ) external onlyOwner {
        require(_bonusPercentage <= 1000, "Invalid bonus percentage");
        referralBonusPercentage = _bonusPercentage;
        emit ReferralBonusUpdated(_bonusPercentage);
    }

    function setToken(IERC20 _token) external onlyOwner {
        bettingToken = _token;
    }

    function getRequestStatus(
        uint256 _requestId
    ) external view returns (bool fulfilled, uint256 result) {
        RequestStatus memory request = s_requests[_requestId];
        return (request.fulfilled, request.result);
    }

    function withdrawBalance(uint256 amount) external onlyOwner {
        uint256 balance = bettingToken.balanceOf(address(this));
        require(amount > 0 && amount <= balance, "Invalid amount");
        require(bettingToken.transfer(msg.sender, amount), "Withdrawal failed");
        emit BalanceWithdrawn(msg.sender, amount);
    }

    function withdrawToken(
        uint256 amount,
        address tokenAddress
    ) external onlyOwner {
        IERC20 token = IERC20(tokenAddress);
        uint256 balance = token.balanceOf(address(this));
        require(amount > 0 && amount <= balance, "Invalid amount");
        require(token.transfer(msg.sender, amount), "Withdrawal failed");
        emit BalanceWithdrawn(msg.sender, amount);
    }

    function withdrawNative(uint256 amount) external onlyOwner {
        require(
            amount > 0 && amount <= address(this).balance,
            "Invalid amount"
        );
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Withdrawal failed");
    }
}
