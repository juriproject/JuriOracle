pragma solidity 0.5.10;

import "./lib/IERC20.sol";
import "./lib/Ownable.sol";
import "./lib/SafeMath.sol";

import "./JuriBonding.sol";
import "./SkaleMessageProxyInterface.sol";
import "./lib/custom/MaxHeapLibrary.sol";
import "./lib/custom/SkaleFileStorageInterface.sol";

contract JuriNetworkProxy is Ownable {
    using SafeMath for uint256;
    using MaxHeapLibrary for MaxHeapLibrary.heapStruct;

    event RemovedMax(address user, address removedNode);
    event AddedVerifierHash(address user, address node, bytes32 verifierHash);

    event OLD_MAX(bytes32 maxVerifierHash);
    event NEW_MAX(bytes32 maxVerifierHash);

    uint256 constant MAX_NODES_PER_UPDATE = 2; // TODO

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
        uint32 activityCount;
    }

    struct JuriRound {
        mapping (address => UserState) userStates;
        mapping (address => NodeState) nodeStates;
        uint256 nodesUpdateIndex;
        uint32 totalActivityCount;
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
    SkaleMessageProxyInterface public skaleMessageProxy;
    SkaleFileStorageInterface public skaleFileStorage;
    address public juriTokenAddress;

    Stages public currentStage;
    uint256 public roundIndex;
    uint256 public startTime;
    uint256 public lastStageUpdate;
    uint256 public nodeVerifierCount;
    address[] public registeredJuriStakingPools;
    address[] public dissentedUsers;

    mapping (uint256 => mapping (address => uint256)) public totalJuriFeesAtWithdrawalTimes;
    mapping (uint256 => uint256) public totalJuriFees;
    mapping (uint256 => uint256) public timesForStages;
    mapping (address => bool) public isRegisteredJuriStakingPool;
    mapping (uint256 => JuriRound) internal stateForRound;

    constructor(
        IERC20 _juriFeesToken,
        IERC20 _juriToken,
        SkaleMessageProxyInterface _skaleMessageProxy,
        SkaleFileStorageInterface _skaleFileStorage,
        address _juriFoundation,
        uint256[] memory _times,
        uint256[] memory _penalties,
        uint256 _minStakePerNode
    ) public {
        timesForStages[uint256(Stages.USER_ADDING_HEART_RATE_DATA)] = _times[0];
        timesForStages[uint256(Stages.NODES_ADDING_RESULT_COMMITMENTS)] = _times[1];
        timesForStages[uint256(Stages.NODES_ADDING_RESULT_REVEALS)] = _times[2];
        timesForStages[uint256(Stages.DISSENTING_PERIOD)] = _times[3];
        timesForStages[uint256(Stages.DISSENTS_NODES_ADDING_RESULT_COMMITMENTS)] = _times[4];
        timesForStages[uint256(Stages.DISSENTS_NODES_ADDING_RESULT_REVEALS)] = _times[5];
        timesForStages[uint256(Stages.SLASHING_PERIOD)] = _times[6];

        bonding = new JuriBonding(
            this,
            _juriToken,
            _juriFoundation,
            _minStakePerNode,
            _penalties[0],
            _penalties[1],
            _penalties[2],
            _penalties[3]
        );
        isRegisteredJuriStakingPool[address(bonding)] = true;

        skaleMessageProxy = _skaleMessageProxy;
        skaleFileStorage = _skaleFileStorage;
        juriTokenAddress = address(_juriToken);
        juriFeesToken = _juriFeesToken;
        currentStage = Stages.USER_ADDING_HEART_RATE_DATA;
        roundIndex = 0;
        startTime = now;
        lastStageUpdate = now;
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
        currentStage = Stages.USER_ADDING_HEART_RATE_DATA;
    }

    // TODO remove
    function moveToNextStage() public {
        currentStage = Stages((uint256(currentStage) + 1) % 7);
        lastStageUpdate = now;

        if (currentStage == Stages.USER_ADDING_HEART_RATE_DATA) {
            roundIndex++;

            bonding.moveToNextRound(roundIndex);
            dissentedUsers = new address[](0);
            nodeVerifierCount = bonding.stakingNodesAddressCount(roundIndex).div(3);
        }
    }

    // TODO remove
    function moveToUserAddingHeartRateDataStage() public {
        currentStage = Stages.USER_ADDING_HEART_RATE_DATA;
        lastStageUpdate = now;
    }

    // TODO What if not called in time?
    function moveToNextRound(uint256 nodesCount)
        public
        atStage(Stages.SLASHING_PERIOD)
        checkIfNextStage {
        uint256 nodesUpdateIndex = stateForRound[roundIndex].nodesUpdateIndex;
        uint32 totalActivity
            = stateForRound[roundIndex].totalActivityCount;
        uint256 totalBonded = bonding.totalBonded();

        uint256 totalNodesCount = bonding.stakingNodesAddressCount(roundIndex);
        uint256 updateNodesCount = totalNodesCount > MAX_NODES_PER_UPDATE
            ? MAX_NODES_PER_UPDATE
            : totalNodesCount;

        address[] memory nodesToUpdate
            = bonding.receiveNodesAtIndex(nodesUpdateIndex, MAX_NODES_PER_UPDATE);
        uint32[] memory nodesActivity = new uint32[](updateNodesCount);
        
        for (uint256 i = 0; i < updateNodesCount; i++) {
            nodesActivity[i]
                = _getCurrentStateForNode(nodesToUpdate[i]).activityCount;
        }

        bool isFirstAddition = nodesUpdateIndex == 0;

        bytes memory data = _encodeIMABytes(
            isFirstAddition,
            isFirstAddition ? uint32(stateForRound[roundIndex].totalActivityCount) : 0,
            isFirstAddition ? bonding.totalBonded() : 0,
            nodesToUpdate,
            nodesActivity
        );

        skaleMessageProxy.postOutgoingMessage(
            'Mainnet', 
            juriTokenAddress, // TODO
            0, // amount ?
            address(0), // to ? 
            data
            // bytes calldata bls
        );

        stateForRound[roundIndex].nodesUpdateIndex
            = nodesUpdateIndex.add(updateNodesCount);

        if (stateForRound[roundIndex].nodesUpdateIndex >= totalNodesCount) {
            roundIndex++;
            bonding.moveToNextRound(roundIndex);
            dissentedUsers = new address[](0);
            // nodeVerifierCount = bonding.totalNodesCount(roundIndex).div(3);
            nodeVerifierCount = bonding.stakingNodesAddressCount(roundIndex).div(3);
        }
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
        uint256 activityCount = uint256(nodeState.activityCount);
        uint256 totalJuriFeesForRound = totalJuriFees[_roundIndex];
        uint256 alreadyWithdrawnJuriFees
            = totalJuriFeesAtWithdrawalTimes[_roundIndex][msg.sender];
        uint256 newFeesToWithdraw = totalJuriFeesForRound.sub(alreadyWithdrawnJuriFees);

        require(_roundIndex < roundIndex, "Round not yet finished!");
        require(activityCount > 0, "Node did not participate this round!");
        require(newFeesToWithdraw > 0, "Nothing available to withdraw!");

        uint256 multiplier = 1000000;
        uint256 totalNodeActivityCount
            = uint256(stateForRound[_roundIndex].totalActivityCount);
        uint256 activityShare = activityCount.mul(multiplier).div(totalNodeActivityCount);
        uint256 juriFeesTokenAmount = newFeesToWithdraw
            .mul(activityShare)
            .div(multiplier);

        totalJuriFeesAtWithdrawalTimes[_roundIndex][msg.sender] = totalJuriFeesForRound;
        stateForRound[_roundIndex].nodeStates[node].hasRetrievedRewards = true;
        juriFeesToken.transfer(node, juriFeesTokenAmount);
    }

    /// INTERFACE METHODS

    function handleJuriFees(
        uint256 _roundIndex,
        uint256 _juriFeesTokenAmount
    ) external {
        require(
            juriFeesToken.transferFrom(msg.sender, address(this), _juriFeesTokenAmount),
            'JuriStakingPool does not have sufficient Juri fee tokens!'
        );

        totalJuriFees[_roundIndex]
            = totalJuriFees[_roundIndex].add(_juriFeesTokenAmount);
    }

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

    function getHeartRateDataStoragePath(uint256 _roundIndex, address _user)
        public
        view
        returns (string memory) {
        return stateForRound[_roundIndex].userStates[_user].userHeartRateDataStoragePath;
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
    function _encodeIMABytes(
        bool _isFirstAddition,
        uint32 _totalActivity,
        uint256 _totalBonded,
        address[] memory _nodes,
        uint32[] memory _nodeActivities
    ) public pure returns (bytes memory) {
        uint8 isFirstAddition = _isFirstAddition ? 1 : 0;
        uint256 firstAdditionAddedDataLength = 37;
        uint256 nodesCount = _nodes.length;
        uint256 nodesDataLength = nodesCount * 24;
        uint256 totalDataLength = nodesDataLength
            + (_isFirstAddition ? firstAdditionAddedDataLength : 1);
        bytes memory result = new bytes(totalDataLength);

        uint256 beginningDest;
        
        assembly {
            beginningDest := add(result, 32)
            mstore8(beginningDest, isFirstAddition)
        }

        if (_isFirstAddition) {
            uint256 totalActivityDest = beginningDest + 1;
            uint256 totalBondedDest = totalActivityDest + 4;

            assembly {
                mstore8(totalActivityDest, shr(24, _totalActivity))
                mstore8(add(totalActivityDest, 1), shr(16, _totalActivity))
                mstore8(add(totalActivityDest, 2), shr(8, _totalActivity))
                mstore8(add(totalActivityDest, 3), _totalActivity)
                mstore(totalBondedDest, _totalBonded)
            }
        }

        uint256 nodesDest = _isFirstAddition
            ? beginningDest + firstAdditionAddedDataLength
            : beginningDest + 1;
        uint256 nodesActivityDest = nodesDest + 20 * _nodes.length;

        for (uint256 i = 0; i < _nodes.length; i++) {
            address node = _nodes[i];
            uint256 nodeDest = nodesDest + 20 * i;
            
            assembly {
                mstore8(nodeDest, shr(152, node))
                mstore8(add(nodeDest, 1), shr(144, node))
                mstore8(add(nodeDest, 2), shr(136, node))
                mstore8(add(nodeDest, 3), shr(128, node))
                mstore8(add(nodeDest, 4), shr(120, node))
                mstore8(add(nodeDest, 5), shr(112, node))
                mstore8(add(nodeDest, 6), shr(104, node))
                mstore8(add(nodeDest, 7), shr(96, node))
                mstore8(add(nodeDest, 8), shr(88, node))
                mstore8(add(nodeDest, 9), shr(80, node))
                mstore8(add(nodeDest, 10), shr(72, node))
                mstore8(add(nodeDest, 11), shr(64, node))
                mstore8(add(nodeDest, 12), shr(56, node))
                mstore8(add(nodeDest, 13), shr(48, node))
                mstore8(add(nodeDest, 14), shr(40, node))
                mstore8(add(nodeDest, 15), shr(32, node))
                mstore8(add(nodeDest, 16), shr(24, node))
                mstore8(add(nodeDest, 17), shr(16, node))
                mstore8(add(nodeDest, 18), shr(8, node))
                mstore8(add(nodeDest, 19), node)
            }
        }
        
        for (uint256 i = 0; i < _nodeActivities.length; i++) {
            uint256 nodeActivity = uint256(_nodeActivities[i]);
            uint256 nodeActivityDest = nodesActivityDest + 4 * i;
    
            assembly {
                mstore8(nodeActivityDest, shr(24, nodeActivity))
                mstore8(add(nodeActivityDest, 1), shr(16, nodeActivity))
                mstore8(add(nodeActivityDest, 2), shr(8, nodeActivity))
                mstore8(add(nodeActivityDest, 3), nodeActivity)
            }
        }

        return result;
    }

    function _increaseActivityCountForNode(
        address _node,
        uint32 _activityCount
    ) internal {
        stateForRound[roundIndex]
            .nodeStates[_node]
            .activityCount = _getCurrentStateForNode(_node)
                .activityCount + _activityCount;
        stateForRound[roundIndex].totalActivityCount
            = stateForRound[roundIndex].totalActivityCount + _activityCount;
    }

    function _decrementActivityCountForNode(address _node) internal {
        stateForRound[roundIndex]
            .nodeStates[_node]
            .activityCount
                = _getCurrentStateForNode(_node).activityCount - 1;
        stateForRound[roundIndex].totalActivityCount
            = stateForRound[roundIndex].totalActivityCount - 1;
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
            _increaseActivityCountForNode(node, uint32(validUserCount));
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