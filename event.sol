// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library StrUtil {
    function toLower(string memory s) internal pure returns (string memory) {
        bytes memory b = bytes(s);
        for (uint i = 0; i < b.length; i++) {
            uint8 c = uint8(b[i]);
            if (c >= 65 && c <= 90) {
                b[i] = bytes1(c + 32);
            }
        }
        return string(b);
    }

    function contains(
        string memory w,
        string memory sub
    ) internal pure returns (bool) {
        bytes memory wb = bytes(w);
        bytes memory sb = bytes(sub);
        if (sb.length > wb.length) return false;

        for (uint i = 0; i <= wb.length - sb.length; i++) {
            bool f = true;
            for (uint j = 0; j < sb.length; j++) {
                if (wb[i + j] != sb[j]) {
                    f = false;
                    break;
                }
            }
            if (f) return true;
        }
        return false;
    }
}

contract EventTicketNFT is ERC721, ReentrancyGuard, Ownable {
    using StrUtil for string;

    struct EvInp {
        string name;
        uint maxTix;
        uint[2] time;
        string tokenURI;
        string data;
        uint price;
        uint catId;
    }

    struct Ev {
        uint id;
        string name;
        uint maxTix;
        uint sold;
        uint start;
        uint end;
        address creator;
        string tokenURI;
        uint8 status;
        string data;
        uint price;
        uint catId;
    }

    struct TixInfo {
        uint tixId;
        uint evId;
        bool checked;
        uint checkTime;
    }

    struct AttInfo {
        string name;
        bool gender;
        string email;
        string phone;
    }

    struct TixInp {
        uint evId;
        string name;
        bool gender;
        string email;
        string phone;
    }

    struct EventInfo {
        uint id;
        string name;
        uint maxTix;
        uint sold;
        uint start;
        uint end;
        address creator;
        string tokenURI;
        uint8 status;
        string data;
        uint price;
        uint catId;
        uint checked;
        uint notChecked;
    }

    uint public evCount;
    uint public tixCount;
    uint public feePct;

    address private constant DEAD = 0x000000000000000000000000000000000000dEaD;

    mapping(uint => Ev) public evs;
    mapping(uint => uint) private tixToEv;
    mapping(uint => uint) private checkTimes;
    mapping(address => uint[]) private tixByOwn;
    mapping(uint => bool) public tixCancel;
    mapping(uint => AttInfo) public attInfo;

    event EventCreated(
        uint indexed evId,
        string name,
        uint maxTix,
        string data,
        uint price,
        uint catId
    );
    event TicketMinted(
        uint indexed evId,
        uint indexed tixId,
        address indexed owner,
        string name,
        bool gender,
        string email,
        string phone
    );
    event CheckedIn(
        uint indexed evId,
        uint indexed tixId,
        address indexed att,
        uint time
    );
    event CheckInRemoved(uint indexed evId, uint indexed tixId);
    event EventStatusUpdated(uint indexed evId, uint8 status);
    event TicketCancelled(uint indexed evId, uint indexed tixId);
    event TicketUncancelled(uint indexed evId, uint indexed tixId);
    event PaymentDistributed(
        uint indexed evId,
        address indexed creator,
        uint creatorAmt,
        uint feeAmt
    );
    event ContractPercentageUpdated(uint oldPct, uint newPct);
    event TicketRecovered(
        uint indexed evId,
        uint indexed tixId,
        address indexed creator,
        address from
    );

    constructor() ERC721("EventTicketNFT", "ETN") Ownable(msg.sender) {}

    function setContractPercentage(uint newPct) external onlyOwner {
        require(newPct <= 100, "Invalid percentage");
        require(newPct != feePct, "No change");
        emit ContractPercentageUpdated(feePct, newPct);
        feePct = newPct;
    }

    function createEvent(EvInp memory inp) external {
        require(inp.maxTix > 0, "Invalid ticket count");
        require(bytes(inp.name).length > 0, "Name required");
        require(bytes(inp.data).length > 0, "Data required");
        require(inp.catId >= 1 && inp.catId <= 15, "Invalid category");
        require(inp.time[1] >= inp.time[0], "Invalid time range");

        evCount++;
        evs[evCount] = Ev(
            evCount,
            inp.name,
            inp.maxTix,
            0,
            inp.time[0],
            inp.time[1],
            msg.sender,
            inp.tokenURI,
            1,
            inp.data,
            inp.price,
            inp.catId
        );
        emit EventCreated(
            evCount,
            inp.name,
            inp.maxTix,
            inp.data,
            inp.price,
            inp.catId
        );
    }

    function updateEventStatus(uint evId, uint8 status) external {
        require(evs[evId].creator == msg.sender, "Not creator");
        require(status <= 1, "Invalid status");
        evs[evId].status = status;
        emit EventStatusUpdated(evId, status);
    }

    function updateBaseTokenURI(uint evId, string memory newURI) external {
        require(evs[evId].creator == msg.sender, "Not creator");
        evs[evId].tokenURI = newURI;
    }

    function tokenURI(uint tixId) public view override returns (string memory) {
        require(_ownerOf(tixId) != address(0), "Nonexistent token");
        return string(abi.encodePacked(evs[tixToEv[tixId]].tokenURI));
    }

    function updateEvent(EvInp memory inp, uint evId) external {
        Ev storage e = evs[evId];
        require(msg.sender == e.creator, "Not creator");
        require(inp.maxTix >= e.sold, "Invalid ticket count");
        require(bytes(inp.name).length > 0, "Name required");
        require(bytes(inp.data).length > 0, "Data required");
        require(inp.catId >= 1 && inp.catId <= 15, "Invalid category");
        require(inp.time[1] >= inp.time[0], "Invalid time range");

        e.name = inp.name;
        e.maxTix = inp.maxTix;
        e.start = inp.time[0];
        e.end = inp.time[1];
        e.tokenURI = inp.tokenURI;
        e.data = inp.data;
        e.price = inp.price;
        e.catId = inp.catId;
        emit EventCreated(
            evId,
            inp.name,
            inp.maxTix,
            inp.data,
            inp.price,
            inp.catId
        );
    }

    function mintTicket(TixInp memory inp) external payable nonReentrant {
        Ev storage e = evs[inp.evId];
        require(e.id != 0, "Nonexistent event");
        require(
            block.timestamp >= e.start && block.timestamp <= e.end,
            "Event inactive"
        );
        require(e.sold < e.maxTix, "Sold out");
        require(e.status == 1, "Event not active");
        require(bytes(inp.name).length > 0, "Name required");
        require(bytes(inp.email).length > 0, "Email required");
        require(bytes(inp.phone).length > 0, "Phone required");

        uint[] storage usrTix = tixByOwn[msg.sender];
        for (uint i = 0; i < usrTix.length; i++) {
            uint existingTixId = usrTix[i];
            if (
                tixToEv[existingTixId] == inp.evId && !tixCancel[existingTixId]
            ) {
                revert("Already owns ticket");
            }
        }

        if (e.price > 0) {
            require(msg.value >= e.price, "Insufficient payment");
            uint feeAmt = (e.price * feePct) / 100;
            uint creatorAmt = e.price - feeAmt;

            (bool ok, ) = e.creator.call{value: creatorAmt}("");
            require(ok, "Payment failed");

            emit PaymentDistributed(inp.evId, e.creator, creatorAmt, feeAmt);

            if (msg.value > e.price) {
                payable(msg.sender).transfer(msg.value - e.price);
            }
        }

        uint tixId = ++tixCount;
        _safeMint(msg.sender, tixId);
        tixToEv[tixId] = inp.evId;
        usrTix.push(tixId);
        e.sold++;
        attInfo[tixId] = AttInfo(inp.name, inp.gender, inp.email, inp.phone);
        emit TicketMinted(
            inp.evId,
            tixId,
            msg.sender,
            inp.name,
            inp.gender,
            inp.email,
            inp.phone
        );
    }

    function checkIn(uint tixId) external {
        require(_ownerOf(tixId) != address(0), "Nonexistent token");
        uint evId = tixToEv[tixId];
        require(ownerOf(tixId) == msg.sender, "Not owner");
        require(checkTimes[tixId] == 0, "Already checked in");
        require(!tixCancel[tixId], "Ticket cancelled");
        require(evs[evId].status == 1, "Event not active");
        require(
            block.timestamp >= evs[evId].start &&
                block.timestamp <= evs[evId].end + 1 hours,
            "Check-in closed"
        );

        checkTimes[tixId] = block.timestamp;
        emit CheckedIn(evId, tixId, msg.sender, block.timestamp);
    }

    function getTicketInfo(
        uint tixId
    )
        external
        view
        returns (
            uint evId,
            address own,
            bool checked,
            uint time,
            string memory name,
            uint8 status,
            AttInfo memory att,
            bool cancelled
        )
    {
        require(_ownerOf(tixId) != address(0), "Nonexistent token");
        evId = tixToEv[tixId];
        Ev storage e = evs[evId];
        own = ownerOf(tixId);
        checked = checkTimes[tixId] > 0;
        time = checkTimes[tixId];
        name = e.name;
        status = e.status;
        att = attInfo[tixId];
        cancelled = tixCancel[tixId];
    }

    function removeCheckIn(uint tixId) external {
        require(_ownerOf(tixId) != address(0), "Nonexistent token");
        uint evId = tixToEv[tixId];
        require(
            evs[evId].creator == msg.sender || ownerOf(tixId) == msg.sender,
            "Not authorized"
        );
        require(checkTimes[tixId] > 0, "Not checked in");

        checkTimes[tixId] = 0;
        emit CheckInRemoved(evId, tixId);
    }

    function getMyTickets()
        external
        view
        returns (TixInfo[] memory, AttInfo[] memory)
    {
        uint[] memory usrTix = tixByOwn[msg.sender];
        TixInfo[] memory tixInf = new TixInfo[](usrTix.length);
        AttInfo[] memory attDet = new AttInfo[](usrTix.length);

        for (uint i = 0; i < usrTix.length; i++) {
            uint tixId = usrTix[i];
            tixInf[i] = TixInfo(
                tixId,
                tixToEv[tixId],
                checkTimes[tixId] > 0,
                checkTimes[tixId]
            );
            attDet[i] = attInfo[tixId];
        }
        return (tixInf, attDet);
    }

    function getEventTicketsWithName(
        address usr,
        uint evId
    ) external view returns (uint[] memory, string memory, AttInfo[] memory) {
        uint[] memory allTix = tixByOwn[usr];
        uint cnt;
        for (uint i = 0; i < allTix.length; i++) {
            if (tixToEv[allTix[i]] == evId) cnt++;
        }

        uint[] memory filt = new uint[](cnt);
        AttInfo[] memory atts = new AttInfo[](cnt);
        uint j;
        for (uint i = 0; i < allTix.length; i++) {
            if (tixToEv[allTix[i]] == evId) {
                filt[j] = allTix[i];
                atts[j] = attInfo[allTix[i]];
                j++;
            }
        }
        return (filt, evs[evId].name, atts);
    }

    function cancelTicket(uint tixId) external {
        require(_ownerOf(tixId) != address(0), "Nonexistent token");
        uint evId = tixToEv[tixId];
        require(evs[evId].creator == msg.sender, "Not creator");
        require(!tixCancel[tixId], "Already cancelled");

        tixCancel[tixId] = true;
        emit TicketCancelled(evId, tixId);
    }

    function unCancelTicket(uint tixId) external {
        require(_ownerOf(tixId) != address(0), "Nonexistent token");
        uint evId = tixToEv[tixId];
        require(evs[evId].creator == msg.sender, "Not creator");
        require(tixCancel[tixId], "Not cancelled");

        tixCancel[tixId] = false;
        emit TicketUncancelled(evId, tixId);
    }

    function withdrawTokenNative(uint amt) external onlyOwner nonReentrant {
        require(amt > 0 && amt <= address(this).balance, "Invalid amount");
        payable(owner()).transfer(amt);
    }

    function withdrawToken(
        address tok,
        uint amt
    ) external onlyOwner nonReentrant {
        require(amt > 0, "Invalid amount");
        IERC20 t = IERC20(tok);
        require(amt <= t.balanceOf(address(this)), "Insufficient balance");
        require(t.transfer(owner(), amt), "Transfer failed");
    }

    function getCheckInStats(uint evId) internal view returns (uint checked, uint notChecked) {
        checked = 0;
        for (uint j = 1; j <= tixCount; j++) {
            if (tixToEv[j] == evId && checkTimes[j] > 0) {
                checked++;
            }
        }
        notChecked = evs[evId].sold - checked;
    }

    function getEventInfo(uint evId) external view returns (EventInfo memory) {
        Ev storage e = evs[evId];
        require(e.id != 0, "Nonexistent event");

        (uint checked, uint notChecked) = getCheckInStats(evId);

        return EventInfo(
            e.id,
            e.name,
            e.maxTix,
            e.sold,
            e.start,
            e.end,
            e.creator,
            e.tokenURI,
            e.status,
            e.data,
            e.price,
            e.catId,
            checked,
            notChecked
        );
    }

    function getEventsByPage(
        uint pg,
        uint8 status,
        uint catId
    ) external view returns (EventInfo[] memory) {
        require(pg > 0, "Invalid page");
        require(status <= 1, "Invalid status");

        EventInfo[] memory evDet = new EventInfo[](10);
        uint cnt;
        uint proc;
        uint start = (pg - 1) * 10;

        for (uint i = evCount; i >= 1 && cnt < 10; i--) {
            if (
                evs[i].id != 0 &&
                evs[i].status == status &&
                (catId == 0 || evs[i].catId == catId)
            ) {
                if (++proc > start) {
                    (uint checked, uint notChecked) = getCheckInStats(evs[i].id);
                    evDet[cnt++] = EventInfo(
                        evs[i].id,
                        evs[i].name,
                        evs[i].maxTix,
                        evs[i].sold,
                        evs[i].start,
                        evs[i].end,
                        evs[i].creator,
                        evs[i].tokenURI,
                        evs[i].status,
                        evs[i].data,
                        evs[i].price,
                        evs[i].catId,
                        checked,
                        notChecked
                    );
                }
            }
            if (i == 1) break;
        }
        return evDet;
    }

    function searchEventsByName(
        uint pg,
        uint8 status,
        string memory term
    ) external view returns (EventInfo[] memory) {
        require(pg > 0, "Invalid page");
        require(status <= 1, "Invalid status");

        EventInfo[] memory evDet = new EventInfo[](10);
        uint cnt;
        uint proc;
        uint start = (pg - 1) * 10;
        string memory lowTerm = term.toLower();

        for (uint i = evCount; i >= 1 && cnt < 10; i--) {
            if (
                evs[i].status == status &&
                evs[i].name.toLower().contains(lowTerm)
            ) {
                if (++proc > start) {
                    (uint checked, uint notChecked) = getCheckInStats(evs[i].id);
                    evDet[cnt++] = EventInfo(
                        evs[i].id,
                        evs[i].name,
                        evs[i].maxTix,
                        evs[i].sold,
                        evs[i].start,
                        evs[i].end,
                        evs[i].creator,
                        evs[i].tokenURI,
                        evs[i].status,
                        evs[i].data,
                        evs[i].price,
                        evs[i].catId,
                        checked,
                        notChecked
                    );
                }
            }
            if (i == 1) break;
        }
        return evDet;
    }

    function recoverTicket(uint tixId) external nonReentrant {
        require(_ownerOf(tixId) != address(0), "Nonexistent token");
        uint evId = tixToEv[tixId];
        require(evs[evId].creator == msg.sender, "Not creator");
        address own = ownerOf(tixId);
        require(own == DEAD, "Not in dead address");

        uint[] storage ownTix = tixByOwn[own];
        for (uint i = 0; i < ownTix.length; i++) {
            if (ownTix[i] == tixId) {
                ownTix[i] = ownTix[ownTix.length - 1];
                ownTix.pop();
                break;
            }
        }

        _transfer(own, msg.sender, tixId);
        tixByOwn[msg.sender].push(tixId);
        emit TicketRecovered(evId, tixId, msg.sender, own);
    }

    function getTicketsByEventAndPage(
        uint evId,
        uint pg
    ) external view returns (string[] memory) {
        require(evs[evId].id != 0, "Nonexistent event");
        require(pg > 0, "Invalid page");

        string[] memory tixDet = new string[](10);
        uint cnt;
        uint proc;
        uint start = (pg - 1) * 10;

        for (uint i = tixCount; i >= 1 && cnt < 10; i--) {
            if (tixToEv[i] == evId) {
                if (++proc > start) {
                    address own = _ownerOf(i);
                    AttInfo memory att = attInfo[i];
                    tixDet[cnt++] = string(
                        abi.encodePacked(
                            _uintToStr(i),
                            ",",
                            _uintToStr(evId),
                            ",",
                            _addrToStr(own),
                            ",",
                            att.name,
                            ",",
                            att.gender ? "1" : "0",
                            ",",
                            att.email,
                            ",",
                            att.phone,
                            ",",
                            checkTimes[i] > 0 ? "1" : "0",
                            ",",
                            _uintToStr(checkTimes[i]),
                            ",",
                            tixCancel[i] ? "1" : "0"
                        )
                    );
                }
            }
            if (i == 1) break;
        }
        return tixDet;
    }

    function getTotalEventsByAllCategories()
        external
        view
        returns (uint[15] memory)
    {
        uint[15] memory tot;
        for (uint catId = 1; catId <= 15; catId++) {
            uint t = 0;
            for (uint i = 1; i <= evCount; i++) {
                if (evs[i].id != 0 && evs[i].catId == catId) {
                    t++;
                }
            }
            tot[catId - 1] = t;
        }
        return tot;
    }

    function _uintToStr(uint v) private pure returns (string memory) {
        if (v == 0) return "0";
        uint t = v;
        uint d;
        while (t != 0) {
            d++;
            t /= 10;
        }
        bytes memory buf = new bytes(d);
        while (v != 0) {
            buf[--d] = bytes1(uint8(48 + (v % 10)));
            v /= 10;
        }
        return string(buf);
    }

    function _addrToStr(address a) private pure returns (string memory) {
        bytes memory alpha = "0123456789abcdef";
        bytes memory s = new bytes(42);
        s[0] = "0";
        s[1] = "x";
        for (uint i = 0; i < 20; i++) {
            uint8 shift = uint8(8 * (19 - i));
            s[2 + i * 2] = alpha[uint8(uint160(a) >> shift) & 0xf];
            s[3 + i * 2] = alpha[uint8(uint160(a) >> (shift + 4)) & 0xf];
        }
        return string(s);
    }

    function _update(
        address to,
        uint tixId,
        address auth
    ) internal override returns (address) {
        address from = super._update(to, tixId, auth);

        if (from != address(0)) {
            uint[] storage fromTix = tixByOwn[from];
            for (uint i = 0; i < fromTix.length; i++) {
                if (fromTix[i] == tixId) {
                    fromTix[i] = fromTix[fromTix.length - 1];
                    fromTix.pop();
                    break;
                }
            }
        }

        if (to != address(0)) {
            tixByOwn[to].push(tixId);
        }

        return from;
    }

    function renounceOwnership() public view override onlyOwner {
        revert("Cannot renounce");
    }
}
