// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library StrUtil {
    function toLower(string memory s) internal pure returns (string memory) {
        bytes memory b = bytes(s);
        for (uint256 i = 0; i < b.length; i++) {
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

        for (uint256 i = 0; i <= wb.length - sb.length; i++) {
            bool f = true;
            for (uint256 j = 0; j < sb.length; j++) {
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

    struct EvIn {
        string name;
        uint256 maxTix;
        uint256[2] time;
        string uri;
        string data;
        uint256 price;
        uint256 catId;
    }

    struct Ev {
        uint256 id;
        string name;
        uint256 maxTix;
        uint256 sold;
        uint256 start;
        uint256 end;
        address creator;
        string uri;
        uint8 status;
        string data;
        uint256 price;
        uint256 catId;
    }

    struct TixInfo {
        uint256 tId;
        uint256 eId;
        bool checked;
        uint256 checkTime;
    }

    struct AttInfo {
        string name;
        bool gender;
        string email;
        string phone;
    }

    struct TixIn {
        uint256 eId;
        string name;
        bool gender;
        string email;
        string phone;
    }

    uint256 public feePct;
    uint256 public eCnt;
    uint256 public tIdCnt;

    address private constant DEAD = 0x000000000000000000000000000000000000dEaD;

    mapping(uint256 => Ev) public evs;
    mapping(uint256 => uint256) private tToE;
    mapping(uint256 => uint256) private checkTs;
    mapping(address => uint256[]) private tByOwn;
    mapping(uint256 => bool) public tCancel;
    mapping(uint256 => AttInfo) public attInfo;

    event EventCreated(
        uint256 indexed eId,
        string name,
        uint256 maxTix,
        string data,
        uint256 price,
        uint256 catId
    );

    event EventUpdated(
        uint256 indexed eId,
        string name,
        uint256 maxTix,
        string data,
        uint256 price,
        uint256 catId
    );

    event TicketMinted(
        uint256 indexed eId,
        uint256 indexed tId,
        address indexed own,
        string name,
        bool gender,
        string email,
        string phone
    );

    event CheckedIn(
        uint256 indexed eId,
        uint256 indexed tId,
        address indexed att,
        uint256 ts
    );

    event CheckInRemoved(uint256 indexed eId, uint256 indexed tId);
    event EventStatusUpdated(uint256 indexed eId, uint8 status);
    event TicketCancelled(uint256 indexed eId, uint256 indexed tId);
    event TicketUncancelled(uint256 indexed eId, uint256 indexed tId);
    event PaymentDistributed(
        uint256 indexed eId,
        address indexed creator,
        uint256 creatorAmt,
        uint256 contractAmt
    );
    event ContractPercentageUpdated(uint256 oldPct, uint256 newPct);
    event TicketRecovered(
        uint256 indexed eId,
        uint256 indexed tId,
        address indexed creator,
        address from
    );
    event TicketProfileUpdated(
        uint256 indexed tId,
        address indexed owner,
        string name,
        bool gender,
        string email,
        string phone
    );

    constructor() ERC721("EventTicketNFT", "ETN") Ownable(msg.sender) {}

    function setContractPercentage(uint256 newPct) external onlyOwner {
        require(newPct <= 100, "Invalid percentage");
        require(newPct != feePct, "No change");
        emit ContractPercentageUpdated(feePct, newPct);
        feePct = newPct;
    }

    function createEvent(EvIn memory inp) external {
        require(inp.maxTix > 0, "Invalid ticket count");
        require(bytes(inp.name).length > 0, "Name required");
        require(bytes(inp.data).length > 0, "Data required");
        require(inp.catId >= 1 && inp.catId <= 15, "Invalid category");
        require(inp.time[1] >= inp.time[0], "Invalid time range");

        eCnt++;
        evs[eCnt] = Ev(
            eCnt,
            inp.name,
            inp.maxTix,
            0,
            inp.time[0],
            inp.time[1],
            msg.sender,
            inp.uri,
            1,
            inp.data,
            inp.price,
            inp.catId
        );

        emit EventCreated(
            eCnt,
            inp.name,
            inp.maxTix,
            inp.data,
            inp.price,
            inp.catId
        );
    }

    function updateEvent(EvIn memory inp, uint256 eId) external {
        Ev storage e = evs[eId];
        require(e.id != 0, "Nonexistent event");
        require(msg.sender == e.creator, "Not creator");
        require(inp.maxTix >= e.sold, "Invalid ticket count");
        require(bytes(inp.name).length > 0, "Name required");
        require(bytes(inp.data).length > 0, "Data required");
        require(inp.catId >= 1 && inp.catId <= 15, "Invalid category");
        require(inp.time[1] >= inp.time[0], "Invalid time range");

        bool hasChanges = keccak256(abi.encodePacked(e.name)) !=
            keccak256(abi.encodePacked(inp.name)) ||
            e.maxTix != inp.maxTix ||
            e.start != inp.time[0] ||
            e.end != inp.time[1] ||
            keccak256(abi.encodePacked(e.uri)) !=
            keccak256(abi.encodePacked(inp.uri)) ||
            keccak256(abi.encodePacked(e.data)) !=
            keccak256(abi.encodePacked(inp.data)) ||
            e.price != inp.price ||
            e.catId != inp.catId;
        require(hasChanges, "No changes detected");

        e.name = inp.name;
        e.maxTix = inp.maxTix;
        e.start = inp.time[0];
        e.end = inp.time[1];
        e.uri = inp.uri;
        e.data = inp.data;
        e.price = inp.price;
        e.catId = inp.catId;

        emit EventUpdated(
            eId,
            inp.name,
            inp.maxTix,
            inp.data,
            inp.price,
            inp.catId
        );
    }

    function updateEventStatus(uint256 eId, uint8 status) external {
        require(evs[eId].creator == msg.sender, "Not creator");
        require(status <= 1, "Invalid status");
        evs[eId].status = status;
        emit EventStatusUpdated(eId, status);
    }

    function updateBaseTokenURI(uint256 eId, string memory newURI) external {
        require(evs[eId].creator == msg.sender, "Not creator");
        evs[eId].uri = newURI;
    }

    function tokenURI(
        uint256 tId
    ) public view override returns (string memory) {
        require(_ownerOf(tId) != address(0), "Nonexistent token");
        return string(abi.encodePacked(evs[tToE[tId]].uri));
    }

    function mintTicket(TixIn memory inp) external payable nonReentrant {
        Ev storage e = evs[inp.eId];
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

        uint256[] memory uTix = tByOwn[msg.sender];
        for (uint256 i = 0; i < uTix.length; i++) {
            uint256 existingTId = uTix[i];
            if (
                tToE[existingTId] == inp.eId &&
                ownerOf(existingTId) == msg.sender &&
                !tCancel[existingTId]
            ) {
                revert("Already owns ticket");
            }
        }

        if (e.price > 0) {
            require(msg.value >= e.price, "Insufficient payment");
            uint256 cAmt = (e.price * feePct) / 100;
            uint256 crAmt = e.price - cAmt;

            (bool s, ) = e.creator.call{value: crAmt}("");
            require(s, "Payment failed");

            emit PaymentDistributed(inp.eId, e.creator, crAmt, cAmt);

            if (msg.value > e.price) {
                payable(msg.sender).transfer(msg.value - e.price);
            }
        }

        uint256 tId = ++tIdCnt;
        _safeMint(msg.sender, tId);
        tToE[tId] = inp.eId;
        tByOwn[msg.sender].push(tId);
        e.sold++;
        attInfo[tId] = AttInfo(inp.name, inp.gender, inp.email, inp.phone);
        emit TicketMinted(
            inp.eId,
            tId,
            msg.sender,
            inp.name,
            inp.gender,
            inp.email,
            inp.phone
        );
    }

    function profileTicket(
        uint256 tId,
        string memory name,
        bool gender,
        string memory email,
        string memory phone
    ) external {
        require(_ownerOf(tId) != address(0), "Nonexistent token");
        require(ownerOf(tId) == msg.sender, "Not owner");
        require(bytes(name).length > 0, "Name required");
        require(bytes(email).length > 0, "Email required");
        require(bytes(phone).length > 0, "Phone required");

        attInfo[tId] = AttInfo(name, gender, email, phone);
        emit TicketProfileUpdated(tId, msg.sender, name, gender, email, phone);
    }

    function checkIn(uint256 tId) external {
        require(_ownerOf(tId) != address(0), "Nonexistent token");
        uint256 eId = tToE[tId];
        require(ownerOf(tId) == msg.sender, "Not owner");
        require(checkTs[tId] == 0, "Already checked in");
        require(!tCancel[tId], "Ticket cancelled");
        require(evs[eId].status == 1, "Event not active");
        require(
            block.timestamp >= evs[eId].start &&
                block.timestamp <= evs[eId].end + 1 hours,
            "Check-in closed"
        );

        checkTs[tId] = block.timestamp;
        emit CheckedIn(eId, tId, msg.sender, block.timestamp);
    }

    function getTicketInfo(
        uint256 tId
    )
        external
        view
        returns (
            uint256 eId,
            address own,
            bool checked,
            uint256 ts,
            string memory eName,
            uint8 eStatus,
            AttInfo memory att,
            bool tCanc
        )
    {
        require(_ownerOf(tId) != address(0), "Nonexistent token");
        eId = tToE[tId];
        Ev storage e = evs[eId];
        own = ownerOf(tId);
        checked = checkTs[tId] > 0;
        ts = checkTs[tId];
        eName = e.name;
        eStatus = e.status;
        att = attInfo[tId];
        tCanc = tCancel[tId];
    }

    function removeCheckIn(uint256 tId) external {
        require(_ownerOf(tId) != address(0), "Nonexistent token");
        uint256 eId = tToE[tId];
        require(
            evs[eId].creator == msg.sender || ownerOf(tId) == msg.sender,
            "Not authorized"
        );
        require(checkTs[tId] > 0, "Not checked in");
        checkTs[tId] = 0;
        emit CheckInRemoved(eId, tId);
    }

    function getMyTickets()
        external
        view
        returns (TixInfo[] memory, AttInfo[] memory)
    {
        uint256[] memory uTix = tByOwn[msg.sender];
        TixInfo[] memory tInfo = new TixInfo[](uTix.length);
        AttInfo[] memory aInfo = new AttInfo[](uTix.length);

        for (uint256 i = 0; i < uTix.length; i++) {
            uint256 tId = uTix[i];
            tInfo[i] = TixInfo(tId, tToE[tId], checkTs[tId] > 0, checkTs[tId]);
            aInfo[i] = attInfo[tId];
        }
        return (tInfo, aInfo);
    }

    function getEventTicketsWithName(
        address usr,
        uint256 eId
    )
        external
        view
        returns (uint256[] memory, string memory, AttInfo[] memory)
    {
        uint256[] memory allTix = tByOwn[usr];
        uint256 cnt;
        for (uint256 i = 0; i < allTix.length; i++) {
            if (tToE[allTix[i]] == eId) cnt++;
        }

        uint256[] memory filt = new uint256[](cnt);
        AttInfo[] memory atts = new AttInfo[](cnt);
        uint256 j;
        for (uint256 i = 0; i < allTix.length; i++) {
            if (tToE[allTix[i]] == eId) {
                filt[j] = allTix[i];
                atts[j] = attInfo[allTix[i]];
                j++;
            }
        }
        return (filt, evs[eId].name, atts);
    }

    function cancelTicket(uint256 tId) external {
        require(_ownerOf(tId) != address(0), "Nonexistent token");
        uint256 eId = tToE[tId];
        require(evs[eId].creator == msg.sender, "Not creator");
        require(!tCancel[tId], "Already cancelled");

        tCancel[tId] = true;
        emit TicketCancelled(eId, tId);
    }

    function unCancelTicket(uint256 tId) external {
        require(_ownerOf(tId) != address(0), "Nonexistent token");
        uint256 eId = tToE[tId];
        require(evs[eId].creator == msg.sender, "Not creator");
        require(tCancel[tId], "Not cancelled");

        tCancel[tId] = false;
        emit TicketUncancelled(eId, tId);
    }

    function withdrawTokenNative(uint256 amt) external onlyOwner nonReentrant {
        require(amt > 0 && amt <= address(this).balance, "Invalid amount");
        payable(owner()).transfer(amt);
    }

    function withdrawToken(
        address tkn,
        uint256 amt
    ) external onlyOwner nonReentrant {
        require(amt > 0, "Invalid amount");
        IERC20 t = IERC20(tkn);
        require(amt <= t.balanceOf(address(this)), "Insufficient balance");
        require(t.transfer(owner(), amt), "Transfer failed");
    }

    function getEventInfo(
        uint256 eId
    )
        external
        view
        returns (
            uint256 id,
            string memory name,
            uint256 maxTix,
            uint256 sold,
            uint256 start,
            uint256 end,
            address creator,
            string memory uri,
            uint8 status,
            string memory data,
            uint256 price,
            uint256 catId,
            uint256 chkInCnt,
            uint256 notChkInCnt
        )
    {
        Ev storage e = evs[eId];
        require(e.id != 0, "Nonexistent event");
        (chkInCnt, notChkInCnt) = _getEventCheckInStats(eId);
        return (
            e.id,
            e.name,
            e.maxTix,
            e.sold,
            e.start,
            e.end,
            e.creator,
            e.uri,
            e.status,
            e.data,
            e.price,
            e.catId,
            chkInCnt,
            notChkInCnt
        );
    }

    function getEventCheckInStats(
        uint256 eId
    ) external view returns (uint256 chkInCnt, uint256 notChkInCnt) {
        return _getEventCheckInStats(eId);
    }

    function _getEventCheckInStats(
        uint256 eId
    ) internal view returns (uint256 chkInCnt, uint256 notChkInCnt) {
        require(evs[eId].id != 0, "Nonexistent event");
        uint256 cnt;
        for (uint256 i = 1; i <= tIdCnt; i++) {
            if (tToE[i] == eId && checkTs[i] > 0) {
                cnt++;
            }
        }
        chkInCnt = cnt;
        notChkInCnt = evs[eId].sold - cnt;
    }

    function getEventsByPage(
        uint256 pg,
        uint8 status,
        uint256 catId
    ) external view returns (string[] memory) {
        require(pg > 0, "Invalid page");
        require(status <= 1, "Invalid status");

        string[] memory eDets = new string[](10);
        uint256 cnt;
        uint256 proc;
        uint256 start = (pg - 1) * 10;

        for (uint256 i = eCnt; i >= 1 && cnt < 10; i--) {
            if (
                evs[i].id != 0 &&
                evs[i].status == status &&
                (catId == 0 || evs[i].catId == catId)
            ) {
                if (++proc > start) {
                    (
                        uint256 chkInCnt,
                        uint256 notChkInCnt
                    ) = _getEventCheckInStats(i);
                    eDets[cnt++] = string(
                        abi.encodePacked(
                            _uintToString(evs[i].id),
                            ",",
                            evs[i].name,
                            ",",
                            _uintToString(evs[i].maxTix),
                            ",",
                            _uintToString(evs[i].sold),
                            ",",
                            _uintToString(evs[i].start),
                            ",",
                            _uintToString(evs[i].end),
                            ",",
                            _addressToString(evs[i].creator),
                            ",",
                            evs[i].uri,
                            ",",
                            _uintToString(evs[i].status),
                            ",",
                            evs[i].data,
                            ",",
                            _uintToString(evs[i].price),
                            ",",
                            _uintToString(evs[i].catId),
                            ",",
                            _uintToString(chkInCnt),
                            ",",
                            _uintToString(notChkInCnt)
                        )
                    );
                }
            }
            if (i == 1) break;
        }
        return eDets;
    }

    function searchEventsByName(
        uint256 pg,
        uint8 status,
        string memory term
    ) external view returns (string[] memory) {
        require(pg > 0, "Invalid page");
        require(status <= 1, "Invalid status");

        string[] memory eDets = new string[](10);
        uint256 cnt;
        uint256 proc;
        uint256 start = (pg - 1) * 10;
        string memory sLow = term.toLower();

        for (uint256 i = eCnt; i >= 1 && cnt < 10; i--) {
            if (
                evs[i].status == status && evs[i].name.toLower().contains(sLow)
            ) {
                if (++proc > start) {
                    (
                        uint256 chkInCnt,
                        uint256 notChkInCnt
                    ) = _getEventCheckInStats(i);
                    eDets[cnt++] = string(
                        abi.encodePacked(
                            _uintToString(evs[i].id),
                            ",",
                            evs[i].name,
                            ",",
                            _uintToString(evs[i].maxTix),
                            ",",
                            _uintToString(evs[i].sold),
                            ",",
                            _uintToString(evs[i].start),
                            ",",
                            _uintToString(evs[i].end),
                            ",",
                            _addressToString(evs[i].creator),
                            ",",
                            evs[i].uri,
                            ",",
                            _uintToString(evs[i].status),
                            ",",
                            evs[i].data,
                            ",",
                            _uintToString(evs[i].price),
                            ",",
                            _uintToString(evs[i].catId),
                            ",",
                            _uintToString(chkInCnt),
                            ",",
                            _uintToString(notChkInCnt)
                        )
                    );
                }
            }
            if (i == 1) break;
        }
        return eDets;
    }

    function recoverTicket(uint256 tId) external nonReentrant {
        require(_ownerOf(tId) != address(0), "Nonexistent token");
        uint256 eId = tToE[tId];
        require(evs[eId].creator == msg.sender, "Not creator");
        address own = ownerOf(tId);
        require(own == DEAD, "Not in dead address");

        uint256[] storage oTix = tByOwn[own];
        for (uint256 i = 0; i < oTix.length; i++) {
            if (oTix[i] == tId) {
                oTix[i] = oTix[oTix.length - 1];
                oTix.pop();
                break;
            }
        }

        _transfer(own, msg.sender, tId);
        tByOwn[msg.sender].push(tId);
        emit TicketRecovered(eId, tId, msg.sender, own);
    }

    function getTicketsByEventAndPage(
        uint256 eId,
        uint256 pg
    ) external view returns (string[] memory) {
        require(evs[eId].id != 0, "Nonexistent event");
        require(pg > 0, "Invalid page");

        string[] memory tDets = new string[](10);
        uint256 cnt;
        uint256 proc;
        uint256 start = (pg - 1) * 10;

        for (uint256 i = tIdCnt; i >= 1 && cnt < 10; i--) {
            if (tToE[i] == eId) {
                if (++proc > start) {
                    address own = _ownerOf(i);
                    AttInfo memory att = attInfo[i];
                    tDets[cnt++] = string(
                        abi.encodePacked(
                            _uintToString(i),
                            ",",
                            _uintToString(eId),
                            ",",
                            _addressToString(own),
                            ",",
                            att.name,
                            ",",
                            att.gender ? "1" : "0",
                            ",",
                            att.email,
                            ",",
                            att.phone,
                            ",",
                            checkTs[i] > 0 ? "1" : "0",
                            ",",
                            _uintToString(checkTs[i]),
                            ",",
                            tCancel[i] ? "1" : "0"
                        )
                    );
                }
            }
            if (i == 1) break;
        }
        return tDets;
    }

    function getTotalEventsByAllCategories()
        external
        view
        returns (uint256[15] memory)
    {
        uint256[15] memory tots;
        for (uint256 catId = 1; catId <= 15; catId++) {
            uint256 tot = 0;
            for (uint256 i = 1; i <= eCnt; i++) {
                if (evs[i].id != 0 && evs[i].catId == catId) {
                    tot++;
                }
            }
            tots[catId - 1] = tot;
        }
        return tots;
    }

    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override returns (address) {
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != from) {
            uint256[] storage fromTix = tByOwn[from];
            for (uint256 i = 0; i < fromTix.length; i++) {
                if (fromTix[i] == tokenId) {
                    fromTix[i] = fromTix[fromTix.length - 1];
                    fromTix.pop();
                    break;
                }
            }
            tByOwn[to].push(tokenId);
        }
        return super._update(to, tokenId, auth);
    }

    function _addressToString(address a) private pure returns (string memory) {
        bytes memory alp = "0123456789abcdef";
        bytes memory s = new bytes(42);
        s[0] = "0";
        s[1] = "x";
        for (uint256 i = 0; i < 20; i++) {
            uint8 sh = uint8(8 * (19 - i));
            s[2 + i * 2] = alp[uint8(uint160(a) >> sh) & 0xf];
            s[3 + i * 2] = alp[uint8(uint160(a) >> (sh + 4)) & 0xf];
        }
        return string(s);
    }

    function _uintToString(uint256 v) private pure returns (string memory) {
        if (v == 0) return "0";
        uint256 t = v;
        uint256 d;

        while (t != 0) {
            d++;
            t /= 10;
        }

        bytes memory b = new bytes(d);
        while (v != 0) {
            b[--d] = bytes1(uint8(48 + (v % 10)));
            v /= 10;
        }
        return string(b);
    }

    function renounceOwnership() public view override onlyOwner {
        revert("Cannot renounce");
    }
}
