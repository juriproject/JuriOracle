pragma solidity 0.5.10;

import "./lib/ERC20.sol";
import "./lib/Ownable.sol";
import "./lib/SafeMath.sol";

import "./SkaleMessageProxy.sol";

contract JuriToken is ERC20, Ownable {
    using SafeMath for uint256;

    // JuriNetworkProxy public proxy;
    // JuriBonding public bonding;
    address public skaleMessageProxy;

    uint256 public currentRoundIndex;
    uint256 public proxyRoundIndex;
    uint256 public inflationChange;
    uint256 public targetBondingRatePer1000000;
    uint256 public inflation;
    uint256 public currentMintedTokens;
    uint256 public currentMintableTokens;
    uint256 public totalBonded;

    uint256 public totalActivityCount;
    mapping (address => uint32) public nodesActivityCount;

    mapping (uint256 => mapping (address => bool)) public haveRetrievedRewards;

    constructor() public {
        skaleMessageProxy = address(new SkaleMessageProxy(address(this)));
    }

    function setTargetBondingRate(uint256 _targetBondingRatePer1000000) public onlyOwner {
        targetBondingRatePer1000000 = _targetBondingRatePer1000000;
    }

    function setInflationChange(uint256 _inflationChange)
        public
        onlyOwner {
        inflationChange = _inflationChange;
    }

    function setCurrentRewardTokens() public {
        require(
            currentRoundIndex < proxyRoundIndex,
            "The round is not yet finished!"
        );

        currentRoundIndex = proxyRoundIndex;

        _setInflation();

        currentMintableTokens = totalSupply().mul(inflation).div(100);
        currentMintedTokens = 0;
    }

    function retrieveRoundInflationRewards() public {
        require(
            !haveRetrievedRewards[currentRoundIndex][msg.sender],
            "You have already retrieved your rewards for this round!"
        );

        // uint256 nodeActivityCount = proxy.getNodeActivityCount(currentRoundIndex.sub(1), msg.sender);
        // uint256 totalActivityCount = proxy.getTotalActivityCount(currentRoundIndex.sub(1));
        uint256 nodeActivityCount = nodesActivityCount[msg.sender];

        uint256 activityShare = nodeActivityCount.mul(1000000).div(totalActivityCount);
        uint256 mintAmount = currentMintableTokens.mul(activityShare).div(1000000);
        currentMintedTokens = currentMintedTokens.add(mintAmount);

        haveRetrievedRewards[currentRoundIndex][msg.sender] = true;
        _mint(msg.sender, mintAmount);
    }

    function updateActivityList(
        uint256 _totalActivityCount,
        uint256 _totalBonded,
        address[] memory _nodeAddressList,
        uint32[] memory _nodeActivityList
    ) public {
        require(
            msg.sender == skaleMessageProxy,
            'Function can only be called by SkaleMessageProxy!'
        );

        totalActivityCount = _totalActivityCount;
        totalBonded = _totalBonded;

        for (uint256 i = 0; i < _nodeAddressList.length; i++) {
            nodesActivityCount[_nodeAddressList[i]] = _nodeActivityList[i];
        }

        proxyRoundIndex++;
    }

    function updateActivityList(
        address[] memory _nodeAddressList,
        uint32[] memory _nodeActivityList
    ) public {
        require(
            msg.sender == skaleMessageProxy,
            'Function can only be called by SkaleMessageProxy!'
        );

        for (uint256 i = 0; i < _nodeAddressList.length; i++) {
            nodesActivityCount[_nodeAddressList[i]] = _nodeActivityList[i];
        }
    }

    function _setInflation() private {
        // uint256 totalBonded = bonding.totalBonded();
        uint256 currentBondingRate = totalBonded.mul(1000000).div(totalSupply());

        if (currentBondingRate < targetBondingRatePer1000000) {
            inflation = inflation.add(inflationChange);
        } else if (currentBondingRate > targetBondingRatePer1000000) {
            inflation = inflationChange > inflation
                ? 0 : inflation.sub(inflationChange);
        }
    }
}