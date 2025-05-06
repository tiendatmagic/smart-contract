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
        string name;
        uint256 maxTix;
        uint256[2] timeRange;
        string baseURI;
        string data;
        uint256 price;
        uint256 catId;
    }

    struct Event {
        uint256 id;
        string name;
        uint256 maxTix;
        uint256 sold;
        uint256 start;
        uint256 end;
        address creator;
        string baseURI;
        uint8 status;
        string data;
        uint256 price;
        uint256 catId;
    }

    struct EventInfo {
        uint256 id;
        string name;
        uint256 maxTix;
        uint256 sold;
        uint256 start;
        uint256 end;
        address creator;
        string baseURI;
        uint8 status;
        string data;
        uint256 price;
        uint256 catId;
        uint256 checked;
        uint256 notChecked;
    }

    struct MyTicketInfo {
        uint256 tokenId;
        uint256 eventId;
        bool checked;
        uint256 checkTime;
    }

    struct AttendeeInfo {
        string name;
        bool gender;
        string email;
        string phone;
    }

    struct TicketInput {
        uint256 eventId;
        string name;
        bool gender;
        string email;
        string phone;
    }

    uint256 public eventCount;
    uint256 public ticketIdCount;
    uint256 public feePercent;

    address private constant DEAD_ADDRESS =
        0x000000000000000000000000000000000000dEaD;

    mapping(uint256 => Event) public events;
    mapping(uint256 => uint256) private _ticketEvent;
    mapping(uint256 => uint256) private _checkTimes;
    mapping(address => uint256[]) private _ownerTickets;
    mapping(uint256 => bool) public isCancelled;
    mapping(uint256 => AttendeeInfo) public attendees;

    event EventCreated(
        uint256 indexed id,
        string name,
        uint256 maxTix,
        string data,
        uint256 price,
        uint256 catId
    );
    event TicketMinted(
        uint256 indexed eventId,
        uint256 indexed ticketId,
        address indexed owner,
        string name,
        bool gender,
        string email,
        string phone
    );
    event CheckedIn(
        uint256 indexed eventId,
        uint256 indexed ticketId,
        address indexed attendee,
        uint256 timestamp
    );
    event CheckInRemoved(uint256 indexed eventId, uint256 indexed ticketId);
    event EventStatusUpdated(uint256 indexed id, uint8 status);
    event TicketCancelled(uint256 indexed eventId, uint256 indexed tokenId);
    event TicketUncancelled(uint256 indexed eventId, uint256 indexed tokenId);
    event PaymentDistributed(
        uint256 indexed eventId,
        address indexed creator,
        uint256 creatorAmt,
        uint256 contractAmt
    );
    event FeePercentUpdated(uint256 oldPercent, uint256 newPercent);
    event TicketRecovered(
        uint256 indexed eventId,
        uint256 indexed tokenId,
        address indexed creator,
        address from
    );

    constructor() ERC721("EventTicketNFT", "ETN") Ownable(msg.sender) {}

    function setFeePercent(uint256 newPercent) external onlyOwner {
        require(newPercent <= 100, "Invalid percent");
        require(newPercent != feePercent, "No change");
        emit FeePercentUpdated(feePercent, newPercent);
        feePercent = newPercent;
    }

    function createEvent(EventInput memory input) external {
        require(input.maxTix > 0, "Invalid ticket count");
        require(bytes(input.name).length > 0, "Name required");
        require(bytes(input.data).length > 0, "Data required");
        require(input.catId >= 1 && input.catId <= 15, "Invalid category");
        require(input.timeRange[1] >= input.timeRange[0], "Invalid time range");

        eventCount++;
        events[eventCount] = Event(
            eventCount,
            input.name,
            input.maxTix,
            0,
            input.timeRange[0],
            input.timeRange[1],
            msg.sender,
            input.baseURI,
            1,
            input.data,
            input.price,
            input.catId
        );
        emit EventCreated(
            eventCount,
            input.name,
            input.maxTix,
            input.data,
            input.price,
            input.catId
        );
    }

    function updateEventStatus(uint256 id, uint8 status) external {
        require(events[id].creator == msg.sender, "Not creator");
        require(status <= 1, "Invalid status");
        events[id].status = status;
        emit EventStatusUpdated(id, status);
    }

    function updateBaseURI(uint256 id, string memory newURI) external {
        require(events[id].creator == msg.sender, "Not creator");
        events[id].baseURI = newURI;
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "Nonexistent token");
        return string(abi.encodePacked(events[_ticketEvent[tokenId]].baseURI));
    }

    function updateEvent(EventInput memory input, uint256 id) external {
        Event storage e = events[id];
        require(msg.sender == e.creator, "Not creator");
        require(input.maxTix >= e.sold, "Invalid ticket count");
        require(bytes(input.name).length > 0, "Name required");
        require(bytes(input.data).length > 0, "Data required");
        require(input.catId >= 1 && input.catId <= 15, "Invalid category");
        require(input.timeRange[1] >= input.timeRange[0], "Invalid time range");

        e.name = input.name;
        e.maxTix = input.maxTix;
        e.start = input.timeRange[0];
        e.end = input.timeRange[1];
        e.baseURI = input.baseURI;
        e.data = input.data;
        e.price = input.price;
        e.catId = input.catId;
        emit EventCreated(
            id,
            input.name,
            input.maxTix,
            input.data,
            input.price,
            input.catId
        );
    }

    function mintTicket(
        TicketInput memory input
    ) external payable nonReentrant {
        Event storage e = events[input.eventId];
        require(e.id != 0, "Nonexistent event");
        require(
            block.timestamp >= e.start && block.timestamp <= e.end,
            "Event inactive"
        );
        require(e.sold < e.maxTix, "Sold out");
        require(e.status == 1, "Event not active");
        require(bytes(input.name).length > 0, "Name required");
        require(bytes(input.email).length > 0, "Email required");
        require(bytes(input.phone).length > 0, "Phone required");

        uint256[] storage userTix = _ownerTickets[msg.sender];
        for (uint256 i = 0; i < userTix.length; i++) {
            uint256 tId = userTix[i];
            if (_ticketEvent[tId] == input.eventId && !isCancelled[tId]) {
                revert("Already owns ticket");
            }
        }

        if (e.price > 0) {
            require(msg.value >= e.price, "Insufficient payment");
            uint256 contractAmt = (e.price * feePercent) / 100;
            uint256 creatorAmt = e.price - contractAmt;

            (bool success, ) = e.creator.call{value: creatorAmt}("");
            require(success, "Payment failed");

            emit PaymentDistributed(
                input.eventId,
                e.creator,
                creatorAmt,
                contractAmt
            );

            if (msg.value > e.price) {
                payable(msg.sender).transfer(msg.value - e.price);
            }
        }

        uint256 tokenId = ++ticketIdCount;
        _safeMint(msg.sender, tokenId);
        _ticketEvent[tokenId] = input.eventId;
        userTix.push(tokenId);
        e.sold++;
        attendees[tokenId] = AttendeeInfo(
            input.name,
            input.gender,
            input.email,
            input.phone
        );
        emit TicketMinted(
            input.eventId,
            tokenId,
            msg.sender,
            input.name,
            input.gender,
            input.email,
            input.phone
        );
    }

    function checkIn(uint256 tokenId) external {
        require(_ownerOf(tokenId) != address(0), "Nonexistent token");
        uint256 eventId = _ticketEvent[tokenId];
        require(ownerOf(tokenId) == msg.sender, "Not owner");
        require(_checkTimes[tokenId] == 0, "Already checked in");
        require(!isCancelled[tokenId], "Ticket cancelled");
        require(events[eventId].status == 1, "Event not active");
        require(
            block.timestamp >= events[eventId].start &&
                block.timestamp <= events[eventId].end + 1 hours,
            "Check-in closed"
        );

        _checkTimes[tokenId] = block.timestamp;
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
            bool checked,
            uint256 timestamp,
            string memory name,
            uint8 status,
            AttendeeInfo memory attendee,
            bool cancelled
        )
    {
        require(_ownerOf(tokenId) != address(0), "Nonexistent token");
        eventId = _ticketEvent[tokenId];
        Event storage e = events[eventId];
        owner = ownerOf(tokenId);
        checked = _checkTimes[tokenId] > 0;
        timestamp = _checkTimes[tokenId];
        name = e.name;
        status = e.status;
        attendee = attendees[tokenId];
        cancelled = isCancelled[tokenId];
    }

    function removeCheckIn(uint256 tokenId) external {
        require(_ownerOf(tokenId) != address(0), "Nonexistent token");
        uint256 eventId = _ticketEvent[tokenId];
        require(
            events[eventId].creator == msg.sender ||
                ownerOf(tokenId) == msg.sender,
            "Not authorized"
        );
        require(_checkTimes[tokenId] > 0, "Not checked in");

        _checkTimes[tokenId] = 0;
        emit CheckInRemoved(eventId, tokenId);
    }

    function getMyTickets()
        external
        view
        returns (MyTicketInfo[] memory, AttendeeInfo[] memory)
    {
        uint256[] memory userTix = _ownerTickets[msg.sender];
        MyTicketInfo[] memory tixInfo = new MyTicketInfo[](userTix.length);
        AttendeeInfo[] memory attendeeInfo = new AttendeeInfo[](userTix.length);

        for (uint256 i = 0; i < userTix.length; i++) {
            uint256 tokenId = userTix[i];
            tixInfo[i] = MyTicketInfo(
                tokenId,
                _ticketEvent[tokenId],
                _checkTimes[tokenId] > 0,
                _checkTimes[tokenId]
            );
            attendeeInfo[i] = attendees[tokenId];
        }
        return (tixInfo, attendeeInfo);
    }

    function getEventTicketsWithName(
        address user,
        uint256 eventId
    )
        external
        view
        returns (uint256[] memory, string memory, AttendeeInfo[] memory)
    {
        uint256[] memory allTix = _ownerTickets[user];
        uint256 count;
        for (uint256 i = 0; i < allTix.length; i++) {
            if (_ticketEvent[allTix[i]] == eventId) count++;
        }

        uint256[] memory filtered = new uint256[](count);
        AttendeeInfo[] memory attendeeInfo = new AttendeeInfo[](count);
        uint256 j;
        for (uint256 i = 0; i < allTix.length; i++) {
            if (_ticketEvent[allTix[i]] == eventId) {
                filtered[j] = allTix[i];
                attendeeInfo[j] = attendees[allTix[i]];
                j++;
            }
        }
        return (filtered, events[eventId].name, attendeeInfo);
    }

    function cancelTicket(uint256 tokenId) external {
        require(_ownerOf(tokenId) != address(0), "Nonexistent token");
        uint256 eventId = _ticketEvent[tokenId];
        require(events[eventId].creator == msg.sender, "Not creator");
        require(!isCancelled[tokenId], "Already cancelled");

        isCancelled[tokenId] = true;
        emit TicketCancelled(eventId, tokenId);
    }

    function unCancelTicket(uint256 tokenId) external {
        require(_ownerOf(tokenId) != address(0), "Nonexistent token");
        uint256 eventId = _ticketEvent[tokenId];
        require(events[eventId].creator == msg.sender, "Not creator");
        require(isCancelled[tokenId], "Not cancelled");

        isCancelled[tokenId] = false;
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
        address token,
        uint256 amount
    ) external onlyOwner nonReentrant {
        require(amount > 0, "Invalid amount");
        IERC20 erc20 = IERC20(token);
        require(
            amount <= erc20.balanceOf(address(this)),
            "Insufficient balance"
        );
        require(erc20.transfer(owner(), amount), "Transfer failed");
    }

    function getEventInfo(uint256 id) external view returns (EventInfo memory) {
        Event storage e = events[id];
        require(e.id != 0, "Nonexistent event");
        uint256 checkedCount;
        for (uint256 i = 1; i <= ticketIdCount; i++) {
            if (_ticketEvent[i] == id && _checkTimes[i] > 0) {
                checkedCount++;
            }
        }
        return
            EventInfo(
                e.id,
                e.name,
                e.maxTix,
                e.sold,
                e.start,
                e.end,
                e.creator,
                e.baseURI,
                e.status,
                e.data,
                e.price,
                e.catId,
                checkedCount,
                e.sold - checkedCount
            );
    }

    function getEventsByPage(
        uint256 page,
        uint8 status,
        uint256 catId
    ) external view returns (EventInfo[] memory) {
        require(page > 0, "Invalid page");
        require(status <= 1, "Invalid status");

        EventInfo[] memory details = new EventInfo[](10);
        uint256 count;
        uint256 processed;
        uint256 startIdx = (page - 1) * 10;

        for (uint256 i = eventCount; i >= 1 && count < 10; i--) {
            Event storage e = events[i];
            if (
                e.id != 0 &&
                e.status == status &&
                (catId == 0 || e.catId == catId)
            ) {
                if (++processed > startIdx) {
                    uint256 checkedCount;
                    for (uint256 j = 1; j <= ticketIdCount; j++) {
                        if (_ticketEvent[j] == i && _checkTimes[j] > 0) {
                            checkedCount++;
                        }
                    }
                    details[count] = EventInfo(
                        e.id,
                        e.name,
                        e.maxTix,
                        e.sold,
                        e.start,
                        e.end,
                        e.creator,
                        e.baseURI,
                        e.status,
                        e.data,
                        e.price,
                        e.catId,
                        checkedCount,
                        e.sold - checkedCount
                    );
                    count++;
                }
            }
            if (i == 1) break;
        }
        return details;
    }

    function searchEventsByName(
        uint256 page,
        uint8 status,
        string memory term
    ) external view returns (EventInfo[] memory) {
        require(page > 0, "Invalid page");
        require(status <= 1, "Invalid status");

        EventInfo[] memory details = new EventInfo[](10);
        uint256 count;
        uint256 processed;
        uint256 startIdx = (page - 1) * 10;
        string memory lowerTerm = term.toLower();

        for (uint256 i = eventCount; i >= 1 && count < 10; i--) {
            Event storage e = events[i];
            if (e.status == status && e.name.toLower().contains(lowerTerm)) {
                if (++processed > startIdx) {
                    uint256 checkedCount;
                    for (uint256 j = 1; j <= ticketIdCount; j++) {
                        if (_ticketEvent[j] == i && _checkTimes[j] > 0) {
                            checkedCount++;
                        }
                    }
                    details[count] = EventInfo(
                        e.id,
                        e.name,
                        e.maxTix,
                        e.sold,
                        e.start,
                        e.end,
                        e.creator,
                        e.baseURI,
                        e.status,
                        e.data,
                        e.price,
                        e.catId,
                        checkedCount,
                        e.sold - checkedCount
                    );
                    count++;
                }
            }
            if (i == 1) break;
        }
        return details;
    }

    function recoverTicket(uint256 tokenId) external nonReentrant {
        require(_ownerOf(tokenId) != address(0), "Nonexistent token");
        uint256 eventId = _ticketEvent[tokenId];
        require(events[eventId].creator == msg.sender, "Not creator");
        address owner = ownerOf(tokenId);
        require(owner == DEAD_ADDRESS, "Not in dead address");

        uint256[] storage ownerTix = _ownerTickets[owner];
        for (uint256 i = 0; i < ownerTix.length; i++) {
            if (ownerTix[i] == tokenId) {
                ownerTix[i] = ownerTix[ownerTix.length - 1];
                ownerTix.pop();
                break;
            }
        }

        _transfer(owner, msg.sender, tokenId);
        _ownerTickets[msg.sender].push(tokenId);
        emit TicketRecovered(eventId, tokenId, msg.sender, owner);
    }

    function getTicketsByEventAndPage(
        uint256 eventId,
        uint256 page
    ) external view returns (string[] memory) {
        require(events[eventId].id != 0, "Nonexistent event");
        require(page > 0, "Invalid page");

        string[] memory details = new string[](10);
        uint256 count;
        uint256 processed;
        uint256 startIdx = (page - 1) * 10;

        for (uint256 i = ticketIdCount; i >= 1 && count < 10; i--) {
            if (_ticketEvent[i] == eventId) {
                if (++processed > startIdx) {
                    address owner = _ownerOf(i);
                    AttendeeInfo memory attendee = attendees[i];
                    details[count] = string(
                        abi.encodePacked(
                            _uintToString(i),
                            ",",
                            _uintToString(eventId),
                            ",",
                            _addressToString(owner),
                            ",",
                            attendee.name,
                            ",",
                            attendee.gender ? "1" : "0",
                            ",",
                            attendee.email,
                            ",",
                            attendee.phone,
                            ",",
                            _checkTimes[i] > 0 ? "1" : "0",
                            ",",
                            _uintToString(_checkTimes[i]),
                            ",",
                            isCancelled[i] ? "1" : "0"
                        )
                    );
                    count++;
                }
            }
            if (i == 1) break;
        }
        return details;
    }

    function getTotalEventsByAllCategories()
        external
        view
        returns (uint256[15] memory)
    {
        uint256[15] memory totals;
        for (uint256 catId = 1; catId <= 15; catId++) {
            uint256 total = 0;
            for (uint256 i = 1; i <= eventCount; i++) {
                if (events[i].id != 0 && events[i].catId == catId) {
                    total++;
                }
            }
            totals[catId - 1] = total;
        }
        return totals;
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
            uint256[] storage fromTix = _ownerTickets[from];
            for (uint256 i = 0; i < fromTix.length; i++) {
                if (fromTix[i] == tokenId) {
                    fromTix[i] = fromTix[fromTix.length - 1];
                    fromTix.pop();
                    break;
                }
            }
        }

        if (to != address(0)) {
            _ownerTickets[to].push(tokenId);
        }

        return from;
    }

    function renounceOwnership() public view override onlyOwner {
        revert("Cannot renounce");
    }
}
