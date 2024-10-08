// SPDX-License-Identifier: MIT
//Tiendatmagic
pragma solidity ^0.8.26;

interface IBEP20 {
    function totalSupply() external view returns (uint256);

    function decimals() external view returns (uint8);

    function symbol() external view returns (string memory);

    function name() external view returns (string memory);

    function balanceOf(address account) external view returns (uint256);

    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

contract Context {
    constructor() {}

    function _msgSender() internal view returns (address) {
        return msg.sender;
    }

    function _msgData() internal pure returns (bytes calldata) {
        return msg.data;
    }
}

contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    constructor() {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

contract BEP20Token is Context, IBEP20, Ownable {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => uint256) private _lastClaimTime;

    uint256 private _totalSupply;
    uint8 private _decimals;
    string private _symbol;
    string private _name;
    uint256 private _claimInterval;
    uint256 private _airdropAmount;

    constructor() {
        _name = "USDT Token";
        _symbol = "USDT";
        _decimals = 18;
        _totalSupply = 1000000 * 10 ** 18;
        _balances[msg.sender] = _totalSupply;
        _claimInterval = 30; // Default claim interval set to 30 minutes
        _airdropAmount = 1000 * 10 ** uint256(_decimals);

        emit Transfer(address(0), msg.sender, _totalSupply);
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function symbol() external view override returns (string memory) {
        return _symbol;
    }

    function name() external view override returns (string memory) {
        return _name;
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(
        address account
    ) external view override returns (uint256) {
        return _balances[account];
    }

    function transfer(
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(
        address owner,
        address spender
    ) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(
        address spender,
        uint256 amount
    ) external override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            _msgSender(),
            _allowances[sender][_msgSender()] - amount
        );
        return true;
    }

    function increaseAllowance(
        address spender,
        uint256 addedValue
    ) public returns (bool) {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender] + addedValue
        );
        return true;
    }

    function decreaseAllowance(
        address spender,
        uint256 subtractedValue
    ) public returns (bool) {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender] - subtractedValue
        );
        return true;
    }

    function burn(uint256 amount) public onlyOwner returns (bool) {
        _burn(_msgSender(), amount);
        return true;
    }

    function mint(uint256 amount) public onlyOwner returns (bool) {
        _mint(_msgSender(), amount);
        return true;
    }

    function claimAirdrop() external {
        require(
            block.timestamp >=
                _lastClaimTime[msg.sender] + _claimInterval * 1 minutes,
            "Airdrop: Claim not available yet"
        );

        uint256 airdropAmount = _airdropAmount;
        _mint(msg.sender, airdropAmount);

        _lastClaimTime[msg.sender] = block.timestamp;
    }

    function setAirdropAmount(uint256 amount) external onlyOwner {
        _airdropAmount = amount;
    }

    function getAirdropAmount() external view returns (uint256) {
        return _airdropAmount;
    }

    function setClaimInterval(uint256 intervalInMinutes) external onlyOwner {
        _claimInterval = intervalInMinutes;
    }

    function getClaimInterval() external view returns (uint256) {
        return _claimInterval;
    }

    function getTimeUntilNextClaim(
        address account
    ) external view returns (uint256) {
        if (
            block.timestamp >=
            _lastClaimTime[account] + _claimInterval * 1 minutes
        ) {
            return 0; // Đã có thể claim lại
        } else {
            return
                (_lastClaimTime[account] + _claimInterval * 1 minutes) -
                block.timestamp;
        }
    }

    function withdraw() external onlyOwner {
        uint256 contractBalance = _balances[address(this)];
        require(contractBalance > 0, "Withdraw: No tokens to withdraw");
        _transfer(address(this), _msgSender(), contractBalance);
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal {
        require(sender != address(0), "BEP20: transfer from the zero address");
        require(recipient != address(0), "BEP20: transfer to the zero address");

        uint256 senderBalance = _balances[sender];
        require(
            senderBalance >= amount,
            "BEP20: transfer amount exceeds balance"
        );
        _balances[sender] = senderBalance - amount;
        _balances[recipient] += amount;

        emit Transfer(sender, recipient, amount);
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "BEP20: mint to the zero address");

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal {
        require(account != address(0), "BEP20: burn from the zero address");

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "BEP20: burn amount exceeds balance");
        _balances[account] = accountBalance - amount;
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "BEP20: approve from the zero address");
        require(spender != address(0), "BEP20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _burnFrom(address account, uint256 amount) internal {
        _burn(account, amount);
        _approve(
            account,
            _msgSender(),
            _allowances[account][_msgSender()] - amount
        );
    }
}
//Tiendatmagic
