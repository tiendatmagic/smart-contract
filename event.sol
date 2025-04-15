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

    function contains(
        string memory what,
        string memory substr
    ) internal pure returns (bool) {
        bytes memory whatBytes = bytes(what);
        bytes memory substrBytes = bytes(substr);

        if (substrBytes.length > whatBytes.length) {
            return false;
        }

        for (uint256 i = 0; i <= whatBytes.length - substrBytes.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < substrBytes.length; j++) {
                if (whatBytes[i + j] != substrBytes[j]) {
                    found = false;
                    break;
                }
            }
            if (found) {
                return true;
            }
        }

        return false;
    }
}

contract EventTicketNFT is ERC721, ReentrancyGuard, Ownable {
    using StringUtils for string;

    struct MyTicketInfo {
        uint256 tokenId;
        uint256 eventId;
        bool checkedIn;
        uint256 checkInTime;
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
    }

    uint256 public eventCounter;
    uint256 public ticketIdCounter;

    mapping(uint256 => Event) public events;
    mapping(uint256 => uint256) internal ticketToEvent;
    mapping(uint256 => bool) public checkedIn;
    mapping(uint256 => uint256) public checkInTimestamps;
    mapping(address => uint256[]) public ticketsByOwner;
    mapping(uint256 => bool) public isTicketCancelled;

    event EventCreated(
        uint256 indexed eventId,
        string eventName,
        uint256 maxTickets
    );
    event TicketMinted(
        uint256 indexed eventId,
        uint256 indexed ticketId,
        address indexed owner
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

    constructor() ERC721("EventTicketNFT", "ETN") Ownable(msg.sender) {}

    receive() external payable {}

    function createEvent(
        string memory _eventName,
        uint256 _maxTickets,
        uint256 _eventTime,
        string memory _baseTokenURI
    ) external {
        require(_maxTickets > 0);
        eventCounter++;
        events[eventCounter] = Event(
            eventCounter,
            _eventName,
            _maxTickets,
            0,
            _eventTime,
            msg.sender,
            _baseTokenURI,
            1
        );
        emit EventCreated(eventCounter, _eventName, _maxTickets);
    }

    function updateEventStatus(uint256 _eventId, uint8 _newStatus) external {
        require(events[_eventId].creator == msg.sender);
        require(_newStatus == 0 || _newStatus == 1);
        events[_eventId].status = _newStatus;
        emit EventStatusUpdated(_eventId, _newStatus);
    }

    function updateBaseTokenURI(
        uint256 _eventId,
        string memory _newURI
    ) external {
        require(events[_eventId].creator == msg.sender);
        events[_eventId].baseTokenURI = _newURI;
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        require(_ownerOf(tokenId) != address(0));
        uint256 eventId = ticketToEvent[tokenId];
        return string(abi.encodePacked(events[eventId].baseTokenURI));
    }

    function updateEvent(
        uint256 _eventId,
        string memory _newEventName,
        uint256 _newMaxTickets,
        uint256 _newEventTime
    ) external {
        Event storage eventDetails = events[_eventId];
        require(msg.sender == eventDetails.creator);
        require(_newMaxTickets >= eventDetails.ticketsSold);
        eventDetails.eventName = _newEventName;
        eventDetails.maxTickets = _newMaxTickets;
        eventDetails.eventTime = _newEventTime;
        emit EventCreated(_eventId, _newEventName, _newMaxTickets);
    }

    function mintTicket(uint256 _eventId) external nonReentrant {
        Event storage eventDetails = events[_eventId];
        require(eventDetails.eventId != 0);
        require(block.timestamp < eventDetails.eventTime);
        require(eventDetails.ticketsSold < eventDetails.maxTickets);
        require(eventDetails.status == 1);
        ticketIdCounter++;
        uint256 tokenId = ticketIdCounter;
        _safeMint(msg.sender, tokenId);
        ticketToEvent[tokenId] = _eventId;
        ticketsByOwner[msg.sender].push(tokenId);
        eventDetails.ticketsSold++;
        emit TicketMinted(_eventId, tokenId, msg.sender);
    }

    function checkIn(uint256 _tokenId, uint256 _eventId) external {
        require(ticketToEvent[_tokenId] == _eventId);
        require(ownerOf(_tokenId) == msg.sender);
        require(!checkedIn[_tokenId]);
        require(block.timestamp <= events[_eventId].eventTime + 1 hours);
        require(!isTicketCancelled[_tokenId]);
        require(events[_eventId].status == 1);
        checkedIn[_tokenId] = true;
        checkInTimestamps[_tokenId] = block.timestamp;
        emit CheckedIn(_eventId, _tokenId, msg.sender, block.timestamp);
    }

    function getCheckInInfo(
        uint256 eventId,
        uint256 tokenId
    )
        external
        view
        returns (
            address owner,
            bool checkedInStatus,
            uint256 timestamp,
            string memory eventName,
            uint8 eventStatus
        )
    {
        require(ticketToEvent[tokenId] == eventId);
        owner = ownerOf(tokenId);
        checkedInStatus = checkedIn[tokenId];
        timestamp = checkInTimestamps[tokenId];
        eventName = events[eventId].eventName;
        eventStatus = events[eventId].status;
    }

    function removeCheckIn(uint256 _eventId, uint256 _tokenId) external {
        require(
            events[_eventId].creator == msg.sender ||
                ownerOf(_tokenId) == msg.sender
        );
        require(ticketToEvent[_tokenId] == _eventId);
        require(checkedIn[_tokenId], "Not checked in");
        checkedIn[_tokenId] = false;
        checkInTimestamps[_tokenId] = 0;
        emit CheckInRemoved(_eventId, _tokenId);
    }

    function getMyTickets() external view returns (MyTicketInfo[] memory) {
        uint256[] memory userTickets = ticketsByOwner[msg.sender];
        MyTicketInfo[] memory result = new MyTicketInfo[](userTickets.length);
        for (uint256 i = 0; i < userTickets.length; i++) {
            uint256 tokenId = userTickets[i];
            result[i] = MyTicketInfo(
                tokenId,
                ticketToEvent[tokenId],
                checkedIn[tokenId],
                checkInTimestamps[tokenId]
            );
        }
        return result;
    }

    function getEventTicketsWithName(
        address user,
        uint256 eventId
    ) external view returns (uint256[] memory, string memory) {
        uint256[] memory allTickets = ticketsByOwner[user];
        uint256 count = 0;
        for (uint256 i = 0; i < allTickets.length; i++) {
            if (ticketToEvent[allTickets[i]] == eventId) count++;
        }
        uint256[] memory filtered = new uint256[](count);
        uint256 j = 0;
        for (uint256 i = 0; i < allTickets.length; i++) {
            if (ticketToEvent[allTickets[i]] == eventId)
                filtered[j++] = allTickets[i];
        }
        return (filtered, events[eventId].eventName);
    }

    function cancelTicket(uint256 eventId, uint256 tokenId) external {
        require(ticketToEvent[tokenId] == eventId);
        require(events[eventId].creator == msg.sender);
        require(!isTicketCancelled[tokenId]);

        isTicketCancelled[tokenId] = true;

        emit TicketCancelled(eventId, tokenId);
    }

    function unCancelTicket(uint256 eventId, uint256 tokenId) external {
        require(ticketToEvent[tokenId] == eventId);
        require(events[eventId].creator == msg.sender);
        require(isTicketCancelled[tokenId]);

        isTicketCancelled[tokenId] = false;

        emit TicketUncancelled(eventId, tokenId);
    }

    function withdrawTokenNative(
        uint256 amount
    ) external onlyOwner nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(
            address(this).balance >= amount,
            "Insufficient native token balance"
        );

        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "Native token transfer failed");
    }

    function withdrawToken(
        address tokenContract,
        uint256 amount
    ) external onlyOwner nonReentrant {
        require(amount > 0);
        require(tokenContract != address(0));

        IERC20 token = IERC20(tokenContract);
        uint256 balance = token.balanceOf(address(this));
        require(balance >= amount, "Insufficient token balance");

        bool success = token.transfer(owner(), amount);
        require(success, "Token transfer failed");
    }

    function getEventsByPage(
        uint256 pageNumber
    )
        external
        view
        returns (
            uint256[] memory eventIds,
            string[] memory eventNames,
            uint256[] memory maxTickets,
            uint256[] memory ticketsSold,
            uint256[] memory eventTimes,
            address[] memory creators,
            string[] memory baseTokenURIs,
            uint8[] memory statuses
        )
    {
        require(pageNumber > 0, "Page number must be greater than 0");
        uint256 startIndex = (pageNumber - 1) * 10;
        uint256 endIndex = startIndex + 10;
        if (endIndex > eventCounter) endIndex = eventCounter;
        if (startIndex >= eventCounter) {
            return (
                new uint256[](0),
                new string[](0),
                new uint256[](0),
                new uint256[](0),
                new uint256[](0),
                new address[](0),
                new string[](0),
                new uint8[](0)
            );
        }
        uint256 length = endIndex - startIndex;
        eventIds = new uint256[](length);
        eventNames = new string[](length);
        maxTickets = new uint256[](length);
        ticketsSold = new uint256[](length);
        eventTimes = new uint256[](length);
        creators = new address[](length);
        baseTokenURIs = new string[](length);
        statuses = new uint8[](length);
        for (uint256 i = 0; i < length; i++) {
            uint256 eventId = startIndex + i + 1;
            Event memory evt = events[eventId];
            eventIds[i] = evt.eventId;
            eventNames[i] = evt.eventName;
            maxTickets[i] = evt.maxTickets;
            ticketsSold[i] = evt.ticketsSold;
            eventTimes[i] = evt.eventTime;
            creators[i] = evt.creator;
            baseTokenURIs[i] = evt.baseTokenURI;
            statuses[i] = evt.status;
        }
        return (
            eventIds,
            eventNames,
            maxTickets,
            ticketsSold,
            eventTimes,
            creators,
            baseTokenURIs,
            statuses
        );
    }

    function searchEventsByName(
        string memory searchTerm
    )
        external
        view
        returns (
            uint256[] memory eventIds,
            string[] memory eventNames,
            uint256[] memory maxTickets,
            uint256[] memory ticketsSold,
            uint256[] memory eventTimes,
            address[] memory creators,
            string[] memory baseTokenURIs,
            uint8[] memory statuses
        )
    {
        uint256 matchCount = 0;
        for (uint256 i = 1; i <= eventCounter; i++) {
            if (events[i].eventName.toLower().contains(searchTerm.toLower())) {
                matchCount++;
            }
        }
        eventIds = new uint256[](matchCount);
        eventNames = new string[](matchCount);
        maxTickets = new uint256[](matchCount);
        ticketsSold = new uint256[](matchCount);
        eventTimes = new uint256[](matchCount);
        creators = new address[](matchCount);
        baseTokenURIs = new string[](matchCount);
        statuses = new uint8[](matchCount);
        uint256 index = 0;
        for (uint256 i = 1; i <= eventCounter; i++) {
            if (events[i].eventName.toLower().contains(searchTerm.toLower())) {
                Event memory evt = events[i];
                eventIds[index] = evt.eventId;
                eventNames[index] = evt.eventName;
                maxTickets[index] = evt.maxTickets;
                ticketsSold[index] = evt.ticketsSold;
                eventTimes[index] = evt.eventTime;
                creators[index] = evt.creator;
                baseTokenURIs[index] = evt.baseTokenURI;
                statuses[index] = evt.status;
                index++;
            }
        }
        return (
            eventIds,
            eventNames,
            maxTickets,
            ticketsSold,
            eventTimes,
            creators,
            baseTokenURIs,
            statuses
        );
    }

    function renounceOwnership() public view override onlyOwner {
        revert();
    }
}
