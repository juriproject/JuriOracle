pragma solidity 0.5.10;

import "./JuriNetworkProxy.sol";

contract JuriNetworkProxyMock is JuriNetworkProxy {
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
    ) JuriNetworkProxy(
        _juriFeesToken,
        _juriTokenSide,
        _juriTokenMain,
        _skaleMessageProxySide,
        _skaleMessageProxyAddressMain,
        _skaleFileStorage,
        _juriFoundation,
        _times,
        _penalties,
        _minStakePerNode
    ) public { }

    function moveToNextStage() public {
        lastStageUpdate = now;

        if (currentStage == Stages.DISSENTING_PERIOD) {
            currentStage = dissentedUsers.length > 0
                ? Stages.DISSENTS_NODES_ADDING_RESULT_COMMITMENTS
                : Stages.SLASHING_PERIOD;
        } else {
            currentStage = Stages((uint256(currentStage) + 1) % 7);
        }
    }

    function moveToUserAddingHeartRateDataStage() public {
        currentStage = Stages.USER_ADDING_HEART_RATE_DATA;
        lastStageUpdate = now;
    }

    function moveToAddingCommitmentStage() public {
        currentStage = Stages.NODES_ADDING_RESULT_COMMITMENTS;
        lastStageUpdate = now;
    }

    function addHeartRateDateForPoolUser(
        bytes32 _userWorkoutSignature,
        string memory _heartRateDataStoragePath
    ) public atStage(Stages.USER_ADDING_HEART_RATE_DATA) {
        stateForRound[roundIndex]
            .userStates[msg.sender]
            .userWorkoutSignature = _userWorkoutSignature;
        stateForRound[roundIndex]
            .userStates[msg.sender]
            .userHeartRateDataStoragePath = _heartRateDataStoragePath;
    }

    function debugMoveToNextRound()
        public
        view
        atStage(Stages.SLASHING_PERIOD)
        returns (bytes memory) {
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

        return data;
    }

    function debugIncreaseRoundIndex() public onlyOwner {
        roundIndex++;
        bonding.moveToNextRound(roundIndex);
        dissentedUsers = new address[](0);
        nodeVerifierCount = bonding.stakingNodesAddressCount(roundIndex).div(3);
        currentStage = Stages.USER_ADDING_HEART_RATE_DATA;
    }

    function moveTimeToNextStage() public {
        uint256 timeForStage = timesForStages[uint256(currentStage)];
        lastStageUpdate = now.sub(timeForStage);
    }
}