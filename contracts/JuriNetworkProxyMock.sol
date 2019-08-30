pragma solidity 0.5.10;

import "./lib/IERC20.sol";
import "./lib/SafeMath.sol";

import "./lib/custom/MaxHeapLibrary.sol";
import "./JuriBonding.sol";
import "./JuriNetworkProxy.sol";

contract JuriNetworkProxyMock {
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
        bool hasRevealed;
        bytes32 complianceDataCommitment;
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

    JuriBonding public bonding;
    IERC20 public juriFeesToken;
    SkaleFileStorageInterface public skaleFileStorage;

    Stages public currentStage;
    uint256 public roundIndex;
    uint256 public startTime;
    uint256 public lastStageUpdate;
    uint256 public totalJuriFees;
    uint256 public nodeVerifierCount;
    address[] public dissentedUsers;

    mapping (uint256 => uint256) public timesForStages;
    mapping (address => bool) public isRegisteredJuriStakingPool;
    mapping (uint256 => JuriRound) private stateForRound;

    constructor(
        IERC20 _juriFeesToken,
        IERC20 _juriToken,
        address _juriFoundation,
        uint256 _minStakePerNode,
        uint256 _offlinePenalty,
        uint256 _notRevealPenalty,
        uint256 _incorrectResultPenalty,
        uint256 _incorrectDissentPenalty
    ) public {
        bonding = new JuriBonding(
            JuriNetworkProxy(address(this)),
            _juriToken,
            _juriFoundation,
            _minStakePerNode,
            _offlinePenalty,
            _notRevealPenalty,
            _incorrectResultPenalty,
            _incorrectDissentPenalty
        );

        juriFeesToken = _juriFeesToken;
        currentStage = Stages.USER_ADDING_HEART_RATE_DATA;
        roundIndex = 0;
        startTime = now;
        lastStageUpdate = now;
        totalJuriFees = 0;
        nodeVerifierCount = 1;
    }

    function moveToNextStage() public {
        currentStage = Stages((uint256(currentStage) + 1) % 7);
    }

    function incrementRoundIndex() public {
        roundIndex++;

        bonding.moveToNextRound(roundIndex);
    }

    function increaseNodeActivity(address _node) public {
        stateForRound[roundIndex].nodeStates[_node].activityCount++;
        stateForRound[roundIndex].totalActivityCount++;
    }

    function addComplianceDataForUsers(
        address[] memory _users,
        int256[] memory _complianceData
    ) public {
        for (uint256 i = 0; i < _users.length; i++) {
            stateForRound[roundIndex].userStates[_users[i]].userComplianceData
                = _complianceData[i];
        }
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
        return stateForRound[_roundIndex].userStates[_user].userComplianceData;
    }
}