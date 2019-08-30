pragma solidity 0.5.10;

import "./lib/ERC20.sol";
import "./lib/Ownable.sol";
import "./lib/SafeMath.sol";

import "./JuriBonding.sol";
import "./JuriNetworkProxy.sol";

contract JuriToken is ERC20, Ownable {
    using SafeMath for uint256;

    JuriNetworkProxy public proxy;
    JuriBonding public bonding;

    uint256 public currentRoundIndex;
    uint256 public inflationChange;
    uint256 public targetBondingRatePer1000000;
    uint256 public inflation;
    uint256 public currentMintedTokens;
    uint256 public currentMintableTokens;

    mapping (uint256 => mapping (address => bool)) public haveRetrievedRewards;

    function setTargetBondingRate(uint256 _targetBondingRatePer1000000) public onlyOwner {
        targetBondingRatePer1000000 = _targetBondingRatePer1000000;
    }

    function setInflationChange(uint256 _inflationChange)
        public
        onlyOwner {
        inflationChange = _inflationChange;
    }

    function setCurrentRewardTokens() public {
        uint256 roundIndex = proxy.roundIndex();
        require(
            roundIndex > currentRoundIndex,
            "The round is not yet finished!"
        );

        currentRoundIndex++;

        _setInflation();

        currentMintableTokens = totalSupply().mul(inflation).div(100);
        currentMintedTokens = 0;
    }

    function retrieveRoundInflationRewards() public {
        require(
            !haveRetrievedRewards[currentRoundIndex][msg.sender],
            "You have already retrieved your rewards for this round!"
        );

        uint256 nodeActivityCount = proxy.getNodeActivityCount(currentRoundIndex.sub(1), msg.sender);
        uint256 totalActivityCount = proxy.getTotalActivityCount(currentRoundIndex.sub(1));
        uint256 activityShare = nodeActivityCount.mul(1000000).div(totalActivityCount);

        uint256 mintAmount = currentMintableTokens.mul(activityShare).div(1000000);
        currentMintedTokens = currentMintedTokens.add(mintAmount);

        haveRetrievedRewards[currentRoundIndex][msg.sender] = true;
        _mint(msg.sender, mintAmount);
    }

    function _setInflation() private {
        uint256 totalBonded = bonding.totalBonded();
        uint256 currentBondingRate = totalBonded.mul(1000000).div(totalSupply());

        if (currentBondingRate < targetBondingRatePer1000000) {
            inflation = inflation.add(inflationChange);
        } else if (currentBondingRate > targetBondingRatePer1000000) {
            inflation = inflationChange > inflation
                ? 0 : inflation.sub(inflationChange);
        }
    }
}