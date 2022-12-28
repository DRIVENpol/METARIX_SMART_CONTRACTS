//SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";

interface IToken {
    function balanceOf(address account) external view returns (uint256);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

/**
 * @title Staking Smart Contract
 * @notice Custom made smart contract to stake Metarix Tokens
 * @author Socarde Paul-Constantin, DRIVENlabs Inc.
 */

contract MetarixStaking_V1 is Ownable {

    /// @dev Metarix Token
    IToken public metarix;

    /// @dev Variable to increase/decrease the APR
    uint256 public aprFactor;
    uint256 public aprFactorForUsers;

    /// @dev Fee for emergency withdraw
    uint256 public fee;

    /// @dev Compund period
    uint256 compoundPeriod;

    /// @dev Pause the smart contract
    bool public isPaused;

    /// @dev Struct for pools
    struct Pool {
        uint256 id;
        uint256 apr;
        uint256 periodInDays;
        uint256 totalStakers;
        bool enabled;
    }

    /// @dev Struct for users
    struct Deposit {
        uint256 depositId;
        uint256 poolId;
        uint256 amount;
        uint256 compounded;
        uint256 startDate;
        uint256 endDate;
        address owner;
        bool ended;
    }

    /// @dev arrays of pools and deposits
    Pool[] public pools;
    Deposit[] public deposits;

    /// @dev Link an address to deposit with id
    mapping(address => uint256[]) public userDeposits;

    /// @dev Add increased APR for certain users
    mapping(address => bool) public hasIncreasedApr;

    /// @dev Track last compund date
    mapping(address => uint256) public lastCompundDate;

    /// @dev Events
    event RescueBNB(uint256 amount);
    event TogglePause(bool status);
    event NewAprFactor(uint256 apr);
    event NewEmergencyFee(uint256 fee);
    event NewCompundPeriod(uint256 period);
    event NewAprFactorForUsers(uint256 apr);
    event NewApr(uint256 poolId, uint256 newApr);
    event EnablePool(uint256 poolId, bool status);
    event DisablePool(uint256 poolId, bool status);
    event SetNormalAprFor(address indexed user, bool status);
    event SendTokensBack(address indexed user, uint256 amount);
    event SetIncreasedAprFor(address indexed user, bool status);
    event WithdrawErc20Tokens(address indexed token, uint256 amount);
    event Stake(address indexed user, uint256 poolId, uint256 amount);
    event Unstake(address indexed user, uint256 poolId, uint256 depositId, uint256 amount);
    event Compound(address indexed user, uint256 poolId, uint256 depositId, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 poolId, uint256 depositId, uint256 amount);

    /// @dev Errors
    error CantCompund();
    error InvalidOwner();
    error EndedDeposit();
    error PoolDisabled();
    error InvalidPoolId();
    error CantUnstakeNow();
    error ContractIsPaused();
    error CantStakeThatMuch();
    error FailedEthTransfer();
    error InvalidErc20Transfer();

    /// @dev Constructor
    constructor(address _metarix) {
        metarix = IToken(_metarix);
        
        // Create pools
        pools.push(Pool(0, 1000, 30, 0, true));
        pools.push(Pool(1, 2000, 180, 0, true));
        pools.push(Pool(2, 3000, 365, 0, true));

        aprFactor = 13; // 0.13%
        aprFactorForUsers = 250; // 2.5%

        fee = 10; // 10%
        compoundPeriod = 1 days; // 1 day

        isPaused = false;
    }

    /// @dev Funciton to stake tokens
    /// @param poolId In which pool the user want to stake
    /// @param amount How many tokens the user want to stake
    function stake(uint256 poolId, uint256 amount) external {
        if(isPaused == true) revert ContractIsPaused();
        if(poolId >= pools.length) revert InvalidPoolId();
        if(metarix.balanceOf(msg.sender) < amount) revert CantStakeThatMuch();
        if(metarix.transferFrom(msg.sender, address(this), amount) == false) revert InvalidErc20Transfer();
        Pool memory pool = pools[poolId];

        if(pool.enabled == false) revert PoolDisabled();

        uint256 _period = pool.periodInDays * 1 days;

        Deposit memory newDeposit = Deposit(
        deposits.length,
        poolId, 
        amount,
        0,
        block.timestamp,
        block.timestamp + _period,
        msg.sender,
        false);

        userDeposits[msg.sender].push(deposits.length);
        deposits.push(newDeposit);

        pools[poolId].totalStakers++;

        // Decrease the APR by aprFactor% for each new staker
        pools[poolId].apr -= aprFactor;

        emit Stake(msg.sender, poolId, amount);
    }

    /// @dev Function to unstake
    /// @param depositId From which deposit the user want to unstake
    function unstake(uint256 depositId) external {
        if(isPaused == true) revert ContractIsPaused();
        Deposit memory myDeposit = deposits[depositId];

        address _depositOwner = myDeposit.owner;
        uint256 _endDate = myDeposit.endDate;

        if(msg.sender != _depositOwner) revert InvalidOwner();
        if(block.timestamp < _endDate) revert CantUnstakeNow();
        if(myDeposit.ended == true) revert EndedDeposit();

        uint256 _amount = myDeposit.amount;
        uint256 _poolId = myDeposit.poolId;

        if(pools[_poolId].enabled == false) revert PoolDisabled();

        deposits[depositId].amount = 0;
        deposits[depositId].ended = true;

        // Compute rewards
        uint256 _pending = computePendingRewards(_depositOwner, _poolId, depositId, _amount);

        // Send rewards
        uint256 _totalAmount = _amount + _pending;
        
        if(metarix.transfer(myDeposit.owner, _totalAmount) == false) revert InvalidErc20Transfer();

        // Increase the APR by aprFactor% for each new staker
        pools[_poolId].apr += aprFactor;
        pools[_poolId].totalStakers--;

        emit Unstake(msg.sender, _poolId, depositId, _totalAmount);
    }

    /// @dev Function for emergency withdraw
    function emergencyWithdraw(uint256 depositId) external {
        if(isPaused == true) revert ContractIsPaused();
        Deposit memory myDeposit = deposits[depositId];

        address _depositOwner = myDeposit.owner;

        if(msg.sender != _depositOwner) revert InvalidOwner();
        if(myDeposit.ended == true) revert EndedDeposit();

        uint256 _amount = myDeposit.amount;
        uint256 _poolId = myDeposit.poolId;

        if(pools[_poolId].enabled == false) revert PoolDisabled();

        deposits[depositId].amount = 0;
        deposits[depositId].ended = true;

        // Substract the fee and send the amount
        uint256 _takenFee = _amount * fee / 100;
        uint256 _totalAmount = _amount  - _takenFee;
        
        if(metarix.transfer(myDeposit.owner, _totalAmount) == false) revert InvalidErc20Transfer();

        // Increase the APR by aprFactor% for each new staker
        pools[_poolId].apr += aprFactor;
        pools[_poolId].totalStakers--;

        emit EmergencyWithdraw(msg.sender, _poolId, depositId, _totalAmount);
    }

    /// @dev Function to compund the pending rewards
    function compound(uint256 depositId) external {
        if(isPaused == true) revert ContractIsPaused();
        Deposit memory myDeposit = deposits[depositId];
        
        address _depositOwner = myDeposit.owner;
        uint256 _endDate = myDeposit.endDate;

        if(msg.sender != _depositOwner) revert InvalidOwner();
        if(block.timestamp > _endDate) revert CantCompund();
        if(lastCompundDate[_depositOwner] + compoundPeriod > block.timestamp) revert CantCompund();
        if(myDeposit.ended == true) revert EndedDeposit();

        uint256 _amount = myDeposit.amount;
        uint256 _poolId = myDeposit.poolId;
        
        if(pools[_poolId].enabled == false) revert PoolDisabled();

        lastCompundDate[_depositOwner] = block.timestamp;

        // Compute rewards
        uint256 _pending = computePendingRewards(_depositOwner, _poolId, depositId, _amount);

        // Compound
        deposits[depositId].amount += _pending;
        deposits[depositId].compounded += _pending;

        emit Compound(msg.sender, _poolId, depositId, _pending);
    }

    /// @dev Function to compute pending rewards
    /// @return _pendingRewards Return pending rewards
    function computePendingRewards(address user, uint256 poolId, uint256 depositId, uint256 amount) internal view returns(uint256) {
        Pool memory pool = pools[poolId];
        Deposit memory deposit = deposits[depositId];

        uint256 _apr = pool.apr;
        uint256 _period = pool.periodInDays;
        uint256 _compounded = deposit.compounded;

        if(hasIncreasedApr[user] == true) {
            _apr += aprFactorForUsers;
        }

        uint256 _rPerYear = (amount * _apr) / 100;
        uint256 _rPerDay = _rPerYear / 365;
        uint256 _rPerHour = _rPerDay / 24;
        uint256 _rPerMinute = _rPerHour / 60;
        uint256 _rPerSecond = _rPerMinute / 60;

        uint256 _delta = block.timestamp - deposit.startDate;
        uint256 _pendingRewards;

        // If deposit not ended
        if(block.timestamp < deposit.endDate) {
            _pendingRewards = (_delta * _rPerSecond) - _compounded;
        } else { // If deposit ended
                if(_period == 30) {
                    _pendingRewards = _rPerDay * 30;
                } else if(_period == 180) {
                    _pendingRewards = _rPerDay * 180;
                } else if(_period == 365) {
                    _pendingRewards = _rPerYear;
                }
        }
        return _pendingRewards / 100;
    }

    /// @dev Pause the smart contract
    function togglePause() external onlyOwner {
        if(isPaused == true) {
            isPaused = false;
        } else {
            isPaused = true;
        }

        emit TogglePause(isPaused);
    }

    /// @dev Function to change the apr factor
    function changeAprFactor(uint256 newFactor) external onlyOwner {
        aprFactor = newFactor;

        emit NewAprFactor(newFactor);
    }

    /// @dev Function to change the apr factor
    function changeAprFactorForUSers(uint256 newFactor) external onlyOwner {
        aprFactorForUsers = newFactor;

        emit NewAprFactorForUsers(newFactor);
    }

    /// @dev Function to change the fee for emergency withdraw
    function changeEmergencyFee(uint256 newFee) external onlyOwner {
        fee = newFee;
    
        emit NewEmergencyFee(newFee);
    }

    /// @dev Function to change the compund period
    function changeCompundPeriod(uint256 newPeriod) external onlyOwner {
        compoundPeriod = newPeriod * 1 hours;

        emit NewCompundPeriod(newPeriod * 1 hours);
    }

    /// @dev Function to set user with increased apr
    function setIncreasedAprForUser(address user) external onlyOwner {
        hasIncreasedApr[user] = true;

        emit SetIncreasedAprFor(user, true);
    }

    /// @dev Funciton to set users with increased apr
    function setIncreasedAprForUsers(address[] calldata users) external onlyOwner {
        for(uint256 i=0; i< users.length; i++) {
            address _user = users[i];
            hasIncreasedApr[_user] = true;

            emit SetIncreasedAprFor(_user, true);
        }
    }

    /// @dev Function to set user with normal apr again
    function setNormalAprForUser(address user) external onlyOwner {
        hasIncreasedApr[user] = false;

        emit SetNormalAprFor(user, false);
    }

    /// @dev Funciton to set users with normal apr again
    function setNormalAprForUsers(address[] calldata users) external onlyOwner {
        for(uint256 i=0; i< users.length; i++) {
            address _user = users[i];
            hasIncreasedApr[_user] = false;

            emit SetNormalAprFor(_user, false);
        }
    }

    /// @dev Function to disable a pool
    function disablePool(uint256 poolId) external onlyOwner {
        pools[poolId].enabled = false;

        emit DisablePool(poolId, false);
    }

    /// @dev Function to disable all pools
    function disableAllPools() external onlyOwner {
        for(uint256 i=0; i< pools.length; i++) {
            pools[i].enabled = false;

            emit DisablePool(i, false);
        }
    }

    /// @dev Function to enable a pool
    function enablePool(uint256 poolId) external onlyOwner {
        pools[poolId].enabled = true;

        emit EnablePool(poolId, true);
    }

    /// @dev Function to disable all pools
    function enableAllPools() external onlyOwner {
        for(uint256 i=0; i< pools.length; i++) {
            pools[i].enabled = true;

            emit EnablePool(i, true);
        }
    }

    /// @dev Function to set APR for a specific pool
    function setNewApr(uint256 poolId, uint256 newApr) external onlyOwner {
        pools[poolId].apr = newApr;

        emit NewApr(poolId, newApr);
    }

    /// @dev Function to send the staked tokens back to users
    function sendTokensBack() external onlyOwner {
        for(uint256 i=0; i< deposits.length; i++) {
            uint256 _amount = deposits[i].amount;
            address _owner = deposits[i].owner;
            deposits[i].amount = 0;
            if(metarix.transfer(_owner, _amount) == false) revert InvalidErc20Transfer();

            emit SendTokensBack(_owner, _amount);
        }
    }

    /// @dev Function to withdraw tokens from the smart contract
    function withdrawErc20Tokens(address token) external onlyOwner {
        uint256 _balance = IToken(token).balanceOf(address(this));
        if(IToken(token).transfer(owner(), _balance) == false) revert InvalidErc20Transfer();

        emit WithdrawErc20Tokens(token, _balance);
    }

    /// @dev Function to rescue BNB
    function rescueBnb() external onlyOwner {
        address _to = owner();
        uint256 _amount = address(this).balance;

        (bool sent, ) = _to.call{value: _amount}("");
        if(sent == false) revert FailedEthTransfer();

        emit RescueBNB(_amount);
    }
}