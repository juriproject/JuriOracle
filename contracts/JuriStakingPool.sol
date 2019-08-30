pragma solidity 0.5.10;

import "./lib/IERC20.sol";
import "./lib/Math.sol";
import "./lib/Ownable.sol";
import "./lib/SafeMath.sol";

contract JuriStakingPool is Ownable {
    using SafeMath for uint256;

    enum Stages {
        AWAITING_COMPLIANCE_DATA,
        AWAITING_FIRST_UPDATE,
        AWAITING_SECOND_UPDATE
    }

    struct PoolDefinition {
        uint256 startTime;
        uint256 periodLength;
        uint256 feePercentage;
        uint256 compliantGainPercentage;
        uint256 maxNonCompliantPenaltyPercentage;
        uint256 maxNonCompliantFactor;
        uint256 minStakePerUser;
        uint256 maxStakePerUser;
        uint256 maxTotalStake;
    }

    struct CurrentStakingRound {
        mapping (address => bool) userIsStaking;
        mapping (address => uint256) userStakes;
        mapping (address => uint256) userStakesAtRoundStart;

        uint256 roundIndex;
        Stages stage;

        uint256 addComplianceDataIndex;
        uint256 updateStaking1Index;
        uint256 updateStaking2Index;

        uint256 totalStakeToSlash;
        uint256 nonCompliancePenalty;
        uint256 totalPayout;
        uint256 juriFees;

        bool useMaxNonCompliancy;
    }

    struct NextStakingRound {
        mapping (address => bool) userIsStaking;
        mapping (address => uint256) addedUserStakes;
        mapping (address => bool) userIsLeaving;
        address[] usersToAdd;
        uint256 totalAddedStake;
    }

    IERC20 public token;
    address public juriAddress;
    PoolDefinition public poolDefinition;

    // Pool state
    CurrentStakingRound public currentStakingRound;
    NextStakingRound public nextStakingRound;

    address[] public users;
    uint256 public ownerFunds;
    uint256 public totalUserStake;

    uint256 public complianceDataIndex;
    mapping (uint256 => mapping(address => bool)) public complianceDataAtIndex;

    event AddedComplianceDataForUser(address user, bool wasCompliant);

    /**
     * @dev Reverts if called in incorrect stage.
     * @param _stage The allowed stage for the given function.
     */
    modifier atStage(Stages _stage) {
        require(
            currentStakingRound.stage == _stage,
            "Function cannot be called at this time!"
        );

        _;
    }

    /**
     * @dev Reverts if called by any account other than a pool user.
     */
    modifier isPoolUser() {
        require(
            _isInArray(msg.sender, users),
            "Only added pool users can use this function!"
        );

        _;
    }

    /**
     * @dev Reverts if called by any pool user account.
     */
    modifier isNotPoolUser() {
        require(
            !_isInArray(msg.sender, users),
            "Only non-members can use this function!"
        );

        _;
    }

    /**
     * @dev Reverts if called by any pool user account.
     */
    modifier isNotPendingPoolUser() {
        require(
            !_isInArray(msg.sender, nextStakingRound.usersToAdd),
            "Only non-pending pool users can use this function!"
        );

        _;
    }

    /**
     * @dev Reverts if called by any pool user account.
     */
    modifier isPoolUserOrPendingPoolUser() {
        require(
            _isInArray(msg.sender, nextStakingRound.usersToAdd)
            || _isInArray(msg.sender, users),
            "Only pool users or pending pool users can use this function!"
        );

        _;
    }

    /**
     * @dev Reverts if called by any account other than the Juri address.
     */
    modifier isJuriNetwork() {
        require(
            msg.sender == juriAddress,
            "Only juriAddress can use this function!"
        );

        _;
    }

    /**
     * @dev JuriStakingPool constructor.
     * @param _token The ERC-20 token to be used for staking.
     * @param _periodLength The length of a staking period.
     * @param _feePercentage The fee percentage for the Juri protocol (0-100).
     * @param _compliantGainPercentage The staking gain percentage for
     * compliant users (0-100).
     * @param _maxNonCompliantPenaltyPercentage The maximum penalty percentage
     * for non-compliant users (0-100).
     * @param _minStakePerUser The minimum amount to stake for users.
     * @param _maxStakePerUser The maximum amount to stake for users.
     * @param _maxTotalStake The maximum amount of total stake in the pool.
     * @param _juriAddress The address of the Juri protocol.
     */
    constructor(
        IERC20 _token,
        uint256 _startTime,
        uint256 _periodLength,
        uint256 _feePercentage,
        uint256 _compliantGainPercentage,
        uint256 _maxNonCompliantPenaltyPercentage,
        uint256 _minStakePerUser,
        uint256 _maxStakePerUser,
        uint256 _maxTotalStake,
        address _juriAddress
    ) public {
        require(
            address(_token) != address(0),
            "Token address must be defined!"
        );
        require(_startTime > now, "Start time must be in the future!");
        require(_periodLength > 0, "Period length cannot be 0!");
        require(
            _feePercentage >= 0 && _feePercentage <= 100,
            "Fee percentage must be a number between 0 and 100!"
        );
        require(
            _compliantGainPercentage >= 0 && _compliantGainPercentage <= 100,
            "Compliant gain percentage must be a number between 0 and 100!"
        );
        require(
            _maxNonCompliantPenaltyPercentage >= 0 && _maxNonCompliantPenaltyPercentage <= 100,
            "Max non-compliant penalty percentage must be a number between 0 and 100!"
        );
        require(_minStakePerUser > 0, "Min stake per user cannot be 0!");
        require(_maxStakePerUser > 0, "Max stake per user cannot be 0!");
        require(_maxTotalStake > 0, "Max stake per user cannot be 0!");
        require(_juriAddress != address(0), "Juri address cannot be 0!");

        ownerFunds = 0;
        totalUserStake = 0;
        complianceDataIndex = 0;

        _setStakingPeriodVariables(0);

        token = _token;
        juriAddress = _juriAddress;

        poolDefinition = PoolDefinition(
            _startTime,
            _periodLength,
            _feePercentage,
            _compliantGainPercentage,
            _maxNonCompliantPenaltyPercentage,
            uint256(100).sub(_maxNonCompliantPenaltyPercentage),
            _minStakePerUser,
            _maxStakePerUser,
            _maxTotalStake
        );
    }

    /**
     * @dev Add user to pool once next staking period starts.
     * @param _amount The amount to be added as stake for the user.
     */
    function addUserInNextPeriod(uint256 _amount)
        public
        isNotPendingPoolUser
        isNotPoolUser
        atStage(Stages.AWAITING_COMPLIANCE_DATA)
    {
        require(
            _amount >= poolDefinition.minStakePerUser,
            'Please pass at least the min stake per user as amount!'
        );

        nextStakingRound.usersToAdd.push(msg.sender);

        addMoreStakeForNextPeriod(_amount);
        optInForStakingForNextPeriod();
    }

    /**
     * @dev Remove user from pool once next staking period starts.
     */
    function removeUserInNextPeriod()
        public
        isPoolUser
        atStage(Stages.AWAITING_COMPLIANCE_DATA)
    {
        require(
            !nextStakingRound.userIsLeaving[msg.sender],
            "User already marked for removal!"
        );

        nextStakingRound.userIsLeaving[msg.sender] = true;
        optOutOfStakingForNextPeriod();
    }

    /**
     * @dev Add more stake for user once next staking period starts.
     * @param _amount The amount to be added as stake.
     */
    function addMoreStakeForNextPeriod(uint256 _amount)
        public
        atStage(Stages.AWAITING_COMPLIANCE_DATA)
        isPoolUserOrPendingPoolUser
    {
        // TODO think about time restrictions:
        // what if compliance data is not added in time?
        uint256 stakeInCurrentPeriod
            = currentStakingRound.userStakes[msg.sender];
        uint256 stakeInNextPeriod
            = nextStakingRound.addedUserStakes[msg.sender];

        require(_amount > 0, "Please pass an amount higher than 0!");
        require(
            stakeInCurrentPeriod.add(stakeInNextPeriod) < poolDefinition.maxStakePerUser,
            "Cannot add more funds for user, because the max per user is reached!"
        );
        require(
            totalUserStake.add(nextStakingRound.totalAddedStake) < poolDefinition.maxTotalStake,
            "Cannot add more funds to pool, because the max in pool is reached!"
        );

        uint256 newStakeInNextPeriod = stakeInNextPeriod.add(_amount);
        uint256 adjustedAddedStake = _amount;

        if (
            stakeInCurrentPeriod.add(newStakeInNextPeriod)
                > poolDefinition.maxStakePerUser
        ) {
            adjustedAddedStake = poolDefinition.maxStakePerUser.sub(
                stakeInCurrentPeriod.add(stakeInNextPeriod)
            );
        }

        uint256 adjustedNewStakeInNextPeriod
            = stakeInNextPeriod.add(adjustedAddedStake);

        if (
            totalUserStake
                .add(nextStakingRound.totalAddedStake)
                .add(adjustedNewStakeInNextPeriod)
                > poolDefinition.maxTotalStake
        ) {
            adjustedAddedStake = poolDefinition.maxTotalStake.sub(
                totalUserStake.add(nextStakingRound.totalAddedStake)
            );
        }

        require(
            token.transferFrom(msg.sender, address(this), adjustedAddedStake),
            "Token transfer failed!"
        );

        uint256 newStakeBalanceInNextPeriod
            = stakeInNextPeriod.add(adjustedAddedStake);
        nextStakingRound.addedUserStakes[msg.sender]
            = newStakeBalanceInNextPeriod;
        nextStakingRound.totalAddedStake = nextStakingRound.totalAddedStake
            .add(adjustedAddedStake);
    }

    /**
     * @dev Opt in for staking for user once next staking period starts.
     */
    function optInForStakingForNextPeriod()
        public
        atStage(Stages.AWAITING_COMPLIANCE_DATA)
        isPoolUserOrPendingPoolUser
    {
        nextStakingRound.userIsStaking[msg.sender] = true;
    }

    /**
     * @dev Opt out of staking for user once next staking period starts.
     */
    function optOutOfStakingForNextPeriod()
        public
        atStage(Stages.AWAITING_COMPLIANCE_DATA)
        isPoolUserOrPendingPoolUser
    {
        nextStakingRound.userIsStaking[msg.sender] = false;
    }

    /**
     * @dev Withdraw user stake funds from pool. Use funds added for next period
     * first. Keep enough funds to pay non-compliant penalty if required.
     */
    function withdraw(
        uint256 _amount
    ) public atStage(Stages.AWAITING_COMPLIANCE_DATA) isPoolUser {
        bool canWithdrawAll = false;
        _withdrawForUser(msg.sender, _amount, canWithdrawAll);
    }

    /**
     * @dev Add owner funds to pool.
     */
    function addOwnerFunds(uint256 _amount)
        public
        onlyOwner
        atStage(Stages.AWAITING_COMPLIANCE_DATA)
    {
        require(_amount > 0, "Please pass an amount higher than 0!");
        require(
            token.transferFrom(msg.sender, address(this), _amount),
            "Token transfer failed!"
        );

        ownerFunds = ownerFunds.add(_amount);
    }

    /**
     * @dev Withdraw owner funds from pool.
     * @param _amount The amount to withdraw.
     */
    function withdrawOwnerFunds(
        uint256 _amount
    ) public onlyOwner atStage(Stages.AWAITING_COMPLIANCE_DATA) {
        uint256 amount = _amount;
        uint256 minOwnerFunds = _computeMinOwnerFunds();

        require(amount > 0, "Please pass an amount higher than 0!!");
        require(ownerFunds > 0, "No funds available to withdraw!");

        require(
            ownerFunds > minOwnerFunds + 1,
            "Cannot withdraw below min owner funds!"
        );

        if (ownerFunds < minOwnerFunds.add(amount)) {
            amount = ownerFunds.sub(minOwnerFunds);
        }

        require(
            token.transfer(msg.sender, amount),
            "Token transfer failed!"
        );
        ownerFunds = ownerFunds.sub(amount);
    }

    /**
     * @dev Add user's compliancy data for current or past periods.
     * @param _updateIterationCount The number defining the max for how much compliance
     * data will be passed in a single function call to prevent out-of-gas errors.
     * @param _wasCompliant The boolean array to indicate compliancy.
     */
    function addWasCompliantDataForUsers(
        uint256 _updateIterationCount,
        bool[] memory _wasCompliant
    )
        public
        isJuriNetwork
        atStage(Stages.AWAITING_COMPLIANCE_DATA)
    {
        // Commented out, because currently not supported anyways to add
        // multiple compliance data lists due to stage restriction.
        /* require(
            complianceDataIndex <= currentStakingPeriodIndex,
            "Cannot add compliance data for future periods!"
        ); */

        uint256 nextStakingPeriodEndTime = poolDefinition.startTime.add(
            currentStakingRound.roundIndex.mul(poolDefinition.periodLength)
        );
        require(
            now > nextStakingPeriodEndTime,
            "Can only add new data after end of periodLength!"
        );

        if (currentStakingRound.addComplianceDataIndex
            .add(_updateIterationCount) > users.length
        ) {
            require(
                currentStakingRound.addComplianceDataIndex
                    .add(_wasCompliant.length) == users.length,
                "Compliance data length must match pool users array!"
            );
        }

        for (
            (uint256 i, uint256 j) = (currentStakingRound.addComplianceDataIndex, 0);
            i < users.length && i <
                currentStakingRound.addComplianceDataIndex
                    .add(_updateIterationCount);
            (i++, j++)
        ) {
            complianceDataAtIndex[complianceDataIndex][users[i]]
                = _wasCompliant[j];
            emit AddedComplianceDataForUser(users[i], _wasCompliant[j]);
        }

        currentStakingRound.addComplianceDataIndex
            = currentStakingRound.addComplianceDataIndex
                .add(_updateIterationCount);

        if (currentStakingRound.addComplianceDataIndex >= users.length) {
            complianceDataIndex++;
            currentStakingRound.stage = Stages.AWAITING_FIRST_UPDATE;
        }
    }

    /**
     * @dev First part for updating stakes of users for next X users.
     * @param _updateIterationCount The number defining how many users should
     * be updated in a single function call to prevent out-of-gas errors.
     */
    function firstUpdateStakeForNextXAmountOfUsers(
        uint256 _updateIterationCount
    )
        public
        onlyOwner
        atStage(Stages.AWAITING_FIRST_UPDATE)
    {
        for (
            uint256 i = currentStakingRound.updateStaking1Index;
            i < users.length && i <
                currentStakingRound.updateStaking1Index
                    .add(_updateIterationCount);
            i++
        ) {
            address user = users[i];

            if (!currentStakingRound.userIsStaking[user]) {
                continue;
            }

            bool wasCompliant = complianceDataAtIndex
                [currentStakingRound.roundIndex]
                [user];

            uint256 stake = getStakeForUserAtRoundStart(user);

            if (wasCompliant) {
                uint256 newStake = _computeNewCompliantStake(stake);
                uint256 gain = newStake.sub(stake);
                currentStakingRound.totalPayout
                    = currentStakingRound.totalPayout.add(gain);

                _moveStakeToNextPeriod(user, newStake);
            } else {
                currentStakingRound.totalStakeToSlash
                    = currentStakingRound.totalStakeToSlash.add(stake);
            }
        }

        currentStakingRound.updateStaking1Index
            = currentStakingRound.updateStaking1Index
                .add(_updateIterationCount);

        if (currentStakingRound.updateStaking1Index >= users.length) {
            currentStakingRound.stage = Stages.AWAITING_SECOND_UPDATE;
        }
    }

    /**
     * @dev Second part for updating stakes of users for next X users.
     * @param _updateIterationCount The number defining how many users should
     * be updated in a single function call to prevent out-of-gas errors.
     */
    function secondUpdateStakeForNextXAmountOfUsers(
        uint256 _updateIterationCount
    )
        public
        onlyOwner
        atStage(Stages.AWAITING_SECOND_UPDATE)
    {
        if (currentStakingRound.updateStaking2Index == 0) {
            currentStakingRound.useMaxNonCompliancy = _computeUseMaxNonCompliancy();
        }

        uint256 removedUserCount = 0;

        for (
            uint256 iteration = currentStakingRound.updateStaking2Index;
            (iteration.sub(removedUserCount) < users.length
                || iteration.sub(removedUserCount) < nextStakingRound.usersToAdd.length
            ) && iteration < currentStakingRound.updateStaking2Index
                .add(_updateIterationCount);
            iteration++
        ) {
            uint256 i = iteration.sub(removedUserCount);

            if (users.length > i.add(nextStakingRound.usersToAdd.length)) {
                _handleSecondUpdateForUser(users[i]);
            }

            if (users.length > i && nextStakingRound.userIsLeaving[users[i]]) {
                nextStakingRound.userIsLeaving[users[i]] = false;
                _removeUserAtIndex(i);
                removedUserCount++;
            } else if (nextStakingRound.usersToAdd.length > i) {
                _addPendingUser(nextStakingRound.usersToAdd[i]);
            }
        }

        currentStakingRound.updateStaking2Index
            = currentStakingRound.updateStaking2Index.add(_updateIterationCount)
                .sub(removedUserCount);

        if (currentStakingRound.updateStaking2Index >= users.length &&
            currentStakingRound.updateStaking2Index >= nextStakingRound.usersToAdd.length
        ) {
            _handleJuriFees();
            _handleUnderwriting();
            _resetPoolForNextPeriod();
        }
    }

    /**
     * @dev Set new Juri address.
     * @param _newJuriAddress The new Juri address to be stored.
     */
    function setJuriAddress(address _newJuriAddress) public isJuriNetwork {
        require(_newJuriAddress != address(0), "New Juri address cannot be 0!");

        juriAddress = _newJuriAddress;
    }

    /**
     * @dev Get the total pool user count.
     */
    function getPoolUserCount() public view returns (uint256) {
        return users.length;
    }

    /**
     * @dev Read users to be added in the next round.
     * @param _index The index in the array of pending user additions.
     * @return The user to be added.
     */
    function getUserToBeAddedNextPeriod(uint256 _index)
        public
        view
        returns (address)
    {
        return nextStakingRound.usersToAdd[_index];
    }

    /**
     * @dev Read if calling user is staking in the current round.
     * @return The boolean indicator if user is staking in the current round.
     */
    function getIsCurrentRoundStaking()
        public
        view
        returns (bool)
    {
        return currentStakingRound.userIsStaking[msg.sender];
    }

    /**
     * @dev Read if calling user is staking in the next round.
     * @return The boolean indicator if user will be staking next round.
     */
    function getIsNextRoundStaking()
        public
        view
        returns (bool)
    {
        return nextStakingRound.userIsStaking[msg.sender];
    }

    /**
     * @dev Read if user will be removed in the next round.
     * @param _user The user to be checked.
     * @return The boolean indicator showing if user is leaving next round.
     */
    function getIsLeavingNextPeriodForUser(address _user)
        public
        view
        returns (bool)
    {
        return nextStakingRound.userIsLeaving[_user];
    }

    /**
     * @dev Get current stake for user.
     * @return The amount of stake in the current round for user.
     */
    function getStakeForUserInCurrentPeriod(
        address _user
    ) public view returns (uint256) {
        return currentStakingRound.userStakes[_user];
    }

    /**
     * @dev Get stake for user that will be used in current staking round.
     * @return The amount of stake used in the current round for user.
     */
    function getStakeForUserAtRoundStart(
        address _user
    ) public view returns (uint256) {
        return currentStakingRound.userStakesAtRoundStart[_user];
    }

    /**
     * @dev Get added stake for user.
     * @return The amount of stake added in the next round for user.
     */
    function getAdditionalStakeForUserInNextPeriod(
        address _user
    ) public view returns (uint256) {
        return nextStakingRound.addedUserStakes[_user];
    }

    /**
     * @dev Read users in pool.
     * @return The users in the pool.
     */
    function getUsers()
        public
        view
        returns (address[] memory)
    {
        return users;
    }

    /**
     * @dev Returns index of user address in array. If not found, returns -1.
     * @param _user The user to be searched in array.
     * @param _array The array to be used.
     */
    function _getIndexInArray(
        address _user,
        address[] memory _array
    ) private pure returns (int256) {
        for (uint256 i = 0; i < _array.length; i++) {
            if (_array[i] == _user) {
                return int256(i);
            }
        }

        return -1;
    }

    /**
     * @dev Returns if array contains at least one instance of user.
     * @param _user The user to be searched in array.
     * @param _array The array to be used.
     */
    function _isInArray(
        address _user,
        address[] memory _array
    ) private pure returns (bool) {
        bool isInArray = false;

        for (uint256 i = 0; i < _array.length; i++) {
            if (_array[i] == _user) {
                isInArray = true;
                break;
            }
        }

        return isInArray;
    }

    function _getNextStakingPeriodIndex() private view returns (uint256) {
        return currentStakingRound.roundIndex + 1;
    }

    function _moveStakeToNextPeriod(address _user, uint256 _newStake) private {
        uint256 oldStake = currentStakingRound.userStakes[_user];
        uint256 withdrawn = currentStakingRound.userStakesAtRoundStart[_user]
            .sub(currentStakingRound.userStakes[_user]);

        uint256 updatedStake = _newStake
            .add(nextStakingRound.addedUserStakes[_user])
            .sub(withdrawn);

        currentStakingRound.userStakes[_user] = updatedStake;
        currentStakingRound.userStakesAtRoundStart[_user] = updatedStake;
        nextStakingRound.addedUserStakes[_user] = 0;

        totalUserStake = updatedStake > oldStake
            ? totalUserStake.add(updatedStake.sub(oldStake))
            : totalUserStake.sub(oldStake.sub(updatedStake));
    }

    function _withdrawFromCurrentPeriod(
        address _user,
        uint256 _amount,
        bool _canWithdrawAll
    ) private {
        uint256 stake = getStakeForUserInCurrentPeriod(_user);
        uint256 stakeAfterWithdraw = stake.sub(_amount);

        if (_canWithdrawAll) {
            totalUserStake = totalUserStake.sub(_amount);
        } else {
            _ensureSufficientStakeLeftForUser(_user, stakeAfterWithdraw);
        }

        currentStakingRound.userStakes[_user] = stakeAfterWithdraw;
    }

    function _ensureSufficientStakeLeftForUser(
        address _user,
        uint256 _stakeAfterWithdraw
    ) private view {
        uint256 stakeAtRoundStart = getStakeForUserAtRoundStart(_user);
        uint256 stakeAfterLoss = _computeMaxLossNewStake(stakeAtRoundStart);
        uint256 maxLoss = stakeAtRoundStart.sub(stakeAfterLoss);

        require(
            _stakeAfterWithdraw >= maxLoss,
            "Cannot withdraw more than safe staking amount!"
        );

        require(
            _stakeAfterWithdraw >= poolDefinition.minStakePerUser,
            "Cannot withdraw more than minStakePerUser!"
        );
    }

    function _withdrawFromNextPeriod(
        address _user,
        uint256 _amount
    ) private returns (uint256) {
        uint256 stakeForNextPeriod = getAdditionalStakeForUserInNextPeriod(
            _user
        );

        if (_amount < stakeForNextPeriod) {
            nextStakingRound.addedUserStakes[_user]
                = stakeForNextPeriod.sub(_amount);

            return _amount;
        }

        nextStakingRound.addedUserStakes[_user] = 0;
        return stakeForNextPeriod;
    }

    function _withdrawForUser(
        address _user,
        uint256 _amount,
        bool _canWithdrawAll
    ) public {
        uint256 withdrawnFromNextPeriod
            = _withdrawFromNextPeriod(_user, _amount);

        if (withdrawnFromNextPeriod < _amount) {
            uint256 withdrawFromCurrentPeriod = _amount.sub(withdrawnFromNextPeriod);
            _withdrawFromCurrentPeriod(_user, withdrawFromCurrentPeriod, _canWithdrawAll);
        }

        require(
            token.transfer(_user, _amount),
            "Token transfer failed!"
        );
    }

    function _addPendingUser(address _newUser) private {
        users.push(_newUser);
        _moveStakeToNextPeriod(_newUser, 0);

        currentStakingRound.userIsStaking[_newUser]
            = nextStakingRound.userIsStaking[_newUser];
    }

    function _removeUserAtIndex(uint256 _index) private {
        address userToRemove = users[_index];

        uint256 userBalance = getStakeForUserInCurrentPeriod(userToRemove)
            .add(getAdditionalStakeForUserInNextPeriod(userToRemove));
        bool canWithdrawAll = true;
        _withdrawForUser(userToRemove, userBalance, canWithdrawAll);

        if (users.length > 1) {
            users[_index] = users[users.length.sub(1)]; // changes order in users!
        }
        users.length--;
    }

    function _computeMinOwnerFunds() private view returns (uint256) {
        uint256 maxNewStakeAfterRound = totalUserStake.mul(
            uint256(100).add(poolDefinition.compliantGainPercentage)
        );

        return maxNewStakeAfterRound.sub(totalUserStake);
    }

    function _ensureContractIsFundedForNextRound() private view {
        uint256 minOwnerFunds = _computeMinOwnerFunds();

        require(
            ownerFunds > minOwnerFunds,
            "Pool is not sufficiently funded by owner!"
        );
    }

    function _handleSecondUpdateForUser(address _user) private {
        bool wasCompliant = complianceDataAtIndex
            [currentStakingRound.roundIndex]
            [_user];

        if (!wasCompliant && currentStakingRound.userIsStaking[_user]) {
            uint256 oldStake = getStakeForUserAtRoundStart(_user);
            uint256 newStake = _computeNewNonCompliantStake(oldStake);
            _moveStakeToNextPeriod(_user, newStake);
        }

        _moveUserToNextRound(_user);
    }

    function _computeNewCompliantStake(uint256 _userStake)
        private
        view
        returns (uint256)
    {
        return _userStake
            .mul(uint256(100).add(poolDefinition.compliantGainPercentage))
            .div(100);
    }

    function _computeUseMaxNonCompliancy() private view returns (bool) {
        if (currentStakingRound.totalStakeToSlash == 0) {
            // avoid division by 0
            return true;
        }

        uint256 nonCompliantFactor = currentStakingRound.totalPayout
            .mul(100)
            .div(currentStakingRound.totalStakeToSlash);

        return nonCompliantFactor >=
            poolDefinition.maxNonCompliantPenaltyPercentage;
    }

    function _computeMaxLossNewStake(uint256 _userStake)
        private
        view
        returns (uint256)
    {
        return _userStake.mul(poolDefinition.maxNonCompliantFactor).div(100);
    }

    function _computeNewNonCompliantStake(uint256 _userStake)
        private
        view
        returns (uint256)
    {
        if (currentStakingRound.useMaxNonCompliancy) {
            return _computeMaxLossNewStake(_userStake);
        }

        uint256 totalStakeToSlash = currentStakingRound.totalStakeToSlash;
        uint256 totalPayout = currentStakingRound.totalPayout;

        // TODO totalPayout > totalStakeToSlash ever possible?
        // probably not, because useMaxNonCompliancy would be true
        return _userStake
            .mul(totalStakeToSlash.sub(totalPayout))
            .div(totalStakeToSlash);
    }

    function _moveUserToNextRound(address _user) private {
        uint256 stake = getStakeForUserInCurrentPeriod(_user);

        if (!currentStakingRound.userIsStaking[_user]) {
            currentStakingRound.userStakes[_user]
                = nextStakingRound.addedUserStakes[_user].add(stake);
            nextStakingRound.addedUserStakes[_user] = 0;
        }

        currentStakingRound.userIsStaking[_user]
            = nextStakingRound.userIsStaking[_user];
    }

    function _computeJuriFees() private view returns (uint256) {
        return totalUserStake.mul(poolDefinition.feePercentage).div(100);
    }

    function _handleJuriFees() private {
        require(
            token.transfer(juriAddress, currentStakingRound.juriFees),
            "Juri fees token transfer failed!"
        );
    }

    function _handleUnderwriting() private {
        if (currentStakingRound.useMaxNonCompliancy) {
            uint256 slashedStake = currentStakingRound.totalStakeToSlash
                .mul(poolDefinition.maxNonCompliantFactor)
                .div(100);
            uint256 fundedPayoutFromSlashedStake
                = currentStakingRound.totalStakeToSlash.sub(slashedStake);
            _fundUserStakesFromOwnerFunds(fundedPayoutFromSlashedStake);
        }
    }

    function _fundUserStakesFromOwnerFunds(
        uint256 _fundedPayoutFromSlashedStake
    )
        private
    {
        uint256 underwriterLiability = currentStakingRound.totalPayout
            .sub(_fundedPayoutFromSlashedStake);
        ownerFunds = ownerFunds.sub(underwriterLiability);
    }

    function _setStakingPeriodVariables(uint256 _roundIndex) private {
        currentStakingRound = CurrentStakingRound(
            _roundIndex, Stages.AWAITING_COMPLIANCE_DATA, 0, 0, 0, 0, 0, 0, 0, false
        );

        nextStakingRound = NextStakingRound(
            new address[](0), 0
        );
    }

    function _resetPoolForNextPeriod() private {
        _setStakingPeriodVariables(currentStakingRound.roundIndex + 1);
        _ensureContractIsFundedForNextRound();

        // for next round
        currentStakingRound.juriFees = _computeJuriFees();
        currentStakingRound.totalPayout = currentStakingRound.juriFees;
    }
}