pragma solidity 0.5.10;

import "./JuriNetworkProxy.sol";
import "./JuriStakingPool.sol";

contract JuriStakingPoolWithOracle is JuriStakingPool {
    JuriNetworkProxy public proxy;

    constructor(
        JuriNetworkProxy _proxy,
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
    ) JuriStakingPool(
        _token,
        _startTime,
        _periodLength,
        _feePercentage,
        _compliantGainPercentage,
        _maxNonCompliantPenaltyPercentage,
        _minStakePerUser,
        _maxStakePerUser,
        _maxTotalStake,
        _juriAddress
    ) public {
        proxy = _proxy;
    }

    /**
     * @dev Add user's compliancy data for current or past periods.
     * @param _updateIterationCount The number defining the max for how much compliance
     * data will be passed in a single function call to prevent out-of-gas errors.
     */
    function checkNewAddedComplianceData(uint256 _updateIterationCount)
        public
        onlyOwner
        atStage(Stages.AWAITING_COMPLIANCE_DATA)
    {
        uint256 nextStakingPeriodEndTime = poolDefinition.startTime.add(
            currentStakingRound.roundIndex.mul(poolDefinition.periodLength)
        );
        require(
            now > nextStakingPeriodEndTime,
            "Can only add new data after end of periodLength!"
        );

        require(
            proxy.roundIndex() >= currentStakingRound.roundIndex,
            "The results for the round are not available yet!"
        );

        for (
            uint256 i = currentStakingRound.addComplianceDataIndex;
            i < users.length && i <
                currentStakingRound.addComplianceDataIndex
                    .add(_updateIterationCount);
            i++
        ) {
            address user = users[i];
            bool wasCompliant = proxy.getUserComplianceData(
                currentStakingRound.roundIndex,
                user
            ) >= 0;

            complianceDataAtIndex[complianceDataIndex][user] = wasCompliant;
        }

        currentStakingRound.addComplianceDataIndex
            = currentStakingRound.addComplianceDataIndex
                .add(_updateIterationCount);

        if (currentStakingRound.addComplianceDataIndex >= users.length) {
            complianceDataIndex++;
            currentStakingRound.stage = Stages.AWAITING_FIRST_UPDATE;
        }
    }

    function _handleJuriFees() private {
        token.approve(address(proxy), currentStakingRound.juriFees);
        proxy.handleJuriFees(
            currentStakingRound.roundIndex,
            currentStakingRound.juriFees
        );
    }
}