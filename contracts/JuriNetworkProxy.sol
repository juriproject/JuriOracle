pragma solidity 0.5.10;

import "./lib/IERC20.sol";
import "./lib/Ownable.sol";
import "./lib/SafeMath.sol";

import "./JuriBonding.sol";
import "./lib/custom/MaxHeapLibrary.sol";
import "./lib/custom/SkaleFileStorageInterface.sol";

contract JuriNetworkProxy is Ownable {
    using SafeMath for uint256;
    using MaxHeapLibrary for MaxHeapLibrary.heapStruct;

    event RemovedMax(address user, address removedNode);
    event AddedVerifierHash(address user, address node, bytes32 verifierHash);

    event OLD_MAX(bytes32 maxVerifierHash);
    event NEW_MAX(bytes32 maxVerifierHash);

    enum Stages {
        USER_ADDING_HEART_RATE_DATA,
        NODES_ADDING_RESULT_COMMITMENTS,
        NODES_ADDING_RESULT_REVEALS,
        DISSENTING_PERIOD,
        DISSENTS_NODES_ADDING_RESULT_COMMITMENTS,
        DISSENTS_NODES_ADDING_RESULT_REVEALS,
        SLASHING_PERIOD
    }

    struct UserState {
        MaxHeapLibrary.heapStruct verifierHashesMaxHeap;
        int256 complianceDataBeforeDissent;
        int256 userComplianceData;
        bytes32 userWorkoutSignature;
        string userHeartRateDataStoragePath;
        bool dissented;
    }

    struct NodeForUserState {
        bytes32 complianceDataCommitment;
        bool hasRevealed;
        bool givenNodeResult;
        bool hasDissented;
        bool wasAssignedToUser;
    }

    struct NodeState {
        mapping (address => NodeForUserState) nodeForUserStates;
        bool hasRetrievedRewards;
        uint256 activityCount;
    }

    struct JuriRound {
        mapping (address => UserState) userStates;
        mapping (address => NodeState) nodeStates;
        uint256 totalActivityCount;
    }

    /**
     * @dev Reverts if called in incorrect stage.
     * @param _stage The allowed stage for the given function.
     */
    modifier atStage(Stages _stage) {
        require(
            currentStage == _stage,
            "Function cannot be called at this time!"
        );

        _;
    }

    modifier checkIfNextStage() {
        uint256 timeForStage = timesForStages[uint256(currentStage)];

        if (currentStage == Stages.SLASHING_PERIOD) {
            uint256 secondsSinceStart = now.sub(startTime);
            uint256 secondsSinceStartNextPeriod = roundIndex.mul(timeForStage);

            if (secondsSinceStart >= secondsSinceStartNextPeriod) {
                _moveToNextStage();
            }
        } else if (now >= lastStageUpdate.add(timeForStage)) {
            _moveToNextStage();
        }

        _;
    }

    JuriBonding public bonding;
    IERC20 public juriFeesToken;
    SkaleFileStorageInterface public skaleFileStorage;

    Stages public currentStage;
    uint256 public roundIndex;
    uint256 public startTime;
    uint256 public lastStageUpdate;
    uint256 public totalJuriFees;
    uint256 public nodeVerifierCount;
    address[] public registeredJuriStakingPools;
    address[] public dissentedUsers;

    mapping (uint256 => uint256) public timesForStages;
    mapping (address => bool) public isRegisteredJuriStakingPool;
    mapping (uint256 => JuriRound) internal stateForRound;

    constructor(
        IERC20 _juriFeesToken,
        IERC20 _juriToken,
        SkaleFileStorageInterface _skaleFileStorage,
        address _juriFoundation,
        uint256 _timeForAddingHeartRateData,
        uint256 _timeForCommitmentStage,
        uint256 _timeForRevealStage,
        uint256 _timeForDissentStage,
        uint256 _timeForDissentCommitmentStage,
        uint256 _timeForDissentRevealStage,
        uint256 _timeForSlashingStage,
        uint256 _minStakePerNode,
        uint256 _offlinePenalty,
        uint256 _notRevealPenalty,
        uint256 _incorrectResultPenalty,
        uint256 _incorrectDissentPenalty
    ) public {
        timesForStages[uint256(Stages.USER_ADDING_HEART_RATE_DATA)] = _timeForAddingHeartRateData;
        timesForStages[uint256(Stages.NODES_ADDING_RESULT_COMMITMENTS)] = _timeForCommitmentStage;
        timesForStages[uint256(Stages.NODES_ADDING_RESULT_REVEALS)] = _timeForRevealStage;
        timesForStages[uint256(Stages.DISSENTING_PERIOD)] = _timeForDissentStage;
        timesForStages[uint256(Stages.DISSENTS_NODES_ADDING_RESULT_COMMITMENTS)] = _timeForDissentCommitmentStage;
        timesForStages[uint256(Stages.DISSENTS_NODES_ADDING_RESULT_REVEALS)] = _timeForDissentRevealStage;
        timesForStages[uint256(Stages.SLASHING_PERIOD)] = _timeForSlashingStage;

        bonding = new JuriBonding(
            this,
            _juriToken,
            _juriFoundation,
            _minStakePerNode,
            _offlinePenalty,
            _notRevealPenalty,
            _incorrectResultPenalty,
            _incorrectDissentPenalty
        );
        isRegisteredJuriStakingPool[address(bonding)] = true;

        skaleFileStorage = _skaleFileStorage;
        juriFeesToken = _juriFeesToken;
        currentStage = Stages.USER_ADDING_HEART_RATE_DATA;
        roundIndex = 0;
        startTime = now;
        lastStageUpdate = now;
        totalJuriFees = 0;
        nodeVerifierCount = 1;
    }

    // PUBLIC METHODS

    function registerJuriStakingPool(address _poolAddress) public onlyOwner {
        isRegisteredJuriStakingPool[_poolAddress] = true;
        registeredJuriStakingPools.push(_poolAddress);
    }

    function removeJuriStakingPool(address _poolAddress, uint256 _removalIndex) public onlyOwner {
        require(
            registeredJuriStakingPools.length > 0,
            'Registered Juri Staking Pools list is empty!'
        );
        require(
            registeredJuriStakingPools[_removalIndex] == _poolAddress,
            'Removal index must match pool address!'
        );

        isRegisteredJuriStakingPool[_poolAddress] = false;
        registeredJuriStakingPools[_removalIndex]
            = registeredJuriStakingPools[registeredJuriStakingPools.length.sub(1)];
        registeredJuriStakingPools.length--;
    }

    // TODO remove
    function debugIncreaseRoundIndex() public onlyOwner {
        roundIndex++;

        bonding.moveToNextRound(roundIndex);

        dissentedUsers = new address[](0);
        // nodeVerifierCount = bonding.totalNodesCount(roundIndex).div(3); // TODO
    
        // maybe also count only active nodes
        // https://juriproject.slack.com/archives/CHKB3D1GF/p1565926038000200
        nodeVerifierCount = bonding.stakingNodesAddressCount(roundIndex).div(3);
        totalJuriFees = juriFeesToken.balanceOf(address(this));

        currentStage = Stages.USER_ADDING_HEART_RATE_DATA;
    }

    // TODO remove
    function moveToNextStage() public {
        currentStage = Stages((uint256(currentStage) + 1) % 7);
        lastStageUpdate = now;
    }

    // TODO remove
    function moveToUserAddingHeartRateDataStage() public {
        currentStage = Stages.USER_ADDING_HEART_RATE_DATA;
        lastStageUpdate = now;
    }

    function moveToNextRound()
        public
        atStage(Stages.SLASHING_PERIOD)
        checkIfNextStage {
        roundIndex++;

        bonding.moveToNextRound(roundIndex);
    
        dissentedUsers = new address[](0);
        // nodeVerifierCount = bonding.totalNodesCount(roundIndex).div(3);
        nodeVerifierCount = bonding.stakingNodesAddressCount(roundIndex).div(3);
        totalJuriFees = juriFeesToken.balanceOf(address(this));
    }

    function moveToDissentPeriod()
        public
        atStage(Stages.NODES_ADDING_RESULT_REVEALS)
        checkIfNextStage {
        // do nothing
    }

    function moveToSlashingPeriod()
        public
        atStage(Stages.DISSENTS_NODES_ADDING_RESULT_REVEALS)
        checkIfNextStage {
        // do nothing
    }

    function moveFromDissentToNextPeriod()
        public
        atStage(Stages.DISSENTING_PERIOD)
        checkIfNextStage {
        // do nothing
    }

    function addHeartRateDateForPoolUser(
        bytes32 _userWorkoutSignature,
        string memory _heartRateDataStoragePath
    ) public checkIfNextStage atStage(Stages.USER_ADDING_HEART_RATE_DATA) {
        // TODO verify signature, HOW ?

        // TODO optional: enforce storage path fits msg.sender

        uint8 fileStatus
            = skaleFileStorage.getFileStatus(_heartRateDataStoragePath);
        require(
            fileStatus == 2, // => file exists
            "Invalid storage path passed"
        );

        stateForRound[roundIndex]
            .userStates[msg.sender]
            .userWorkoutSignature = _userWorkoutSignature;
        stateForRound[roundIndex]
            .userStates[msg.sender]
            .userHeartRateDataStoragePath = _heartRateDataStoragePath;
    }

    function addWasCompliantDataCommitmentsForUsers(
        address[] memory _users,
        bytes32[] memory _wasCompliantDataCommitments,
        uint256[] memory _proofIndices
    ) public checkIfNextStage atStage(Stages.NODES_ADDING_RESULT_COMMITMENTS) {
        _addWasCompliantDataCommitmentsForUsers(
            _users,
            _wasCompliantDataCommitments,
            _proofIndices
        );
    }

    function addDissentWasCompliantDataCommitmentsForUsers(
        address[] memory _users,
        bytes32[] memory _wasCompliantDataCommitments
        
    ) public
        checkIfNextStage
        atStage(Stages.DISSENTS_NODES_ADDING_RESULT_COMMITMENTS) {
        uint256[] memory _proofIndices = new uint256[](0);

        _addWasCompliantDataCommitmentsForUsers(
            _users,
            _wasCompliantDataCommitments,
            _proofIndices
        );
    }

    function addWasCompliantDataForUsers(
        address[] memory _users,
        bool[] memory _wasCompliantData,
        bytes32[] memory _randomNonces
    ) public checkIfNextStage atStage(Stages.NODES_ADDING_RESULT_REVEALS) {
        _addWasCompliantDataForUsers(
            _users,
            _wasCompliantData,
            _randomNonces
        );
    }

    function addDissentWasCompliantDataForUsers(
        address[] memory _users,
        bool[] memory _wasCompliantData,
        bytes32[] memory _randomNonces
    ) public
        checkIfNextStage
        atStage(Stages.DISSENTS_NODES_ADDING_RESULT_REVEALS) {
        _addWasCompliantDataForUsers(
            _users,
            _wasCompliantData,
            _randomNonces
        );
    }

    function dissentToAcceptedAnswers(address[] memory _users)
        public
        checkIfNextStage
        atStage(Stages.DISSENTING_PERIOD)
    {
        address node = msg.sender;
        uint256 usersToDissentCount = 0;

        require(_users.length > 0, 'Users array cannot be empty!');

        for (uint256 i = 0; i < _users.length; i++) {
            address user = _users[i];

            require(
                _getCurrentStateForNodeForUser(node, user).wasAssignedToUser,
                'You were not assigned to the given user!'
            );

            if (!_getCurrentStateForUser(user).dissented) {
                usersToDissentCount++;
            }

            // TODO only allow if node gave different previous result ?
        }

        require(
            usersToDissentCount > 0,
            "Users were already dissented!"
        );
        address[] memory usersToDissent = new address[](usersToDissentCount);
        uint256 usersToDissentIndex = 0;

        for (uint256 i = 0; i < _users.length; i++) {
            if (!_getCurrentStateForUser(_users[i]).dissented) {
                usersToDissent[usersToDissentIndex] = _users[i];
                usersToDissentIndex++;
            }
        }

        for (uint256 i = 0; i < usersToDissent.length; i++) {
            address user = usersToDissent[i];

            stateForRound[roundIndex].userStates[user].complianceDataBeforeDissent
                = _getCurrentStateForUser(user).userComplianceData;
            stateForRound[roundIndex]
                .userStates[user]
                .dissented = true;
            stateForRound[roundIndex]
                .nodeStates[node]
                .nodeForUserStates[user]
                .hasDissented = true;

            dissentedUsers.push(user);
        }
    }

    function retrieveRoundJuriFees(uint256 _roundIndex) public {
        address node = msg.sender;
        NodeState memory nodeState = stateForRound[_roundIndex].nodeStates[node];
        uint256 activityCount = nodeState.activityCount;

        require(_roundIndex < roundIndex, "Round not yet finished!");
        require(
            !nodeState.hasRetrievedRewards,
            "You already retrieved your rewards this round!"
        );
        require(activityCount > 0, "Node did not participate this round!");

        uint256 multiplier = 1000000;
        uint256 totalNodeActivityCount
            = stateForRound[_roundIndex].totalActivityCount;
        uint256 activityShare = activityCount.mul(multiplier).div(totalNodeActivityCount);
        uint256 juriFeesTokenAmount = totalJuriFees.mul(activityShare).div(multiplier);

        stateForRound[_roundIndex].nodeStates[node].hasRetrievedRewards = true;
        juriFeesToken.transfer(node, juriFeesTokenAmount);
    }

    /// INTERFACE METHODS

    function getUserWorkAssignmentHashes(uint256 _roundIndex, address _user)
        public
        view
        returns (uint256[] memory) {
        return stateForRound[_roundIndex].userStates[_user].verifierHashesMaxHeap.getLowestHashes();
    }

    function getDissented(uint256 _roundIndex, address _user)
        public
        view
        returns (bool) {
        return stateForRound[_roundIndex].userStates[_user].dissented;
    }

    function getComplianceDataBeforeDissent(uint256 _roundIndex, address _user)
        public
        view
        returns (int256) {
        return stateForRound[_roundIndex].userStates[_user].complianceDataBeforeDissent;
    }

    function getHasRevealed(uint256 _roundIndex, address _node, address _user)
        public
        view
        returns (bool) {
        return stateForRound[_roundIndex].nodeStates[_node].nodeForUserStates[_user].hasRevealed;
    }

    function getNodeActivityCount(uint256 _roundIndex, address _node)
        public
        view
        returns (uint256) {
        return stateForRound[_roundIndex].nodeStates[_node].activityCount;
    }

    function getTotalActivityCount(uint256 _roundIndex)
        public
        view
        returns (uint256) {
        return stateForRound[_roundIndex].totalActivityCount;
    }

    function getUserComplianceDataCommitment(
        uint256 _roundIndex,
        address _node,
        address _user
    ) public view returns (bytes32) {
        return stateForRound[_roundIndex].nodeStates[_node].nodeForUserStates[_user].complianceDataCommitment;
    }

    function getGivenNodeResult(
        uint256 _roundIndex,
        address _node,
        address _user
    ) public view returns (bool) {
        return stateForRound[_roundIndex].nodeStates[_node].nodeForUserStates[_user].givenNodeResult;
    }

    function getWasAssignedToUser(
        uint256 _roundIndex,
        address _node,
        address _user
    ) public view returns (bool) {
        return stateForRound[_roundIndex].nodeStates[_node].nodeForUserStates[_user].wasAssignedToUser;
    }

    function getHasDissented(uint256 _roundIndex, address _node, address _user)
        public
        view
        returns (bool) {
        return stateForRound[_roundIndex].nodeStates[_node].nodeForUserStates[_user].hasDissented;
    }

    function getUserComplianceData(uint256 _roundIndex, address _user)
        public
        view
        returns (int256) {
        require(
            isRegisteredJuriStakingPool[msg.sender],
            "Pool is not registered to receive new data!"
        );

        return stateForRound[_roundIndex].userStates[_user].userComplianceData;
    }

    function getUserWorkoutSignature(uint256 _roundIndex, address _user)
        public
        view
        returns (bytes32) {
        return stateForRound[_roundIndex].userStates[_user].userWorkoutSignature;
    }

    /**
     * @dev Read registered staking pools.
     * @return The registered staking pools.
     */
    function getRegisteredJuriStakingPools()
        public
        view
        returns (address[] memory)
    {
        return registeredJuriStakingPools;
    }

    function getDissentedUsers()
        public
        view
        returns (address[] memory)
    {
        return dissentedUsers;
    }

    function getCurrentHighestHashForUser(address _user)
        public
        view
        returns (uint256) {
        MaxHeapLibrary.heapStruct storage verifierHashesMaxHeap
            = _getCurrentStateForUser(_user).verifierHashesMaxHeap;

        uint256 hashesCount = verifierHashesMaxHeap.getLength();
        uint256 highestHash = hashesCount > 0
            ? verifierHashesMaxHeap.getMax().value
            : 0;

        return highestHash;
    }

    /// PRIVATE METHODS

    function _increaseActivityCountForNode(
        address _node,
        uint256 _activityCount
    ) internal {
        stateForRound[roundIndex]
            .nodeStates[_node]
            .activityCount = _getCurrentStateForNode(_node)
                .activityCount
                .add(_activityCount);
        stateForRound[roundIndex].totalActivityCount
            = stateForRound[roundIndex].totalActivityCount.add(_activityCount);
    }

    function _decrementActivityCountForNode(address _node) internal {
        stateForRound[roundIndex]
            .nodeStates[_node]
            .activityCount
                = _getCurrentStateForNode(_node).activityCount.sub(1);
        stateForRound[roundIndex].totalActivityCount
            = stateForRound[roundIndex].totalActivityCount.sub(1);
    }

    function _moveToNextStage() internal {
        if (currentStage == Stages.DISSENTING_PERIOD) {
            currentStage = dissentedUsers.length > 0
                ? Stages.DISSENTS_NODES_ADDING_RESULT_COMMITMENTS
                : Stages.SLASHING_PERIOD;
        } else {
            currentStage = Stages((uint256(currentStage) + 1) % 7);
        }

        lastStageUpdate = now;
    }

    function _addWasCompliantDataCommitmentsForUsers(
        address[] memory _users,
        bytes32[] memory _wasCompliantDataCommitments,
        uint256[] memory _proofIndices
    ) internal {
        address node = msg.sender;

        require(
            _users.length == _wasCompliantDataCommitments.length,
            'Users length should match wasCompliantDataCommitments!'
        );
        require(
            _users.length == _proofIndices.length
            || currentStage == Stages.DISSENTS_NODES_ADDING_RESULT_COMMITMENTS,
            'Users length should match proofIndices!'
        );

        uint256 validUserCount = 0;

        for (uint256 i = 0; i < _users.length; i++) {
            address user = _users[i];
            bytes32 wasCompliantCommitment = _wasCompliantDataCommitments[i];

            NodeForUserState memory nodeForUserState
                = _getCurrentStateForNodeForUser(node, user);
            require(
                !nodeForUserState.hasRevealed,
                "You already added the complianceData!"
            );

            if (_getCurrentStateForUser(user).dissented
                || (_verifyValidComplianceAddition(user, node, _proofIndices[i])
                && currentStage == Stages.NODES_ADDING_RESULT_COMMITMENTS)
            ) {
                validUserCount++;

                if (nodeForUserState.complianceDataCommitment == 0x0) {
                    stateForRound[roundIndex]
                        .nodeStates[node]
                        .nodeForUserStates[user]
                        .complianceDataCommitment
                            = wasCompliantCommitment;
                }
            }
        }
        
        require(validUserCount > 0, 'No valid users to add!');

        if (currentStage == Stages.NODES_ADDING_RESULT_COMMITMENTS) {
            // dont count dissent rounds as activity
            // because nodes have an incentive anyways to participate
            // due to not getting offline slashed
            _increaseActivityCountForNode(node, validUserCount);
        }
    }

    function _addWasCompliantDataForUsers(
        address[] memory _users,
        bool[] memory _wasCompliantData,
        bytes32[] memory _randomNonces
    ) internal {
        address node = msg.sender;

        require(
            _users.length == _wasCompliantData.length,
            "The users length must match the compliance data length!"
        );
        require(
            _users.length == _randomNonces.length,
            "The users length must match the randomNonces data length!"
        );

        for (uint256 i = 0; i < _users.length; i++) {
            address user = _users[i];
            NodeForUserState memory nodeForUserState
                = _getCurrentStateForNodeForUser(node, user);
            bool wasCompliant = _wasCompliantData[i];
            bytes32 commitment = nodeForUserState.complianceDataCommitment;
            bytes32 randomNonce = _randomNonces[i];
            bytes32 verifierNonceHash = keccak256(
                abi.encodePacked(wasCompliant, randomNonce)
            );

            require(
                _getCurrentStateForUser(user).dissented
                    || nodeForUserState.wasAssignedToUser,
                'You were not assigned to the user!'
            );
            require(
                !nodeForUserState.hasRevealed,
                "You already added the complianceData!"
            );
            stateForRound[roundIndex].nodeStates[msg.sender].nodeForUserStates[user].hasRevealed = true;
    
            require(
                verifierNonceHash == commitment,
                "The passed random nonce does not match!"
            );

            stateForRound[roundIndex]
                .nodeStates[node]
                .nodeForUserStates[user]
                .givenNodeResult = wasCompliant;
    
            int256 currentCompliance = _getCurrentStateForUser(user)
                .userComplianceData;
            stateForRound[roundIndex].userStates[user].userComplianceData
                = wasCompliant ? currentCompliance + 1 : currentCompliance - 1;
        }
    }

    function _getStateForCurrentRound()
        internal
        view
        returns (JuriRound storage) {
        return stateForRound[roundIndex];
    }

    function _getCurrentStateForUser(address _user)
        internal
        view
        returns (UserState storage) {
        return stateForRound[roundIndex].userStates[_user];
    }

    function _getCurrentStateForNode(address _node)
        internal
        view
        returns (NodeState storage) {
        return stateForRound[roundIndex].nodeStates[_node];
    }

    function _getCurrentStateForNodeForUser(address _node, address _user)
        internal
        view
        returns (NodeForUserState storage) {
        return stateForRound[roundIndex].nodeStates[_node].nodeForUserStates[_user];
    }

    function _verifyValidComplianceAddition(
        address _user,
        address _node,
        uint256 _proofIndex
    ) internal returns (bool) {
        UserState storage userState = _getCurrentStateForUser(_user);

        uint256 currentHighestHash = _getCurrentHighestHashForUser(_user);
        bytes32 userWorkoutSignature = userState.userWorkoutSignature;
        uint256 bondedStake = bonding.getBondedStakeOfNode(_node);

        require(
            userWorkoutSignature != 0x0,
            "The user did not add any heart rate data!"
        );

        require(
            _proofIndex < bondedStake.div(1e18),
            "The proof index must be smaller than the bonded stake per 1e18!"
        );

        uint256 verifierHash = uint256(
            keccak256(abi.encodePacked(userWorkoutSignature, _node, _proofIndex))
        );

        MaxHeapLibrary.heapStruct storage verifierHashesMaxHeap
            = userState.verifierHashesMaxHeap;

        if (verifierHashesMaxHeap.getLength() < nodeVerifierCount // TODO count node quality ??
            || verifierHash < currentHighestHash) {
            _addNewVerifierHashForUser(_node, _user, verifierHash);

            if (verifierHashesMaxHeap.getLength() > nodeVerifierCount) {
                emit OLD_MAX(bytes32(_getCurrentHighestHashForUser(_user)));
                _removeMaxVerifierHashForUser(_user);
                emit NEW_MAX(bytes32(_getCurrentHighestHashForUser(_user)));
            }

            return true;
        }

        return false;
    }

    function _getCurrentHighestHashForUser(address _user)
        internal
        view
        returns (uint256) {
        MaxHeapLibrary.heapStruct storage verifierHashesMaxHeap
            = _getCurrentStateForUser(_user).verifierHashesMaxHeap;

        uint256 hashesCount = verifierHashesMaxHeap.getLength();
        uint256 highestHash = hashesCount > 0
            ? verifierHashesMaxHeap.getMax().value
            : 0;

        return highestHash;
    }

    function _removeMaxVerifierHashForUser(
        address _user
    ) internal {
        MaxHeapLibrary.heapStruct storage verifierHashesMaxHeap
            = _getCurrentStateForUser(_user).verifierHashesMaxHeap;
        address removedNode = verifierHashesMaxHeap.removeMax();

        emit RemovedMax(_user, removedNode);

        stateForRound[roundIndex]
            .nodeStates[removedNode]
            .nodeForUserStates[_user]
            .wasAssignedToUser = false;
        stateForRound[roundIndex]
            .nodeStates[removedNode]
            .nodeForUserStates[_user]
            .complianceDataCommitment = 0x0;

        _decrementActivityCountForNode(removedNode);
    }

    function _addNewVerifierHashForUser(
        address _node,
        address _user,
        uint256 _verifierHash
    ) internal {        
        MaxHeapLibrary.heapStruct storage verifierHashesMaxHeap
            = _getCurrentStateForUser(_user).verifierHashesMaxHeap;
        verifierHashesMaxHeap.insert(_node, _verifierHash);

        emit AddedVerifierHash(_user, _node, bytes32(_verifierHash));

        stateForRound[roundIndex]
            .nodeStates[_node]
            .nodeForUserStates[_user]
            .wasAssignedToUser = true;
    }
}