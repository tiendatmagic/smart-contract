// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts@1.2.0/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts@1.2.0/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CoinFlipConsumer is VRFConsumerBaseV2Plus {
    event RequestSent(uint256 requestId, uint32 numWords);
    event RequestFulfilled(uint256 requestId, uint256[] randomWords);
    event CoinFlipResult(uint256 requestId, uint256 result);
    event BetPlaced(address indexed bettor, uint256 amount, bool guess);
    event Withdraw(address indexed to, uint256 amount);

    struct RequestStatus {
        bool fulfilled;
        bool exists;
        uint256 result; // Storing the result (0 or 1)
        address bettor;
        uint256 amount;
        bool guess;
    }
    mapping(uint256 => RequestStatus) public s_requests;

    uint256 public s_subscriptionId;
    uint256[] public requestIds;
    uint256 public lastRequestId;
    uint256 public houseFeePercentage; // 0% - 100%
    IERC20 public bettingToken;

    bytes32 public keyHash =
        0x8596b430971ac45bdf6088665b9ad8e8630c9d5049ab54b14dff711bee7c0e26;

    uint32 public callbackGasLimit = 250000;
    uint16 public requestConfirmations = 3;
    uint32 public numWords = 1; // Only need one word

    constructor(
        uint256 subscriptionId,
        IERC20 initialToken
    ) VRFConsumerBaseV2Plus(0xDA3b641D438362C440Ac5458c57e00a712b66700) {
        s_subscriptionId = subscriptionId;
        bettingToken = initialToken;
    }

    function placeBet(
        uint256 amount,
        bool guess
    ) external returns (uint256 requestId) {
        require(bettingToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: keyHash,
                subId: s_subscriptionId,
                requestConfirmations: requestConfirmations,
                callbackGasLimit: callbackGasLimit,
                numWords: numWords,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({
                        nativePayment: false // Set default to false
                    })
                )
            })
        );
        s_requests[requestId] = RequestStatus({
            result: 0,
            exists: true,
            fulfilled: false,
            bettor: msg.sender,
            amount: amount,
            guess: guess
        });
        requestIds.push(requestId);
        lastRequestId = requestId;
        emit RequestSent(requestId, numWords);
        emit BetPlaced(msg.sender, amount, guess);
        return requestId;
    }

    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] calldata _randomWords
    ) internal override {
        require(s_requests[_requestId].exists, "request not found");
        uint256 result = _randomWords[0] % 2; // Map to 0 or 1
        s_requests[_requestId].fulfilled = true;
        s_requests[_requestId].result = result;
        emit RequestFulfilled(_requestId, _randomWords);
        emit CoinFlipResult(_requestId, result);

        // Handle the bet result
        RequestStatus storage request = s_requests[_requestId];
        uint256 payoutAmount = request.amount * 2; // Payout is 2x the bet amount

        if (result == (request.guess ? 1 : 0)) {
            // Win case
            uint256 houseFee = (payoutAmount * houseFeePercentage) / 100;
            uint256 payout = payoutAmount - houseFee;
            require(bettingToken.transfer(request.bettor, payout), "Payout failed");
        } else {
            // Loss case
            // No house fee is deducted in loss case
        }
    }

    function setHouseFee(uint256 _feePercentage) external onlyOwner {
        require(_feePercentage <= 100, "Fee percentage too high");
        houseFeePercentage = _feePercentage;
    }

    function setToken(IERC20 _token) external onlyOwner {
        bettingToken = _token;
    }

    function withdrawBalance() external onlyOwner {
        uint256 balance = bettingToken.balanceOf(address(this));
        require(bettingToken.transfer(msg.sender, balance), "Withdrawal failed");
        emit Withdraw(msg.sender, balance);
    }

    function getRequestStatus(
        uint256 _requestId
    ) external view returns (bool fulfilled, uint256 result, address bettor, uint256 amount, bool guess) {
        require(s_requests[_requestId].exists, "request not found");
        RequestStatus memory request = s_requests[_requestId];
        return (request.fulfilled, request.result, request.bettor, request.amount, request.guess);
    }
}
