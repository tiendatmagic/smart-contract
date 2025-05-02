// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library StringUtils {
    function toLower(string memory str) internal pure returns (string memory) {
        bytes memory bStr = bytes(str);
        for (uint256 i = 0; i < bStr.length; i++) {
            uint8 char = uint8(bStr[i]);
            if (char >= 65 && char <= 90) {
                bStr[i] = bytes1(char + 32);
            }
        }
        return string(bStr);
    }

    function contains(
        string memory what,
        string memory substr
    ) internal pure returns (bool) {
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
        uint256[2] timeRange;
        string baseTokenURI;
        string eventData;
        uint256 ticketPrice;
        uint256 categoryId;
    }

    struct Event {
        uint256 eventId;
        string eventName;
        uint256 maxTickets;
        uint256 ticketsSold;
        uint256 startTime;
        uint256 endTime;
        address creator;
        string baseTokenURI;
        uint8 status;
        string eventData;
        uint256 ticketPrice;
        uint256 categoryId;
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
    uint256 public contractPercentage;

    address private constant DEAD_ADDRESS =
        0x000000000000000000000000000000000000dEaD;

    mapping(uint256 => Event) public events;
    mapping(uint256 => uint256) private _ticketToEvent;
    mapping(uint256 => uint256) private _checkInTimestamps;
    mapping(address => uint256[]) private _ticketsByOwner;
    mapping(uint256 => bool) public isTicketCancelled;
    mapping(uint256 => AttendeeInfo) public attendeeInfo;

    event EventCreated(
        uint256 indexed eventId,
        string eventName,
        uint256 maxTickets,
        string eventData,
        uint256 ticketPrice,
        uint256 categoryId
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
    event TicketRecovered(
        uint256 indexed eventId,
        uint256 indexed tokenId,
        address indexed creator,
        address fromAddress
    );

    constructor() ERC721("EventTicketNFT", "ETN") Ownable(msg.sender) {}

    function setContractPercentage(uint256 newPercentage) external onlyOwner {
        require(newPercentage <= 100, "Invalid percentage");
        require(newPercentage != contractPercentage, "No change");
        emit ContractPercentageUpdated(contractPercentage, newPercentage);
        contractPercentage = newPercentage;
    }

    function createEvent(EventInput memory input) external {
        require(input.maxTickets > 0, "Invalid ticket count");
        require(bytes(input.eventName).length > 0, "Name required");
        require(bytes(input.eventData).length > 0, "Data required");
        require(
            input.categoryId >= 1 && input.categoryId <= 20,
            "Invalid category"
        );
        require(input.timeRange[1] >= input.timeRange[0], "Invalid time range");

        eventCounter++;
        events[eventCounter] = Event(
            eventCounter,
            input.eventName,
            input.maxTickets,
            0,
            input.timeRange[0],
            input.timeRange[1],
            msg.sender,
            input.baseTokenURI,
            1,
            input.eventData,
            input.ticketPrice,
            input.categoryId
        );
        emit EventCreated(
            eventCounter,
            input.eventName,
            input.maxTickets,
            input.eventData,
            input.ticketPrice,
            input.categoryId
        );
    }

    function updateEventStatus(uint256 eventId, uint8 newStatus) external {
        require(events[eventId].creator == msg.sender, "Not creator");
        require(newStatus <= 1, "Invalid status");
        events[eventId].status = newStatus;
        emit EventStatusUpdated(eventId, newStatus);
    }

    function updateBaseTokenURI(
        uint256 eventId,
        string memory newURI
    ) external {
        require(events[eventId].creator == msg.sender, "Not creator");
        events[eventId].baseTokenURI = newURI;
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "Nonexistent token");
        return
            string(
                abi.encodePacked(events[_ticketToEvent[tokenId]].baseTokenURI)
            );
    }

    function updateEvent(EventInput memory input, uint256 eventId) external {
        Event storage e = events[eventId];
        require(msg.sender == e.creator, "Not creator");
        require(input.maxTickets >= e.ticketsSold, "Invalid ticket count");
        require(bytes(input.eventName).length > 0, "Name required");
        require(bytes(input.eventData).length > 0, "Data required");
        require(
            input.categoryId >= 1 && input.categoryId <= 20,
            "Invalid category"
        );
        require(input.timeRange[1] >= input.timeRange[0], "Invalid time range");

        e.eventName = input.eventName;
        e.maxTickets = input.maxTickets;
        e.startTime = input.timeRange[0];
        e.endTime = input.timeRange[1];
        e.baseTokenURI = input.baseTokenURI;
        e.eventData = input.eventData;
        e.ticketPrice = input.ticketPrice;
        e.categoryId = input.categoryId;
        emit EventCreated(
            eventId,
            input.eventName,
            input.maxTickets,
            input.eventData,
            input.ticketPrice,
            input.categoryId
        );
    }

    function mintTicket(
        TicketInput memory input
    ) external payable nonReentrant {
        Event storage e = events[input.eventId];
        require(e.eventId != 0, "Nonexistent event");
        require(
            block.timestamp >= e.startTime && block.timestamp <= e.endTime,
            "Event inactive"
        );
        require(e.ticketsSold < e.maxTickets, "Sold out");
        require(e.status == 1, "Event not active");
        require(bytes(input.fullName).length > 0, "Name required");
        require(bytes(input.email).length > 0, "Email required");
        require(bytes(input.phoneNumber).length > 0, "Phone required");

        uint256[] storage userTickets = _ticketsByOwner[msg.sender];
        for (uint256 i = 0; i < userTickets.length; i++) {
            uint256 existingTokenId = userTickets[i];
            if (
                _ticketToEvent[existingTokenId] == input.eventId &&
                !isTicketCancelled[existingTokenId]
            ) {
                revert("Already owns ticket");
            }
        }

        if (e.ticketPrice > 0) {
            require(msg.value >= e.ticketPrice, "Insufficient payment");
            uint256 contractAmount = (e.ticketPrice * contractPercentage) / 100;
            uint256 creatorAmount = e.ticketPrice - contractAmount;

            (bool success, ) = e.creator.call{value: creatorAmount}("");
            require(success, "Payment failed");

            emit PaymentDistributed(
                input.eventId,
                e.creator,
                creatorAmount,
                contractAmount
            );

            if (msg.value > e.ticketPrice) {
                payable(msg.sender).transfer(msg.value - e.ticketPrice);
            }
        }

        uint256 tokenId = ++ticketIdCounter;
        _safeMint(msg.sender, tokenId);
        _ticketToEvent[tokenId] = input.eventId;
        userTickets.push(tokenId);
        e.ticketsSold++;
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
        require(_ownerOf(tokenId) != address(0), "Nonexistent token");
        uint256 eventId = _ticketToEvent[tokenId];
        require(ownerOf(tokenId) == msg.sender, "Not owner");
        require(_checkInTimestamps[tokenId] == 0, "Already checked in");
        require(!isTicketCancelled[tokenId], "Ticket cancelled");
        require(events[eventId].status == 1, "Event not active");
        require(
            block.timestamp >= events[eventId].startTime &&
                block.timestamp <= events[eventId].endTime + 1 hours,
            "Check-in closed"
        );

        _checkInTimestamps[tokenId] = block.timestamp;
        emit CheckedIn(eventId, tokenId, msg.sender, block.timestamp);
    }

    function getTicketInfo(
        uint256 tokenId
    )
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
        require(_ownerOf(tokenId) != address(0), "Nonexistent token");
        eventId = _ticketToEvent[tokenId];
        Event storage e = events[eventId];
        owner = ownerOf(tokenId);
        checkedInStatus = _checkInTimestamps[tokenId] > 0;
        timestamp = _checkInTimestamps[tokenId];
        eventName = e.eventName;
        eventStatus = e.status;
        attendee = attendeeInfo[tokenId];
        ticketCancelled = isTicketCancelled[tokenId];
    }

    function removeCheckIn(uint256 tokenId) external {
        require(_ownerOf(tokenId) != address(0), "Nonexistent token");
        uint256 eventId = _ticketToEvent[tokenId];
        require(
            events[eventId].creator == msg.sender ||
                ownerOf(tokenId) == msg.sender,
            "Not authorized"
        );
        require(_checkInTimestamps[tokenId] > 0, "Not checked in");

        _checkInTimestamps[tokenId] = 0;
        emit CheckInRemoved(eventId, tokenId);
    }

    function getMyTickets()
        external
        view
        returns (MyTicketInfo[] memory, AttendeeInfo[] memory)
    {
        uint256[] memory userTickets = _ticketsByOwner[msg.sender];
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
                _ticketToEvent[tokenId],
                _checkInTimestamps[tokenId] > 0,
                _checkInTimestamps[tokenId]
            );
            attendeeDetails[i] = attendeeInfo[tokenId];
        }
        return (ticketInfo, attendeeDetails);
    }

    function getEventTicketsWithName(
        address user,
        uint256 eventId
    )
        external
        view
        returns (uint256[] memory, string memory, AttendeeInfo[] memory)
    {
        uint256[] memory allTickets = _ticketsByOwner[user];
        uint256 count;
        for (uint256 i = 0; i < allTickets.length; i++) {
            if (_ticketToEvent[allTickets[i]] == eventId) count++;
        }

        uint256[] memory filtered = new uint256[](count);
        AttendeeInfo[] memory attendees = new AttendeeInfo[](count);
        uint256 j;
        for (uint256 i = 0; i < allTickets.length; i++) {
            if (_ticketToEvent[allTickets[i]] == eventId) {
                filtered[j] = allTickets[i];
                attendees[j] = attendeeInfo[allTickets[i]];
                j++;
            }
        }
        return (filtered, events[eventId].eventName, attendees);
    }

    function cancelTicket(uint256 tokenId) external {
        require(_ownerOf(tokenId) != address(0), "Nonexistent token");
        uint256 eventId = _ticketToEvent[tokenId];
        require(events[eventId].creator == msg.sender, "Not creator");
        require(!isTicketCancelled[tokenId], "Already cancelled");

        isTicketCancelled[tokenId] = true;
        emit TicketCancelled(eventId, tokenId);
    }

    function unCancelTicket(uint256 tokenId) external {
        require(_ownerOf(tokenId) != address(0), "Nonexistent token");
        uint256 eventId = _ticketToEvent[tokenId];
        require(events[eventId].creator == msg.sender, "Not creator");
        require(isTicketCancelled[tokenId], "Not cancelled");

        isTicketCancelled[tokenId] = false;
        emit TicketUncancelled(eventId, tokenId);
    }

    function withdrawTokenNative(
        uint256 amount
    ) external onlyOwner nonReentrant {
        require(
            amount > 0 && amount <= address(this).balance,
            "Invalid amount"
        );
        payable(owner()).transfer(amount);
    }

    function withdrawToken(
        address tokenContract,
        uint256 amount
    ) external onlyOwner nonReentrant {
        require(amount > 0, "Invalid amount");
        IERC20 token = IERC20(tokenContract);
        require(
            amount <= token.balanceOf(address(this)),
            "Insufficient balance"
        );
        require(token.transfer(owner(), amount), "Transfer failed");
    }

    function getEventInfo(
        uint256 eventId
    )
        external
        view
        returns (
            uint256 _eventId,
            string memory eventName,
            uint256 maxTickets,
            uint256 ticketsSold,
            uint256 startTime,
            uint256 endTime,
            address creator,
            string memory baseTokenURI,
            uint8 status,
            string memory eventData,
            uint256 ticketPrice,
            uint256 categoryId
        )
    {
        Event storage e = events[eventId];
        require(e.eventId != 0, "Nonexistent event");
        return (
            e.eventId,
            e.eventName,
            e.maxTickets,
            e.ticketsSold,
            e.startTime,
            e.endTime,
            e.creator,
            e.baseTokenURI,
            e.status,
            e.eventData,
            e.ticketPrice,
            e.categoryId
        );
    }

    function getEventCheckInStats(
        uint256 eventId
    )
        external
        view
        returns (uint256 checkedInCount, uint256 notCheckedInCount)
    {
        require(events[eventId].eventId != 0, "Nonexistent event");
        uint256 count;
        for (uint256 i = 1; i <= ticketIdCounter; i++) {
            if (_ticketToEvent[i] == eventId && _checkInTimestamps[i] > 0) {
                count++;
            }
        }
        return (count, events[eventId].ticketsSold - count);
    }

    function getEventsByPage(
        uint256 pageNumber,
        uint8 status,
        uint256 categoryId
    ) external view returns (string[] memory) {
        require(pageNumber > 0, "Invalid page");
        require(status <= 1, "Invalid status");

        string[] memory eventDetails = new string[](10);
        uint256 count;
        uint256 processed;
        uint256 startIndex = (pageNumber - 1) * 10;

        for (uint256 i = eventCounter; i >= 1 && count < 10; i--) {
            if (
                events[i].eventId != 0 &&
                events[i].status == status &&
                (categoryId == 0 || events[i].categoryId == categoryId)
            ) {
                if (++processed > startIndex) {
                    eventDetails[count++] = string(
                        abi.encodePacked(
                            _uintToString(events[i].eventId),
                            ",",
                            events[i].eventName,
                            ",",
                            _uintToString(events[i].maxTickets),
                            ",",
                            _uintToString(events[i].ticketsSold),
                            ",",
                            _uintToString(events[i].startTime),
                            ",",
                            _uintToString(events[i].endTime),
                            ",",
                            _addressToString(events[i].creator),
                            ",",
                            events[i].baseTokenURI,
                            ",",
                            _uintToString(events[i].status),
                            ",",
                            events[i].eventData,
                            ",",
                            _uintToString(events[i].ticketPrice),
                            ",",
                            _uintToString(events[i].categoryId)
                        )
                    );
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
    ) external view returns (string[] memory) {
        require(pageNumber > 0, "Invalid page");
        require(status <= 1, "Invalid status");

        string[] memory eventDetails = new string[](10);
        uint256 count;
        uint256 processed;
        uint256 startIndex = (pageNumber - 1) * 10;
        string memory searchLower = searchTerm.toLower();

        for (uint256 i = eventCounter; i >= 1 && count < 10; i--) {
            if (
                events[i].status == status &&
                events[i].eventName.toLower().contains(searchLower)
            ) {
                if (++processed > startIndex) {
                    eventDetails[count++] = string(
                        abi.encodePacked(
                            _uintToString(events[i].eventId),
                            ",",
                            events[i].eventName,
                            ",",
                            _uintToString(events[i].maxTickets),
                            ",",
                            _uintToString(events[i].ticketsSold),
                            ",",
                            _uintToString(events[i].startTime),
                            ",",
                            _uintToString(events[i].endTime),
                            ",",
                            _addressToString(events[i].creator),
                            ",",
                            events[i].baseTokenURI,
                            ",",
                            _uintToString(events[i].status),
                            ",",
                            events[i].eventData,
                            ",",
                            _uintToString(events[i].ticketPrice),
                            ",",
                            _uintToString(events[i].categoryId)
                        )
                    );
                }
            }
            if (i == 1) break;
        }
        return eventDetails;
    }

    function recoverTicket(uint256 tokenId) external nonReentrant {
        require(_ownerOf(tokenId) != address(0), "Nonexistent token");
        uint256 eventId = _ticketToEvent[tokenId];
        require(events[eventId].creator == msg.sender, "Not creator");
        address currentOwner = ownerOf(tokenId);
        require(currentOwner == DEAD_ADDRESS, "Not in dead address");

        uint256[] storage ownerTickets = _ticketsByOwner[currentOwner];
        for (uint256 i = 0; i < ownerTickets.length; i++) {
            if (ownerTickets[i] == tokenId) {
                ownerTickets[i] = ownerTickets[ownerTickets.length - 1];
                ownerTickets.pop();
                break;
            }
        }

        _transfer(currentOwner, msg.sender, tokenId);
        _ticketsByOwner[msg.sender].push(tokenId);
        emit TicketRecovered(eventId, tokenId, msg.sender, currentOwner);
    }

    function getTicketsByEventAndPage(
        uint256 eventId,
        uint256 pageNumber
    ) external view returns (string[] memory) {
        require(events[eventId].eventId != 0, "Nonexistent event");
        require(pageNumber > 0, "Invalid page");

        string[] memory ticketDetails = new string[](10);
        uint256 count;
        uint256 processed;
        uint256 startIndex = (pageNumber - 1) * 10;

        for (uint256 i = ticketIdCounter; i >= 1 && count < 10; i--) {
            if (_ticketToEvent[i] == eventId) {
                if (++processed > startIndex) {
                    address owner = _ownerOf(i);
                    AttendeeInfo memory attendee = attendeeInfo[i];
                    ticketDetails[count++] = string(
                        abi.encodePacked(
                            _uintToString(i),
                            ",",
                            _uintToString(eventId),
                            ",",
                            _addressToString(owner),
                            ",",
                            attendee.fullName,
                            ",",
                            attendee.gender ? "1" : "0",
                            ",",
                            attendee.email,
                            ",",
                            attendee.phoneNumber,
                            ",",
                            _checkInTimestamps[i] > 0 ? "1" : "0",
                            ",",
                            _uintToString(_checkInTimestamps[i]),
                            ",",
                            isTicketCancelled[i] ? "1" : "0"
                        )
                    );
                }
            }
            if (i == 1) break;
        }
        return ticketDetails;
    }

    function _uintToString(uint256 value) private pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            buffer[--digits] = bytes1(uint8(48 + (value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function _addressToString(
        address addr
    ) private pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(42);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < 20; i++) {
            uint8 shift = uint8(8 * (19 - i));
            str[2 + i * 2] = alphabet[uint8(uint160(addr) >> shift) & 0xf];
            str[3 + i * 2] = alphabet[
                uint8(uint160(addr) >> (shift + 4)) & 0xf
            ];
        }
        return string(str);
    }

    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override returns (address) {
        address from = super._update(to, tokenId, auth);

        if (from != address(0)) {
            uint256[] storage fromTickets = _ticketsByOwner[from];
            for (uint256 i = 0; i < fromTickets.length; i++) {
                if (fromTickets[i] == tokenId) {
                    fromTickets[i] = fromTickets[fromTickets.length - 1];
                    fromTickets.pop();
                    break;
                }
            }
        }

        if (to != address(0)) {
            _ticketsByOwner[to].push(tokenId);
        }

        return from;
    }

    function renounceOwnership() public view override onlyOwner {
        revert("Cannot renounce");
    }
}
