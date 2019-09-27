pragma solidity 0.5.10;

import "./JuriNetworkProxy.sol";
import "./lib/custom/LinkedListLib.sol";

import "./lib/IERC20.sol";
import "./lib/Ownable.sol";
import "./lib/SafeMath.sol";

contract JuriBonding is Ownable {
    using LinkedListLib for LinkedListLib.LinkedList;
    using SafeMath for uint256;

    address constant HEAD = address(0);
    bool constant PREV = false;
    bool constant NEXT = true;
    uint256 constant OFFLINE_SLASH = 0;
    uint256 constant NOT_REVEAL_SLASH = 1;
    uint256 constant INCORRECT_RESULT_SLASH = 2;
    uint256 constant INCORRECT_DISSENT_SLASH = 3;

    struct ValidStakeAfter {
        uint256 oldStake;
        uint256 newStake;
        uint256 afterRoundId;
    }

    struct AllowedWithdrawalAfter {
        uint256 amount;
        uint256 minRoundIndex;
    }

    event SlashedStake(
        uint256 roundIndex,
        address from,
        address to,
        uint256 penalty
    );

    JuriNetworkProxy public proxy;
    IERC20 public token;
    LinkedListLib.LinkedList stakingNodes;

    address public juriFoundation;
    uint256 public juriFoundationFunds;

    mapping (address => AllowedWithdrawalAfter) public allowedWithdrawalAmounts;
    mapping (uint256 => uint256) public stakingNodesAddressCount;
    mapping (uint256 => uint256) public totalNodesCount;
    mapping (address => ValidStakeAfter) public bondedStakes;
    mapping (uint256 => mapping (address => mapping (uint256 => bool))) public hasBeenSlashed;
    mapping (uint256 => mapping (address => bool)) public changedStakeInRound;
    
    uint256 public totalBonded;
    uint256 public minStakePerNode;
    uint256 public offlinePenalty;
    uint256 public notRevealPenalty;
    uint256 public incorrectResultPenalty;
    uint256 public incorrectDissentPenalty;

    constructor(
        JuriNetworkProxy _proxy,
        IERC20 _token,
        address _juriFoundation,
        uint256 _minStakePerNode,
        uint256 _offlinePenalty,
        uint256 _notRevealPenalty,
        uint256 _incorrectResultPenalty,
        uint256 _incorrectDissentPenalty
    ) public {
        proxy = _proxy;
        token = _token;
        juriFoundation = _juriFoundation;
        minStakePerNode = _minStakePerNode;
        offlinePenalty = _offlinePenalty;
        notRevealPenalty = _notRevealPenalty;
        incorrectResultPenalty = _incorrectResultPenalty;
        incorrectDissentPenalty = _incorrectDissentPenalty;

        juriFoundationFunds = 0;
    }

    function slashStakeForBeingOffline(address _toSlashNode, address _dissentedUser) public {
        require(
            proxy.currentStage() == JuriNetworkProxy.Stages.SLASHING_PERIOD,
            'Proxy must be in slashing stage!'
        );
        uint256 roundIndex = proxy.roundIndex();

        require(
            !hasBeenSlashed[roundIndex][_dissentedUser][OFFLINE_SLASH],
            "The node has already been slashed for being offline!"
        );
        hasBeenSlashed[roundIndex][_dissentedUser][OFFLINE_SLASH] = true;

        bool userWasDissented = proxy.getDissented(roundIndex, _dissentedUser);
        bytes32 commitment = proxy.getUserComplianceDataCommitment(roundIndex, _toSlashNode, _dissentedUser);

        require(userWasDissented, "The passed user was not dissented!");
        require(
            commitment == 0x0,
            "The passed node was not offline!"
        );

        _slashStake(roundIndex, _toSlashNode, msg.sender, offlinePenalty);
    }

    function slashStakeForNotRevealing(address _toSlashNode, address _notRevealedUser) public {
        require(
            proxy.currentStage() == JuriNetworkProxy.Stages.SLASHING_PERIOD,
            'Proxy must be in slashing stage!'
        );
        uint256 roundIndex = proxy.roundIndex();

        require(
            !hasBeenSlashed[roundIndex][_notRevealedUser][NOT_REVEAL_SLASH],
            "The node has already been slashed for not revealing!"
        );
        hasBeenSlashed[roundIndex][_notRevealedUser][NOT_REVEAL_SLASH] = true;

        bool wasAssignedToUser = proxy.getWasAssignedToUser(
            roundIndex,
            _toSlashNode,
            _notRevealedUser
        );
        
        require(
            wasAssignedToUser,
            "The passed node was not assigned to passed user!"
        );
        require(
            !proxy.getHasRevealed(roundIndex, _toSlashNode, _notRevealedUser),
            "The passed node has revealed his commitment!"
        );
        
        _slashStake(roundIndex, _toSlashNode, msg.sender, notRevealPenalty);
    }

    function slashStakeForIncorrectResult(address _toSlashNode, address _incorrectResultUser) public {
        require(
            proxy.currentStage() == JuriNetworkProxy.Stages.SLASHING_PERIOD,
            'Proxy must be in slashing stage!'
        );
        uint256 roundIndex = proxy.roundIndex();

        require(
            !hasBeenSlashed[roundIndex][_incorrectResultUser][INCORRECT_RESULT_SLASH],
            "The node has already been slashed for an incorrect result!"
        );
        hasBeenSlashed[roundIndex][_incorrectResultUser][INCORRECT_RESULT_SLASH] = true;

        bool givenAnswer = proxy.getGivenNodeResult(roundIndex, _toSlashNode, _incorrectResultUser);
        bool acceptedAnswer = proxy.getUserComplianceData(roundIndex, _incorrectResultUser) > 0;

        require(
            givenAnswer != acceptedAnswer,
            "The passed node did not give an incorrect result!"
        );

        _slashStake(roundIndex, _toSlashNode, msg.sender, incorrectResultPenalty);
    }

    function slashStakeForIncorrectDissenting(address _toSlashNode, address _incorrectDissentUser) public {
        require(
            proxy.currentStage() == JuriNetworkProxy.Stages.SLASHING_PERIOD,
            'Proxy must be in slashing stage!'
        );
        uint256 roundIndex = proxy.roundIndex();

        require(
            !hasBeenSlashed[roundIndex][_incorrectDissentUser][INCORRECT_DISSENT_SLASH],
            "The node has already been slashed for an incorrect dissent!"
        );
        hasBeenSlashed[roundIndex][_incorrectDissentUser][INCORRECT_DISSENT_SLASH] = true;

        bool hasDissented = proxy.getHasDissented(roundIndex, _toSlashNode, _incorrectDissentUser);
        bool previousAnswer = proxy.getComplianceDataBeforeDissent(roundIndex, _incorrectDissentUser) > 0;
        bool acceptedAnswer = proxy.getUserComplianceData(roundIndex, _incorrectDissentUser) > 0;

        require(
            hasDissented,
            "The passed node did not dissent to the passed user!"
        );

        require(
            previousAnswer == acceptedAnswer,
            "The dissent from passed node was correct!"
        );

        _slashStake(roundIndex, _toSlashNode, msg.sender, incorrectDissentPenalty);
    }

    function withdrawAllowedStakes() public {
        uint256 roundIndex = proxy.roundIndex();
        AllowedWithdrawalAfter memory allowed = allowedWithdrawalAmounts[msg.sender];

        require(
            roundIndex >= allowed.minRoundIndex,
            "Not yet allowed to withdraw!"
        );

        allowedWithdrawalAmounts[msg.sender] = AllowedWithdrawalAfter(0, 0);
        require(
            token.transfer(msg.sender, allowed.amount),
            "Not enough tokens in bonding contract for withdrawal!"
        );
    }

    function bondStake(uint256 _amount) public {
        uint256 roundIndex = proxy.roundIndex();
        uint256 nextRoundIndex = proxy.roundIndex() + 1;

        require(
            token.transferFrom(msg.sender, address(this), _amount),
            "Not enough tokens for bonding!"
        );
        require(
            !changedStakeInRound[roundIndex][msg.sender],
            "You may only bond or unbond once per round!"
        );

        changedStakeInRound[roundIndex][msg.sender] = true;

        ValidStakeAfter memory currentStakeAfter = bondedStakes[msg.sender];
        uint256 oldNodeStake;

        if (currentStakeAfter.afterRoundId <= roundIndex) {
            oldNodeStake = currentStakeAfter.newStake;
        } else {
            oldNodeStake = currentStakeAfter.oldStake;
        }

        if (oldNodeStake == 0) {
            stakingNodes.insert(HEAD, msg.sender, PREV);
            stakingNodesAddressCount[nextRoundIndex]
                = stakingNodesAddressCount[nextRoundIndex] > 0
                    ? stakingNodesAddressCount[nextRoundIndex].add(1)
                    : stakingNodesAddressCount[roundIndex].add(1);
        }

        uint256 newNodeStake = oldNodeStake.add(_amount);
        uint256 oldNodeQualityCount = oldNodeStake.div(minStakePerNode);

        bondedStakes[msg.sender]
            = ValidStakeAfter(oldNodeStake, newNodeStake, nextRoundIndex);
        totalBonded = totalBonded.add(_amount);

        require(
            newNodeStake >= minStakePerNode,
            "You must bond at least the minimum allowance!"
        );

        uint256 newNodeQualityCount = newNodeStake.div(minStakePerNode);
        uint256 addedNodeQuality = newNodeQualityCount.sub(oldNodeQualityCount);

        uint256 oldNextTotalNodesCount = totalNodesCount[nextRoundIndex] > 0
            ? totalNodesCount[nextRoundIndex]
            : totalNodesCount[roundIndex];
        totalNodesCount[nextRoundIndex] = oldNextTotalNodesCount.add(addedNodeQuality);
    }

    function unbondStake(uint256 _amount) public {
        uint256 roundIndex = proxy.roundIndex();
        uint256 nextRoundIndex = proxy.roundIndex() + 1;

        require(
            !changedStakeInRound[roundIndex][msg.sender],
            "You may only bond or unbond once per round!"
        );
        changedStakeInRound[roundIndex][msg.sender] = true;

        ValidStakeAfter memory currentStakeAfter = bondedStakes[msg.sender];
        uint256 oldNodeStake;

        if (currentStakeAfter.afterRoundId <= roundIndex) {
            oldNodeStake = currentStakeAfter.newStake;
        } else {
            oldNodeStake = currentStakeAfter.oldStake;
        }

        require(
            _amount > 0,
            "Please pass an amount above 0!"
        );
        require(
            oldNodeStake >= _amount,
            "You don't have enough stake to unbond!"
        );

        uint256 newNodeStake = oldNodeStake.sub(_amount);
        uint256 oldNodeQualityCount = oldNodeStake.div(minStakePerNode);
        require(
            newNodeStake >= minStakePerNode || newNodeStake == 0,
            "You may only unbond up to the minimum allowance or all stake!"
        );
        
        allowedWithdrawalAmounts[msg.sender]
            = AllowedWithdrawalAfter(_amount, nextRoundIndex);
        bondedStakes[msg.sender]
            = ValidStakeAfter(oldNodeStake, newNodeStake, nextRoundIndex);
        totalBonded = totalBonded.sub(_amount);

        uint256 newNodeQualityCount = newNodeStake.div(minStakePerNode);
        uint256 removedNodeQuality = oldNodeQualityCount.sub(newNodeQualityCount);

        uint256 oldNextTotalNodesCount = totalNodesCount[nextRoundIndex] > 0
            ? totalNodesCount[nextRoundIndex]
            : totalNodesCount[roundIndex];
        totalNodesCount[nextRoundIndex]
            = oldNextTotalNodesCount.sub(removedNodeQuality);

        if (newNodeStake == 0) {
            stakingNodes.remove(msg.sender);

            stakingNodesAddressCount[nextRoundIndex]
                = stakingNodesAddressCount[nextRoundIndex] > 0
                    ? stakingNodesAddressCount[nextRoundIndex].sub(1)
                    : stakingNodesAddressCount[roundIndex].sub(1);
        }
    }

    function withdrawJuriFoundationStake(uint256 _amount) external {
        require(
            msg.sender == juriFoundation,
            'Only juriFoundation may withdraw their funds!'
        );

        require(
            _amount <= juriFoundationFunds,
            'Not enough funds to withdraw from jurFoundationFunds!'
        );

        juriFoundationFunds = juriFoundationFunds.sub(_amount);
        token.transfer(juriFoundation, _amount);
    }

    function moveToNextRound(uint256 _newRoundIndex) external onlyOwner {
        totalNodesCount[_newRoundIndex] = totalNodesCount[_newRoundIndex] > 0
            ? totalNodesCount[_newRoundIndex]
            : totalNodesCount[_newRoundIndex.sub(1)];
        stakingNodesAddressCount[_newRoundIndex]
            = stakingNodesAddressCount[_newRoundIndex] > 0
                ? stakingNodesAddressCount[_newRoundIndex]
                : stakingNodesAddressCount[_newRoundIndex.sub(1)];
    }

    function getBondedStakeOfNode(
        address _node
    ) public view returns (uint256) {
        uint256 roundIndex = proxy.roundIndex();

        ValidStakeAfter memory currentStakeAfter = bondedStakes[_node];

        return currentStakeAfter.afterRoundId <= roundIndex
            ? currentStakeAfter.newStake
            : currentStakeAfter.oldStake;
    }

    function getAllStakingNodes() public view returns (address[] memory) {
        uint256 stakingNodesCount = stakingNodes.sizeOf();
        require(stakingNodesCount > 0, 'No nodes available!');

        address[] memory stakingNodesList = new address[](stakingNodesCount);

        stakingNodesList[0] = stakingNodes.list[HEAD][NEXT];

        for (uint256 i = 1; i < stakingNodesCount; i++) {
            stakingNodesList[i]
                = stakingNodes.list[stakingNodesList[i.sub(1)]][NEXT];
        }

        return stakingNodesList;
    }

    function receiveNodesAtIndex(
        uint256 _nodeIndex,
        uint256 _nodesCount
    ) public view returns (address[] memory) {
        require(
            _nodesCount > 0,
            'Passed nodes count must be greater than 0!'
        );

        address[] memory resultNodesList = new address[](_nodesCount);

        address node = stakingNodes.list[HEAD][NEXT];

        for (uint256 i = 1; i <= _nodeIndex + _nodesCount; i++) {
            require(
                node != HEAD,
                'Nodes list too short for given node index or count!'
            );

            if (i > _nodeIndex) {
                resultNodesList[i.sub(_nodeIndex).sub(1)] = node;
            }

            node = stakingNodes.list[node][NEXT];
        }

        return resultNodesList;
    }

    function _slashStake(
        uint256 _roundIndex,
        address _from,
        address _to,
        uint256 _penalty
    ) private returns (uint256) {
        uint256 nextRoundIndex = _roundIndex + 1;
        ValidStakeAfter memory stakeAfterFrom = bondedStakes[_from];
        ValidStakeAfter memory stakeAfterTo = bondedStakes[_to];

        uint256 stakeFrom = stakeAfterFrom.afterRoundId <= _roundIndex
            ? stakeAfterFrom.newStake
            : stakeAfterFrom.oldStake;
        uint256 stakeTo = stakeAfterTo.afterRoundId <= _roundIndex
            ? stakeAfterTo.newStake
            : stakeAfterTo.oldStake;

        uint256 slashedStake = stakeFrom.mul(_penalty).div(100);
        uint256 slashedStakeHalf = slashedStake.div(2);

        uint256 newStakeFrom = stakeAfterFrom.newStake.sub(slashedStake);
        uint256 newStakeTo = stakeAfterTo.newStake.add(slashedStakeHalf);

        bondedStakes[_from]
            = ValidStakeAfter(stakeFrom, newStakeFrom, nextRoundIndex);
        bondedStakes[_to]
            = ValidStakeAfter(stakeTo, newStakeTo, nextRoundIndex);
        juriFoundationFunds = juriFoundationFunds
            .add(slashedStakeHalf);

        emit SlashedStake(_roundIndex, _from, _to, _penalty);
    }
}