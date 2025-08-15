// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

contract TimeLimitedAccessPass {
    /*//////////////////////////////////////////////////////////////
                                 OWNABLE
    //////////////////////////////////////////////////////////////*/
    address public owner;

    event OwnerTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    function _transferOwnership(address newOwner) internal {
        require(newOwner != address(0), "Zero owner");
        emit OwnerTransferred(owner, newOwner);
        owner = newOwner;
    }

    /*//////////////////////////////////////////////////////////////
                           REENTRANCY GUARD
    //////////////////////////////////////////////////////////////*/
    uint256 private _reentrancyLock = 1;
    modifier nonReentrant() {
        require(_reentrancyLock == 1, "Reentrancy");
        _reentrancyLock = 2;
        _;
        _reentrancyLock = 1;
    }

    /*//////////////////////////////////////////////////////////////
                               PASS TYPES
    //////////////////////////////////////////////////////////////*/
    struct PassType {
        uint256 price; // price in wei for 1 unit (1 duration)
        uint256 duration; // seconds per unit (e.g., 30 days)
        uint256 maxSupply; // 0 = unlimited
        uint256 sold; // total units sold
        bool isActive; // can be purchased
        bool stackable; // if true, buying multiple extends time additively
        string name; // optional label (e.g., "Monthly", "Annual", "VIP Day Pass")
    }

    // passId => PassType
    mapping(uint256 => PassType) public passTypes;
    uint256 public passTypeCount;

    // user => passId => expiration timestamp
    mapping(address => mapping(uint256 => uint256)) public expirationOf;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event PassTypeCreated(
        uint256 indexed passId,
        string name,
        uint256 price,
        uint256 duration,
        uint256 maxSupply,
        bool isActive,
        bool stackable
    );
    event PassTypeUpdated(
        uint256 indexed passId,
        string name,
        uint256 price,
        uint256 duration,
        uint256 maxSupply,
        bool isActive,
        bool stackable
    );
    event Purchased(
        address indexed buyer,
        uint256 indexed passId,
        uint256 quantity,
        uint256 newExpiration,
        uint256 valuePaid
    );
    event Granted(
        address indexed to,
        uint256 indexed passId,
        uint256 quantity,
        uint256 newExpiration
    );
    event Revoked(
        address indexed user,
        uint256 indexed passId,
        uint256 oldExpiration
    );
    event Withdrawn(address indexed to, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor() {
        owner = msg.sender;
        emit OwnerTransferred(address(0), msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                              ADMIN LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Create a new pass type.
    /// @param _name Display name (e.g., "Monthly Access")
    /// @param _price Price per unit (wei)
    /// @param _duration Duration per unit (seconds)
    /// @param _maxSupply 0 for unlimited; otherwise total units sellable
    /// @param _isActive Whether purchasable at launch
    /// @param _stackable If true, multiple units extend time linearly
    function createPassType(
        string memory _name,
        uint256 _price,
        uint256 _duration,
        uint256 _maxSupply,
        bool _isActive,
        bool _stackable
    ) external onlyOwner returns (uint256 passId) {
        require(_duration > 0, "Duration=0");
        passId = ++passTypeCount;

        passTypes[passId] = PassType({
            price: _price,
            duration: _duration,
            maxSupply: _maxSupply,
            sold: 0,
            isActive: _isActive,
            stackable: _stackable,
            name: _name
        });

        emit PassTypeCreated(
            passId,
            _name,
            _price,
            _duration,
            _maxSupply,
            _isActive,
            _stackable
        );
    }

    /// @notice Update an existing pass type. All fields are overwritten.
    function updatePassType(
        uint256 passId,
        string memory _name,
        uint256 _price,
        uint256 _duration,
        uint256 _maxSupply,
        bool _isActive,
        bool _stackable
    ) external onlyOwner {
        PassType storage p = passTypes[passId];
        require(p.duration != 0, "Pass not found");
        require(_duration > 0, "Duration=0");

        p.name = _name;
        p.price = _price;
        p.duration = _duration;
        p.maxSupply = _maxSupply;
        p.isActive = _isActive;
        p.stackable = _stackable;

        emit PassTypeUpdated(
            passId,
            _name,
            _price,
            _duration,
            _maxSupply,
            _isActive,
            _stackable
        );
    }

    /// @notice Grant time to a user without payment (airdrop, comp, support).
    /// @param to Recipient
    /// @param passId Pass type id
    /// @param quantity Number of units to grant (each unit = duration)
    function grant(
        address to,
        uint256 passId,
        uint256 quantity
    ) external onlyOwner {
        require(to != address(0), "Zero addr");
        require(quantity > 0, "Qty=0");
        PassType storage p = passTypes[passId];
        require(p.duration != 0, "Pass not found");

        _enforceSupply(p, quantity);

        uint256 addTime = p.duration * quantity;
        uint256 current = expirationOf[to][passId];

        // If already active, extend from current expiration; else from now
        uint256 base = current > block.timestamp ? current : block.timestamp;
        uint256 newExp = base + addTime;
        expirationOf[to][passId] = newExp;

        emit Granted(to, passId, quantity, newExp);
    }

    /// @notice Revoke a user's pass (sets expiration to now).
    function revoke(address user, uint256 passId) external onlyOwner {
        uint256 old = expirationOf[user][passId];
        require(old > block.timestamp, "Not active");
        expirationOf[user][passId] = block.timestamp;
        emit Revoked(user, passId, old);
    }

    /// @notice Withdraw accumulated ETH.
    function withdraw(
        address payable to,
        uint256 amount
    ) external onlyOwner nonReentrant {
        require(to != address(0), "Zero to");
        require(amount <= address(this).balance, "Insufficient");
        (bool ok, ) = to.call{value: amount}("");
        require(ok, "Withdraw failed");
        emit Withdrawn(to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                               PURCHASE
    //////////////////////////////////////////////////////////////*/

    /// @notice Purchase time for a given pass type.
    /// @param passId Pass type to purchase
    /// @param quantity Number of units (each adds `duration`)
    function buy(
        uint256 passId,
        uint256 quantity
    ) external payable nonReentrant {
        require(quantity > 0, "Qty=0");
        PassType storage p = passTypes[passId];
        require(p.duration != 0, "Pass not found");
        require(p.isActive, "Sales paused");

        _enforceSupply(p, quantity);

        uint256 cost = p.price * quantity;
        require(msg.value == cost, "Wrong ETH sent");

        uint256 addTime = p.duration * quantity;
        uint256 current = expirationOf[msg.sender][passId];

        // If pass is active, extend from current expiration; else start from now
        uint256 base = current > block.timestamp ? current : block.timestamp;
        uint256 newExp = base + addTime;

        expirationOf[msg.sender][passId] = newExp;

        emit Purchased(msg.sender, passId, quantity, newExp, msg.value);
    }

    function _enforceSupply(PassType storage p, uint256 quantity) internal {
        if (p.maxSupply != 0) {
            require(p.sold + quantity <= p.maxSupply, "Sold out");
        }
        p.sold += quantity;
    }

    /*//////////////////////////////////////////////////////////////
                              VIEW HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @return Whether `user` currently has access for `passId`.
    function hasAccess(
        address user,
        uint256 passId
    ) public view returns (bool) {
        return expirationOf[user][passId] > block.timestamp;
    }

    /// @return Seconds remaining for `user` on `passId` (0 if expired).
    function timeRemaining(
        address user,
        uint256 passId
    ) external view returns (uint256) {
        uint256 exp = expirationOf[user][passId];
        if (exp <= block.timestamp) return 0;
        return exp - block.timestamp;
    }

    /// @return Expiration timestamp for `user` on `passId` (UNIX time).
    function expiresAt(
        address user,
        uint256 passId
    ) external view returns (uint256) {
        return expirationOf[user][passId];
    }

    /// @return name The name of the pass type.
    /// @return price The price per unit (wei).
    /// @return duration The duration per unit (seconds).
    /// @return maxSupply The maximum supply of the pass type.
    /// @return sold The total units sold.
    /// @return isActive Whether the pass type is active.
    /// @return stackable Whether the pass type is stackable.
    function getPassType(
        uint256 passId
    )
        external
        view
        returns (
            string memory name,
            uint256 price,
            uint256 duration,
            uint256 maxSupply,
            uint256 sold,
            bool isActive,
            bool stackable
        )
    {
        PassType storage p = passTypes[passId];
        require(p.duration != 0, "Pass not found");
        return (
            p.name,
            p.price,
            p.duration,
            p.maxSupply,
            p.sold,
            p.isActive,
            p.stackable
        );
    }

    /*//////////////////////////////////////////////////////////////
                           OWNER MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function transferOwnership(address newOwner) external onlyOwner {
        _transferOwnership(newOwner);
    }

    /*//////////////////////////////////////////////////////////////
                                 FALLBACK
    //////////////////////////////////////////////////////////////*/
    receive() external payable {}

    fallback() external payable {}
}
