// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract EventTicketNFT is ERC721, ReentrancyGuard {
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

    mapping(uint256 => Event) public events; // eventId => Event
    mapping(uint256 => uint256) internal ticketToEvent; // tokenId => eventId
    mapping(uint256 => bool) public checkedIn; // tokenId => bool
    mapping(uint256 => uint256) public checkInTimestamps; // tokenId => timestamp
    mapping(address => uint256[]) public ticketsByOwner; // owner => tokenIds
    mapping(uint256 => bool) public isTicketCancelled; // tokenId => true nếu đã bị hủy

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


    constructor() ERC721("EventTicketNFT", "ETN") {}

    function createEvent(
        string memory _eventName,
        uint256 _maxTickets,
        uint256 _eventTime,
        string memory _baseTokenURI
    ) external {
        require(_maxTickets > 0, "Max tickets must be > 0");
        eventCounter++;

        events[eventCounter] = Event({
            eventId: eventCounter,
            eventName: _eventName,
            maxTickets: _maxTickets,
            ticketsSold: 0,
            eventTime: _eventTime,
            creator: msg.sender,
            baseTokenURI: _baseTokenURI,
            status: 1
        });

        emit EventCreated(eventCounter, _eventName, _maxTickets);
    }

    function updateEventStatus(uint256 _eventId, uint8 _newStatus) external {
        require(events[_eventId].creator == msg.sender, "Not event creator");
        require(_newStatus == 0 || _newStatus == 1, "Invalid status");
        events[_eventId].status = _newStatus;
        emit EventStatusUpdated(_eventId, _newStatus);
    }

    function updateBaseTokenURI(
        uint256 _eventId,
        string memory _newURI
    ) external {
        require(events[_eventId].creator == msg.sender, "Not event creator");
        events[_eventId].baseTokenURI = _newURI;
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        uint256 eventId = ticketToEvent[tokenId];
        string memory base = events[eventId].baseTokenURI;
        return string(abi.encodePacked(base));
    }

    function updateEvent(
        uint256 _eventId,
        string memory _newEventName,
        uint256 _newMaxTickets,
        uint256 _newEventTime
    ) external {
        Event storage eventDetails = events[_eventId];

        // Kiểm tra quyền truy cập: chỉ người tạo sự kiện mới có thể cập nhật
        require(
            msg.sender == eventDetails.creator,
            "Only event creator can update the event"
        );

        // Đảm bảo số lượng vé tối đa không thể giảm xuống dưới số vé đã bán
        require(
            _newMaxTickets >= eventDetails.ticketsSold,
            "New max tickets must be >= tickets already sold"
        );

        // Cập nhật các thông tin sự kiện
        eventDetails.eventName = _newEventName;
        eventDetails.maxTickets = _newMaxTickets;
        eventDetails.eventTime = _newEventTime;

        emit EventCreated(_eventId, _newEventName, _newMaxTickets);
    }

    function mintTicket(uint256 _eventId) external nonReentrant {
        Event storage eventDetails = events[_eventId];
        require(eventDetails.eventId != 0, "Event does not exist");
        require(
            block.timestamp < eventDetails.eventTime,
            "Event already started"
        );
        require(
            eventDetails.ticketsSold < eventDetails.maxTickets,
            "All tickets sold"
        );
        require(eventDetails.status == 1, "Event is not active");

        // Không cần kiểm tra vé đã sở hữu trước đó nữa

        ticketIdCounter++;
        uint256 tokenId = ticketIdCounter;

        _safeMint(msg.sender, tokenId);

        ticketToEvent[tokenId] = _eventId;
        ticketsByOwner[msg.sender].push(tokenId);
        eventDetails.ticketsSold++;

        emit TicketMinted(_eventId, tokenId, msg.sender);
    }

    function checkIn(uint256 _tokenId, uint256 _eventId) external {
        // Kiểm tra sự kiện của tokenId
        require(
            ticketToEvent[_tokenId] == _eventId,
            "Token does not belong to this event"
        );

        // Kiểm tra quyền sở hữu vé
        require(ownerOf(_tokenId) == msg.sender, "Not owner of this ticket");

        // Kiểm tra người dùng chưa điểm danh
        require(!checkedIn[_tokenId], "Already checked in");

        // Kiểm tra thời gian sự kiện
        require(
            block.timestamp <= events[_eventId].eventTime + 1 hours,
            "Event is over"
        );
        require(!isTicketCancelled[_tokenId], "Ticket is cancelled");
        require(events[_eventId].status == 1, "Event is not active");

        // Cập nhật trạng thái điểm danh
        checkedIn[_tokenId] = true;
        checkInTimestamps[_tokenId] = block.timestamp;

        // Thông báo sự kiện điểm danh
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
        // Kiểm tra vé có thuộc sự kiện không
        require(ticketToEvent[tokenId] == eventId, "Ticket not for this event");

        // Lấy địa chỉ chủ sở hữu vé
        owner = ownerOf(tokenId);

        // Trả về trạng thái điểm danh và thời gian điểm danh
        checkedInStatus = checkedIn[tokenId];
        timestamp = checkInTimestamps[tokenId];

        // Lấy tên sự kiện tại thời điểm điểm danh
        eventName = events[eventId].eventName;
        eventStatus = events[eventId].status;
    }

    function removeCheckIn(uint256 _eventId, uint256 _tokenId) external {
        // Kiểm tra quyền truy cập: chỉ người tổ chức sự kiện hoặc chủ sở hữu vé mới có thể xóa check-in
        require(
            events[_eventId].creator == msg.sender ||
                ownerOf(_tokenId) == msg.sender,
            "Not event creator or ticket owner"
        );

        require(
            ticketToEvent[_tokenId] == _eventId,
            "Invalid event for ticket"
        );
        require(checkedIn[_tokenId], "Not checked in");

        // Xóa trạng thái check-in
        checkedIn[_tokenId] = false;
        checkInTimestamps[_tokenId] = 0;

        emit CheckInRemoved(_eventId, _tokenId);
    }

    // Lấy tất cả vé của người dùng
    function getMyTickets() external view returns (MyTicketInfo[] memory) {
        uint256[] memory userTickets = ticketsByOwner[msg.sender];
        uint256 length = userTickets.length;
        MyTicketInfo[] memory result = new MyTicketInfo[](length);

        for (uint256 i = 0; i < length; i++) {
            uint256 tokenId = userTickets[i];
            uint256 eventId = ticketToEvent[tokenId];
            bool isCheckedIn = checkedIn[tokenId];
            uint256 time = checkInTimestamps[tokenId];

            result[i] = MyTicketInfo(tokenId, eventId, isCheckedIn, time);
        }

        return result;
    }

    // (Bonus) Lấy vé theo sự kiện của người dùng cụ thể
    function getEventTicketsWithName(
        address user,
        uint256 eventId
    ) external view returns (uint256[] memory, string memory) {
        uint256[] memory allTickets = ticketsByOwner[user];
        uint256 count = 0;

        for (uint256 i = 0; i < allTickets.length; i++) {
            if (ticketToEvent[allTickets[i]] == eventId) {
                count++;
            }
        }

        uint256[] memory filtered = new uint256[](count);
        uint256 j = 0;

        for (uint256 i = 0; i < allTickets.length; i++) {
            uint256 tokenId = allTickets[i];
            if (ticketToEvent[tokenId] == eventId) {
                filtered[j++] = tokenId;
            }
        }

        return (filtered, events[eventId].eventName);
    }

    function cancelTicket(uint256 eventId, uint256 tokenId) external {
        require(ticketToEvent[tokenId] == eventId, "Token not for this event");
        require(events[eventId].creator == msg.sender, "Not event creator");
        require(!isTicketCancelled[tokenId], "Ticket already cancelled");

        isTicketCancelled[tokenId] = true;

        emit TicketCancelled(eventId, tokenId);
    }

   function unCancelTicket(uint256 eventId, uint256 tokenId) external {
        require(ticketToEvent[tokenId] == eventId, "Token not for this event");
        require(events[eventId].creator == msg.sender, "Not event creator");
        require(isTicketCancelled[tokenId], "Ticket is not cancelled");

        isTicketCancelled[tokenId] = false;

        emit TicketUncancelled(eventId, tokenId); // Sửa lại sự kiện
    }
}
