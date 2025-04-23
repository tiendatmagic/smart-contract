// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library StringUtils {
    function toLower(string memory str) internal pure returns (string memory) {
        bytes memory bStr = bytes(str);
        bytes memory bLower = new bytes(bStr.length);
        for (uint256 i = 0; i < bStr.length; i++) {
            if ((uint8(bStr[i]) >= 65) && (uint8(bStr[i]) <= 90)) {
                bLower[i] = bytes1(uint8(bStr[i]) + 32);
            } else {
                bLower[i] = bStr[i];
            }
        }
        return string(bLower);
    }

    function contains(string memory what, string memory substr)
        internal
        pure
        returns (bool)
    {
        bytes memory whatBytes = bytes(what);
        bytes memory substrBytes = bytes(substr);
        if (substrBytes.length > whatBytes.length) return false;
        for (uint256 i = 0; i <= whatBytes.length - substrBytes.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < substrBytes.length; j++) {
                if (whatBytes[i + j] != substrBytes[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return true;
        }
        return false;
    }
}

contract EventTicketNFT is ERC721, ReentrancyGuard, Ownable {
    using StringUtils for string;

    struct EventInput {
        string eventName;
        uint256 maxTickets;
        uint256 eventTime;
        string baseTokenURI;
        string eventData;
        uint256 ticketPrice;
    }

    struct Event {
        uint256 eventId;
        string eventName;
        uint256 maxTickets;
        uint256 ticketsSold;
        uint256 eventTime;
        address creator;
        string baseTokenURI;
        uint8 status;
        string eventData;
        uint256 ticketPrice;
    }

    struct MyTicketInfo {
        uint256 tokenId;
        uint256 eventId;
        bool checkedIn;
        uint256 checkInTime;
    }

    struct AttendeeInfo {
        string fullName;
        bool gender;
        string email;
        string phoneNumber;
    }

    struct TicketInput {
        uint256 eventId;
        string fullName;
        bool gender;
        string email;
        string phoneNumber;
    }

    uint256 public eventCounter;
    uint256 public ticketIdCounter;
    uint256 public contractPercentage = 0;

    mapping(uint256 => Event) public events;
    mapping(uint256 => uint256) internal ticketToEvent;
    mapping(uint256 => bool) public checkedIn;
    mapping(uint256 => uint256) public checkInTimestamps;
    mapping(address => uint256[]) public ticketsByOwner;
    mapping(uint256 => bool) public isTicketCancelled;
    mapping(uint256 => AttendeeInfo) public attendeeInfo;

    event EventCreated(
        uint256 indexed eventId,
        string eventName,
        uint256 maxTickets,
        string eventData,
        uint256 ticketPrice
    );
    event TicketMinted(
        uint256 indexed eventId,
        uint256 indexed ticketId,
        address indexed owner,
        string fullName,
        bool gender,
        string email,
        string phoneNumber
    );
    event CheckedIn(
        uint256 indexed eventId,
        uint256 indexed ticketId,
        address indexed attendee,
        uint256 timestamp
    );
    event CheckInRemoved(uint256 indexed eventId, uint256 indexed ticketId);
    event EventStatusUpdated(uint256 indexed eventId, uint8 newStatus);
    event TicketCancelled(uint256 indexed eventId, uint256 indexed tokenId);
    event TicketUncancelled(uint256 indexed eventId, uint256 indexed tokenId);
    event PaymentDistributed(
        uint256 indexed eventId,
        address indexed creator,
        uint256 creatorAmount,
        uint256 contractAmount
    );
    event ContractPercentageUpdated(
        uint256 oldPercentage,
        uint256 newPercentage
    );

    constructor() ERC721("EventTicketNFT", "ETN") Ownable(msg.sender) {}

    receive() external payable {}

    function setContractPercentage(uint256 newPercentage) external onlyOwner {
        require(newPercentage <= 100, "Percentage must be 0-100");
        require(newPercentage != contractPercentage, "Percentage unchanged");
        uint256 oldPercentage = contractPercentage;
        contractPercentage = newPercentage;
        emit ContractPercentageUpdated(oldPercentage, newPercentage);
    }

    function createEvent(EventInput memory input) external {
        require(input.maxTickets > 0, "Max tickets must be greater than 0");
        require(bytes(input.eventName).length > 0, "Event name is required");
        require(bytes(input.eventData).length > 0, "Event data is required");

        eventCounter++;
        events[eventCounter] = Event(
            eventCounter,
            input.eventName,
            input.maxTickets,
            0,
            input.eventTime,
            msg.sender,
            input.baseTokenURI,
            1,
            input.eventData,
            input.ticketPrice
        );
        emit EventCreated(
            eventCounter,
            input.eventName,
            input.maxTickets,
            input.eventData,
            input.ticketPrice
        );
    }

    function updateEventStatus(uint256 eventId, uint8 newStatus) external {
        require(
            events[eventId].creator == msg.sender,
            "Only creator can update status"
        );
        require(newStatus == 0 || newStatus == 1, "Invalid status");
        events[eventId].status = newStatus;
        emit EventStatusUpdated(eventId, newStatus);
    }

    function updateBaseTokenURI(uint256 eventId, string memory newURI)
        external
    {
        require(
            events[eventId].creator == msg.sender,
            "Only creator can update URI"
        );
        events[eventId].baseTokenURI = newURI;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        uint256 eventId = ticketToEvent[tokenId];
        return string(abi.encodePacked(events[eventId].baseTokenURI));
    }

    function updateEvent(EventInput memory input, uint256 eventId) external {
        Event storage eventDetails = events[eventId];
        require(
            msg.sender == eventDetails.creator,
            "Only creator can update event"
        );
        require(
            input.maxTickets >= eventDetails.ticketsSold,
            "New max tickets too low"
        );
        require(bytes(input.eventName).length > 0, "Event name is required");
        require(bytes(input.eventData).length > 0, "Event data is required");

        eventDetails.eventName = input.eventName;
        eventDetails.maxTickets = input.maxTickets;
        eventDetails.eventTime = input.eventTime;
        eventDetails.baseTokenURI = input.baseTokenURI;
        eventDetails.eventData = input.eventData;
        eventDetails.ticketPrice = input.ticketPrice;
        emit EventCreated(
            eventId,
            input.eventName,
            input.maxTickets,
            input.eventData,
            input.ticketPrice
        );
    }

    function mintTicket(TicketInput memory input)
        external
        payable
        nonReentrant
    {
        Event storage eventDetails = events[input.eventId];
        require(eventDetails.eventId != 0, "Event does not exist");
        require(block.timestamp < eventDetails.eventTime, "Event has ended");
        require(
            eventDetails.ticketsSold < eventDetails.maxTickets,
            "Tickets sold out"
        );
        require(eventDetails.status == 1, "Event is not active");
        require(bytes(input.fullName).length > 0, "Full name is required");
        require(bytes(input.email).length > 0, "Email is required");
        require(
            bytes(input.phoneNumber).length > 0,
            "Phone number is required"
        );

        // Check if ticket requires payment
        if (eventDetails.ticketPrice > 0) {
            require(
                msg.value >= eventDetails.ticketPrice,
                "Insufficient payment"
            );

            // Calculate distribution based on contractPercentage
            uint256 contractAmount = (eventDetails.ticketPrice *
                contractPercentage) / 100;
            uint256 creatorAmount = eventDetails.ticketPrice - contractAmount;

            // Transfer creator's share - must succeed
            (bool success, ) = payable(eventDetails.creator).call{
                value: creatorAmount
            }("");
            require(success, "Transfer to creator failed");

            // Emit payment distribution event
            emit PaymentDistributed(
                input.eventId,
                eventDetails.creator,
                creatorAmount,
                contractAmount
            );

            // Refund excess payment if any
            if (msg.value > eventDetails.ticketPrice) {
                (bool refundSuccess, ) = payable(msg.sender).call{
                    value: msg.value - eventDetails.ticketPrice
                }("");
                require(refundSuccess, "Refund failed");
            }
        } else {
            // Ensure no payment is sent for free events
            require(msg.value == 0, "No payment required for free event");
        }

        ticketIdCounter++;
        uint256 tokenId = ticketIdCounter;
        _safeMint(msg.sender, tokenId);
        ticketToEvent[tokenId] = input.eventId;
        ticketsByOwner[msg.sender].push(tokenId);
        eventDetails.ticketsSold++;
        attendeeInfo[tokenId] = AttendeeInfo(
            input.fullName,
            input.gender,
            input.email,
            input.phoneNumber
        );
        emit TicketMinted(
            input.eventId,
            tokenId,
            msg.sender,
            input.fullName,
            input.gender,
            input.email,
            input.phoneNumber
        );
    }

    function checkIn(uint256 tokenId) external {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        uint256 eventId = ticketToEvent[tokenId];
        require(eventId != 0, "Ticket not associated with any event");
        require(ownerOf(tokenId) == msg.sender, "Not ticket owner");
        require(!checkedIn[tokenId], "Already checked in");
        require(
            block.timestamp <= events[eventId].eventTime + 1 hours,
            "Check-in period ended"
        );
        require(!isTicketCancelled[tokenId], "Ticket is cancelled");
        require(events[eventId].status == 1, "Event is not active");

        checkedIn[tokenId] = true;
        checkInTimestamps[tokenId] = block.timestamp;
        emit CheckedIn(eventId, tokenId, msg.sender, block.timestamp);
    }

    function getTicketInfo(uint256 tokenId)
        external
        view
        returns (
            uint256 eventId,
            address owner,
            bool checkedInStatus,
            uint256 timestamp,
            string memory eventName,
            uint8 eventStatus,
            AttendeeInfo memory attendee,
            bool ticketCancelled
        )
    {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        eventId = ticketToEvent[tokenId];
        require(eventId != 0, "Ticket not associated with any event");
        owner = ownerOf(tokenId);
        checkedInStatus = checkedIn[tokenId];
        timestamp = checkInTimestamps[tokenId];
        eventName = events[eventId].eventName;
        eventStatus = events[eventId].status;
        attendee = attendeeInfo[tokenId];
        ticketCancelled = isTicketCancelled[tokenId];
    }

    function removeCheckIn(uint256 tokenId) external {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        uint256 eventId = ticketToEvent[tokenId];
        require(eventId != 0, "Ticket not associated with any event");
        require(
            events[eventId].creator == msg.sender ||
                ownerOf(tokenId) == msg.sender,
            "Not authorized"
        );
        require(checkedIn[tokenId], "Not checked in");

        checkedIn[tokenId] = false;
        checkInTimestamps[tokenId] = 0;
        emit CheckInRemoved(eventId, tokenId);
    }

    function getMyTickets()
        external
        view
        returns (MyTicketInfo[] memory, AttendeeInfo[] memory)
    {
        uint256[] memory userTickets = ticketsByOwner[msg.sender];
        MyTicketInfo[] memory ticketInfo = new MyTicketInfo[](
            userTickets.length
        );
        AttendeeInfo[] memory attendeeDetails = new AttendeeInfo[](
            userTickets.length
        );

        for (uint256 i = 0; i < userTickets.length; i++) {
            uint256 tokenId = userTickets[i];
            ticketInfo[i] = MyTicketInfo(
                tokenId,
                ticketToEvent[tokenId],
                checkedIn[tokenId],
                checkInTimestamps[tokenId]
            );
            attendeeDetails[i] = attendeeInfo[tokenId];
        }
        return (ticketInfo, attendeeDetails);
    }

    function getEventTicketsWithName(address user, uint256 eventId)
        external
        view
        returns (
            uint256[] memory,
            string memory,
            AttendeeInfo[] memory
        )
    {
        uint256[] memory allTickets = ticketsByOwner[user];
        uint256 count = 0;
        for (uint256 i = 0; i < allTickets.length; i++) {
            if (ticketToEvent[allTickets[i]] == eventId) count++;
        }

        uint256[] memory filtered = new uint256[](count);
        AttendeeInfo[] memory attendees = new AttendeeInfo[](count);
        uint256 j = 0;
        for (uint256 i = 0; i < allTickets.length; i++) {
            if (ticketToEvent[allTickets[i]] == eventId) {
                filtered[j] = allTickets[i];
                attendees[j] = attendeeInfo[allTickets[i]];
                j++;
            }
        }
        return (filtered, events[eventId].eventName, attendees);
    }

    function cancelTicket(uint256 tokenId) external {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        uint256 eventId = ticketToEvent[tokenId];
        require(eventId != 0, "Ticket not associated with any event");
        require(
            events[eventId].creator == msg.sender,
            "Only creator can cancel"
        );
        require(!isTicketCancelled[tokenId], "Ticket already cancelled");

        isTicketCancelled[tokenId] = true;
        emit TicketCancelled(eventId, tokenId);
    }

    function unCancelTicket(uint256 tokenId) external {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        uint256 eventId = ticketToEvent[tokenId];
        require(eventId != 0, "Ticket not associated with any event");
        require(
            events[eventId].creator == msg.sender,
            "Only creator can uncancel"
        );
        require(isTicketCancelled[tokenId], "Ticket not cancelled");

        isTicketCancelled[tokenId] = false;
        emit TicketUncancelled(eventId, tokenId);
    }

    function withdrawTokenNative(uint256 amount)
        external
        onlyOwner
        nonReentrant
    {
        require(amount > 0, "Amount must be greater than 0");
        require(address(this).balance >= amount, "Insufficient balance");

        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "Transfer failed");
    }

    function withdrawToken(address tokenContract, uint256 amount)
        external
        onlyOwner
        nonReentrant
    {
        require(amount > 0, "Amount must be greater than 0");
        require(tokenContract != address(0), "Invalid token contract");

        IERC20 token = IERC20(tokenContract);
        uint256 balance = token.balanceOf(address(this));
        require(balance >= amount, "Insufficient token balance");

        bool success = token.transfer(owner(), amount);
        require(success, "Token transfer failed");
    }

    function getEventInfo(uint256 eventId)
        external
        view
        returns (
            uint256 _eventId,
            string memory eventName,
            uint256 maxTickets,
            uint256 ticketsSold,
            uint256 eventTime,
            address creator,
            string memory baseTokenURI,
            uint8 status,
            string memory eventData,
            uint256 ticketPrice
        )
    {
        require(events[eventId].eventId != 0, "Event does not exist");
        _eventId = events[eventId].eventId;
        eventName = events[eventId].eventName;
        maxTickets = events[eventId].maxTickets;
        ticketsSold = events[eventId].ticketsSold;
        eventTime = events[eventId].eventTime;
        creator = events[eventId].creator;
        baseTokenURI = events[eventId].baseTokenURI;
        status = events[eventId].status;
        eventData = events[eventId].eventData;
        ticketPrice = events[eventId].ticketPrice;
    }

    function getEventCheckInStats(uint256 eventId)
        external
        view
        returns (uint256 checkedInCount, uint256 notCheckedInCount)
    {
        require(events[eventId].eventId != 0, "Event does not exist");
        uint256 checkedInUsers = 0;
        for (uint256 i = 1; i <= ticketIdCounter; i++) {
            if (ticketToEvent[i] == eventId && checkedIn[i]) {
                checkedInUsers++;
            }
        }
        checkedInCount = checkedInUsers;
        notCheckedInCount = events[eventId].ticketsSold - checkedInUsers;
    }

    function getEventsByPage(uint256 pageNumber, uint8 status)
        external
        view
        returns (string[] memory eventDetails)
    {
        require(pageNumber > 0, "Page number must be greater than 0");
        require(status == 0 || status == 1, "Invalid status");

        eventDetails = new string[](10);
        uint256 count = 0;
        uint256 eventsProcessed = 0;
        uint256 startIndex = (pageNumber - 1) * 10;

        for (uint256 i = eventCounter; i >= 1 && count < 10; i--) {
            if (events[i].status == status) {
                eventsProcessed++;
                if (eventsProcessed > startIndex) {
                    eventDetails[count] = string(
                        abi.encodePacked(
                            uintToString(events[i].eventId),
                            ",",
                            events[i].eventName,
                            ",",
                            uintToString(events[i].maxTickets),
                            ",",
                            uintToString(events[i].ticketsSold),
                            ",",
                            uintToString(events[i].eventTime),
                            ",",
                            addressToString(events[i].creator),
                            ",",
                            events[i].baseTokenURI,
                            ",",
                            uintToString(events[i].status),
                            ",",
                            events[i].eventData,
                            ",",
                            uintToString(events[i].ticketPrice)
                        )
                    );
                    count++;
                }
            }
            if (i == 1) break;
        }
        return eventDetails;
    }

    function searchEventsByName(
        uint256 pageNumber,
        uint8 status,
        string memory searchTerm
    ) external view returns (string[] memory eventDetails) {
        require(pageNumber > 0, "Page number must be greater than 0");
        require(status == 0 || status == 1, "Invalid status");

        eventDetails = new string[](10);
        uint256 count = 0;
        uint256 eventsProcessed = 0;
        uint256 startIndex = (pageNumber - 1) * 10;

        for (uint256 i = eventCounter; i >= 1 && count < 10; i--) {
            if (
                events[i].status == status &&
                events[i].eventName.toLower().contains(searchTerm.toLower())
            ) {
                eventsProcessed++;
                if (eventsProcessed > startIndex) {
                    eventDetails[count] = string(
                        abi.encodePacked(
                            uintToString(events[i].eventId),
                            ",",
                            events[i].eventName,
                            ",",
                            uintToString(events[i].maxTickets),
                            ",",
                            uintToString(events[i].ticketsSold),
                            ",",
                            uintToString(events[i].eventTime),
                            ",",
                            addressToString(events[i].creator),
                            ",",
                            events[i].baseTokenURI,
                            ",",
                            uintToString(events[i].status),
                            ",",
                            events[i].eventData,
                            ",",
                            uintToString(events[i].ticketPrice)
                        )
                    );
                    count++;
                }
            }
            if (i == 1) break;
        }
        return eventDetails;
    }

    function uintToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits--;
            buffer[digits] = bytes1(uint8(48 + (value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function addressToString(address addr)
        internal
        pure
        returns (string memory)
    {
        bytes32 value = bytes32(uint256(uint160(addr)));
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(42);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(value[i + 12] >> 4)];
            str[3 + i * 2] = alphabet[uint8(value[i + 12] & 0x0f)];
        }
        return string(str);
    }

    function renounceOwnership() public view override onlyOwner {
        revert("Ownership renunciation not allowed");
    }
}
