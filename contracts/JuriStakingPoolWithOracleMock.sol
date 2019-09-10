pragma solidity 0.5.10;

import "./JuriStakingPoolWithOracle.sol";

contract JuriStakingPoolWithOracleMock is JuriStakingPoolWithOracle {
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
    ) JuriStakingPoolWithOracle(
        _proxy,
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
    ) public { }

    function insertUsers(address[] memory _users) public {
        for (uint256 i = 0; i < _users.length; i++) {
            users.push(_users[i]);
        }
    }

    function handleJuriFees(uint256 _roundIndex, uint256 _juriFees) external {
        token.approve(address(proxy), _juriFees);
        proxy.handleJuriFees(_roundIndex, _juriFees);
    }
}