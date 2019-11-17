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

    uint256 constant MAX_NODES_PER_UPDATE = 10; // TODO

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
        uint256 proofIndicesCount;
        bool hasRevealed;
        bool givenNodeResult;
        bool hasDissented;
        bool wasAssignedToUser;
    }

    struct NodeState {
        mapping (address => NodeForUserState) nodeForUserStates;
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

        if (currentStage == Stages.USER_ADDING_HEART_RATE_DATA) {
            uint256 secondsSinceStart = now.sub(startTime);
            uint256 secondsSinceStartNextPeriod = roundIndex.mul(timeForStage);

            if (secondsSinceStart >= secondsSinceStartNextPeriod) {
                _moveToNextStage();
            }
        } else if (currentStage == Stages.SLASHING_PERIOD) {
            // cannot automatically move to next stage as we need the correct
            // update logic for all nodes via postOutgoingMessage
            require(
                now >= lastStageUpdate.add(timeForStage),
                'You cannot move to the next round before slashing period is finished!'
            );
        } else if (now >= lastStageUpdate.add(timeForStage)) {
            _moveToNextStage();
        }

        _;
    }

    JuriBonding public bonding;
    IERC20 public juriFeesToken;
    SkaleMessageProxyInterface public skaleMessageProxySide;
    address public skaleMessageProxyAddressMain;
    SkaleFileStorageInterface public skaleFileStorage;
    address public juriTokenMainAddress;

    Stages public currentStage;
    uint256 public roundIndex;
    uint256 public startTime;
    uint256 public lastStageUpdate;
    uint256 public nodeVerifierCount;
    address[] public registeredJuriStakingPools; // no out-of-gas because array only read in view function
    address[] public dissentedUsers; // no out-of-gas because array only read in view function

    mapping (uint256 => mapping (address => uint256)) public totalJuriFeesAtWithdrawalTimes;
    mapping (uint256 => uint256) public totalJuriFees;
    mapping (uint256 => uint256) public timesForStages;
    mapping (address => bool) public isRegisteredJuriStakingPool;
    mapping (uint256 => JuriRound) internal stateForRound;

    constructor(
        IERC20 _juriFeesToken,
        IERC20 _juriTokenSide,
        IERC20 _juriTokenMain,
        SkaleMessageProxyInterface _skaleMessageProxySide,
        address _skaleMessageProxyAddressMain,
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
            _juriTokenSide,
            _juriFoundation,
            _minStakePerNode,
            _penalties[0],
            _penalties[1],
            _penalties[2],
            _penalties[3]
        );
        isRegisteredJuriStakingPool[address(bonding)] = true;

        skaleMessageProxySide = _skaleMessageProxySide;
        skaleMessageProxyAddressMain = _skaleMessageProxyAddressMain;
        skaleFileStorage = _skaleFileStorage;
        juriTokenMainAddress = address(_juriTokenMain);
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

    // TODO What if not called in time?
    function moveToNextRound()
        public
        atStage(Stages.SLASHING_PERIOD) {
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
            isFirstAddition ? totalActivity : 0,
            isFirstAddition ? totalBonded : 0,
            nodesToUpdate,
            nodesActivity
        );

        skaleMessageProxySide.postOutgoingMessage(
            'Mainnet', 
            skaleMessageProxyAddressMain, // dstContract
            0, // amount
            juriTokenMainAddress, // to
            data
            // bytes calldata bls
        );

        stateForRound[roundIndex].nodesUpdateIndex
            = nodesUpdateIndex.add(updateNodesCount);

        if (stateForRound[roundIndex].nodesUpdateIndex >= totalNodesCount) {
            roundIndex++;
            currentStage = Stages.USER_ADDING_HEART_RATE_DATA;

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
        uint256[] memory _flatProofIndices,
        uint256[] memory _proofIndicesCutoffs
    ) public checkIfNextStage atStage(Stages.NODES_ADDING_RESULT_COMMITMENTS) {
        uint256[][] memory proofIndices = _receiveMultiDimensionalProofIndices(
            _flatProofIndices,
            _proofIndicesCutoffs
        ); // Solidity doesnt support passing multi-dimensional array yet

        _addWasCompliantDataCommitmentsForUsers(
            _users,
            _wasCompliantDataCommitments,
            proofIndices
        );
    }

    function addDissentWasCompliantDataCommitmentsForUsers(
        address[] memory _users,
        bytes32[] memory _wasCompliantDataCommitments
        
    ) public
        checkIfNextStage
        atStage(Stages.DISSENTS_NODES_ADDING_RESULT_COMMITMENTS) {
        uint256[][] memory _proofIndices = new uint256[][](0);

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
        bool isVotingStakeBased = false;

        _addWasCompliantDataForUsers(
            _users,
            _wasCompliantData,
            _randomNonces,
            isVotingStakeBased
        );
    }

    function addDissentWasCompliantDataForUsers(
        address[] memory _users,
        bool[] memory _wasCompliantData,
        bytes32[] memory _randomNonces
    ) public
        checkIfNextStage
        atStage(Stages.DISSENTS_NODES_ADDING_RESULT_REVEALS) {
        bool isVotingStakeBased = true;

        _addWasCompliantDataForUsers(
            _users,
            _wasCompliantData,
            _randomNonces,
            isVotingStakeBased
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

    function getProofIndicesCount(
        uint256 _roundIndex,
        address _node,
        address _user
    ) public view returns (uint256) {
        return stateForRound[_roundIndex].nodeStates[_node].nodeForUserStates[_user].proofIndicesCount;
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

    /// INTERNAL METHODS
    function _encodeIMABytes(
        bool _isFirstAddition,
        uint32 _totalActivity,
        uint256 _totalBonded,
        address[] memory _nodes,
        uint32[] memory _nodeActivities
    ) internal pure returns (bytes memory) {
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

    function _incrementActivityCountForNode(NodeState storage _nodeState) internal {
        _nodeState.activityCount = _nodeState.activityCount + 1;
        stateForRound[roundIndex].totalActivityCount
            = stateForRound[roundIndex].totalActivityCount + 1;
    }

    function _decrementActivityCountForNode(
        NodeState storage _nodeState
    ) internal {
        uint32 oldActivityCount = _nodeState.activityCount;
        uint32 oldTotalActivityCount = stateForRound[roundIndex].totalActivityCount;

        _nodeState.activityCount = oldActivityCount - 1;
        stateForRound[roundIndex].totalActivityCount = oldTotalActivityCount - 1;

        require(
            _nodeState.activityCount < oldActivityCount,
            'Sub underflow when decrementing activity count!'
        );

        require(
            stateForRound[roundIndex].totalActivityCount < oldTotalActivityCount,
            'Sub underflow when decrementing total activity count!'
        );
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
        uint256[][] memory _proofIndices
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

        uint256 bondedStake = bonding.getBondedStakeOfNode(node);

        for (uint256 i = 0; i < _users.length; i++) {
            address user = _users[i];
            bytes32 wasCompliantCommitment = _wasCompliantDataCommitments[i];

            _addValidUser(
                user,
                node,
                wasCompliantCommitment,
                _proofIndices[i],
                bondedStake
            );
        }
        
        // TODO no valid users added -> revert
    }

    function _assignProofIndexForNodeToUser(
        NodeForUserState storage _nodeForUserState,
        bytes32 _wasCompliantCommitment
    ) internal {
        _nodeForUserState.complianceDataCommitment = _wasCompliantCommitment;
        _nodeForUserState.wasAssignedToUser = true;
        _nodeForUserState.proofIndicesCount = _nodeForUserState.proofIndicesCount + 1;
    }

    function _removeOneUserFromNode(
        NodeForUserState storage _nodeForUserState
    ) internal {
        require(
            _nodeForUserState.proofIndicesCount > 0,
            'Trying to remove node from user that is already empty!'
        );

        _nodeForUserState.proofIndicesCount
            = _nodeForUserState.proofIndicesCount.sub(1);

        if (_nodeForUserState.proofIndicesCount == 0) {
            _nodeForUserState.wasAssignedToUser = false;
            _nodeForUserState.complianceDataCommitment = 0x0;
        }
    }

    function _addWasCompliantDataForUsers(
        address[] memory _users,
        bool[] memory _wasCompliantData,
        bytes32[] memory _randomNonces,
        bool _isVotingStakeBased
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
        
        uint256 bondedStake = bonding.getBondedStakeOfNode(node);
        uint256 nodeStakeCount = bondedStake.div(1e18);

        for (uint256 i = 0; i < _users.length; i++) {
            address user = _users[i];
            NodeForUserState storage nodeForUserState
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
            nodeForUserState.hasRevealed = true;
    
            require(
                verifierNonceHash == commitment,
                "The passed random nonce does not match!"
            );

            nodeForUserState.givenNodeResult = wasCompliant;

            int256 currentCompliance = _getCurrentStateForUser(user)
                .userComplianceData;
            int256 complianceDataChange = _isVotingStakeBased
                ? int256(nodeStakeCount)
                : int256(nodeForUserState.proofIndicesCount);
            stateForRound[roundIndex].userStates[user].userComplianceData
                = wasCompliant ?
                    currentCompliance + complianceDataChange
                    : currentCompliance - complianceDataChange;
        }
    }

    function _receiveMultiDimensionalProofIndices(
        uint256[] memory _flatProofIndices,
        uint256[] memory _proofIndicesCutoffs
    ) internal returns (uint256[][] memory) {
        uint256[][] memory proofIndices = new uint256[][](_proofIndicesCutoffs.length + 1);
        uint256 lastCutoffIndex = 0;

        for (uint256 i = 0; i < proofIndices.length - 1; i++) {
            proofIndices[i] = new uint256[](
                _proofIndicesCutoffs[i] - (lastCutoffIndex)
            );

            for (uint256 j = 0; j < proofIndices[i].length; j++) {
                proofIndices[i][j] = _flatProofIndices[lastCutoffIndex + j];
            }

            lastCutoffIndex = _proofIndicesCutoffs[i];
        }
        
        proofIndices[proofIndices.length - 1] = new uint256[](
            _flatProofIndices.length - lastCutoffIndex
        );

        for (uint256 j = 0; j < proofIndices[proofIndices.length - 1].length; j++) {
            proofIndices[proofIndices.length - 1][j] = _flatProofIndices[lastCutoffIndex + j];
        }

        return proofIndices;
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

    function _addValidUser(
        address _user,
        address _node,
        bytes32 _wasCompliantCommitment,
        uint256[] memory _proofIndices,
        uint256 _bondedStake
    ) internal {
        UserState storage userState = _getCurrentStateForUser(_user);
        NodeState storage nodeState = stateForRound[roundIndex]
            .nodeStates[_node];
        NodeForUserState storage nodeForUserState = nodeState
            .nodeForUserStates[_user];

        uint256 currentHighestHash = _getCurrentHighestHashForUser(_user);
        bytes32 userWorkoutSignature = userState.userWorkoutSignature;

        require(
            userWorkoutSignature != 0x0,
            "The user did not add any heart rate data!"
        );

        for (uint256 i = 0; i < _proofIndices.length; i++) {
            uint256 proofIndex = _proofIndices[i];
            require(
                proofIndex < _bondedStake.div(1e18),
                "The proof index must be smaller than the bonded stake per 1e18!"
            );

            uint256 verifierHash = uint256(
                keccak256(abi.encodePacked(userWorkoutSignature, _node, proofIndex))
            );

            MaxHeapLibrary.heapStruct storage verifierHashesMaxHeap
                = userState.verifierHashesMaxHeap;

            if (verifierHashesMaxHeap.getLength() >= nodeVerifierCount // TODO count node quality ??
                && verifierHash >= currentHighestHash) {
                continue;
            }

            _addNewVerifierHashForUser(_node, _user, verifierHash);
            _incrementActivityCountForNode(nodeState);
            _assignProofIndexForNodeToUser(nodeForUserState, _wasCompliantCommitment);

            if (verifierHashesMaxHeap.getLength() > nodeVerifierCount) {
                emit OLD_MAX(bytes32(_getCurrentHighestHashForUser(_user)));
                _removeMaxVerifierHashForUser(_user);
                emit NEW_MAX(bytes32(_getCurrentHighestHashForUser(_user)));
            }
        }
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
    ) internal returns (bool) {
        MaxHeapLibrary.heapStruct storage verifierHashesMaxHeap
            = _getCurrentStateForUser(_user).verifierHashesMaxHeap;
        address removedNode = verifierHashesMaxHeap.removeMax();
        emit RemovedMax(_user, removedNode);
        
        NodeState storage nodeState = stateForRound[roundIndex]
            .nodeStates[removedNode];
        NodeForUserState storage nodeForUserState = nodeState
            .nodeForUserStates[_user];

        _removeOneUserFromNode(nodeForUserState);
        _decrementActivityCountForNode(nodeState);
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
    }
}