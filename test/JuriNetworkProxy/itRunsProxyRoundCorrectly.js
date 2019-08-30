const { expect } = require('chai')
const { BN, ether, shouldFail, time } = require('openzeppelin-test-helpers')
const Web3Utils = require('web3-utils')

const ERC20Mintable = artifacts.require('./lib/ERC20Mintable.sol')
const JuriBonding = artifacts.require('./JuriBonding.sol')
const JuriNetworkProxy = artifacts.require('./JuriNetworkProxy.sol')
const SkaleFileStorageMock = artifacts.require('./SkaleFileStorageMock.sol')

const {
  findLowestHashProofIndexes,
  runDissentRound,
  runFirstHalfOfRound,
  runSetupRound,
} = require('../helpers/RoundHelpers')

const { duration, increase } = time

const itRunsProxyRoundCorrectly = async addresses => {
  describe('when running a round', async () => {
    let bonding,
      incorrectDissentPenalty,
      incorrectResultPenalty,
      juriNode1,
      juriNode2,
      juriNode3,
      juriNode4,
      juriNode5,
      juriNode6,
      networkProxy,
      notRevealPenalty,
      poolUser1,
      poolUser2,
      poolUser3,
      poolUser4,
      skaleFileStorage,
      offlinePenalty,
      juriToken

    beforeEach(async () => {
      poolUser1 = addresses[0]
      poolUser2 = addresses[1]
      poolUser3 = addresses[2]
      poolUser4 = addresses[3]
      juriNode1 = addresses[4]
      juriNode2 = addresses[5]
      juriNode3 = addresses[6]
      juriNode4 = addresses[7]
      juriNode5 = addresses[8]
      juriNode6 = addresses[9]
      juriFoundation = addresses[9]

      offlinePenalty = new BN(10)
      notRevealPenalty = new BN(20)
      incorrectResultPenalty = new BN(35)
      incorrectDissentPenalty = new BN(40)
      skaleFileStorage = await SkaleFileStorageMock.new()
      juriFeesToken = await ERC20Mintable.new()
      juriToken = await ERC20Mintable.new()
      networkProxy = await JuriNetworkProxy.new(
        juriFeesToken.address,
        juriToken.address,
        skaleFileStorage.address,
        juriFoundation,
        duration.days(7),
        duration.hours(1),
        duration.hours(1),
        duration.hours(1),
        duration.hours(1),
        duration.hours(1),
        duration.hours(1),
        ether('1000'),
        offlinePenalty,
        notRevealPenalty,
        incorrectResultPenalty,
        incorrectDissentPenalty
      )
      bonding = await JuriBonding.at(await networkProxy.bonding())

      await Promise.all(
        addresses
          .slice(0, 10)
          .map(address => juriToken.mint(address, ether('1000000')))
      )
      await Promise.all(
        addresses
          .slice(4, 10)
          .map(node =>
            juriToken
              .approve(bonding.address, ether('10000'), { from: node })
              .then(() => bonding.bondStake(ether('10000'), { from: node }))
          )
      )

      await networkProxy.registerJuriStakingPool(poolUser1)
      await networkProxy.debugIncreaseRoundIndex()

      await runSetupRound({
        node: juriNode1,
        user: poolUser1,
        proxy: networkProxy,
      })
    })

    it('runs the round correctly', async () => {
      const nodes = [juriNode1, juriNode2, juriNode3, juriNode4]
      const users = [poolUser1, poolUser2, poolUser3, poolUser4]
      const wasCompliantData = [true, false, false, true]
      const randomNonces = [
        '0x48656c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100',
        '0x58656c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100',
        '0x68656c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100',
        '0x78656c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100',
      ]
      const commitments = [
        Web3Utils.soliditySha3(wasCompliantData[0], randomNonces[0]),
        Web3Utils.soliditySha3(wasCompliantData[1], randomNonces[1]),
        Web3Utils.soliditySha3(wasCompliantData[2], randomNonces[2]),
        Web3Utils.soliditySha3(wasCompliantData[3], randomNonces[3]),
      ]

      const lowestProofIndexesWithHashes = [...Array(4).keys()].map(i => {
        const { lowestHashes, proofIndexes } = findLowestHashProofIndexes({
          bondedStake: 100,
          node: nodes[i],
        })

        return {
          lowestHashes: lowestHashes.map(
            index => '0x' + index.toString(16).padStart(64, '0')
          ),
          proofIndexes,
        }
      })

      const lowestHashes = lowestProofIndexesWithHashes.map(a => a.lowestHashes)
      const proofIndexes = lowestProofIndexesWithHashes.map(a => a.proofIndexes)

      await runFirstHalfOfRound({
        proxy: networkProxy,
        commitments,
        lowestHashes,
        nodes,
        proofIndexes,
        randomNonces,
        users,
        wasCompliantData,
      })

      await increase(duration.hours(1).add(duration.minutes(5)))
      await networkProxy.moveToDissentPeriod()
      await increase(duration.hours(1).add(duration.minutes(5)))
      await networkProxy.moveFromDissentToNextPeriod()
      await increase(duration.hours(1).add(duration.minutes(5)))
      await networkProxy.moveToNextRound()

      for (let i = 0; i < users.length; i++) {
        const wasCompliant = (await networkProxy.getUserComplianceData(
          2,
          users[i]
        )).gt(new BN(0))

        expect(wasCompliant).to.be.equal(wasCompliantData[i])
      }
    })

    it('runs the round correctly with multiple proof indexes per node', async () => {
      const users = [poolUser1, poolUser1, poolUser2]

      for (let i = 1; i < users.length; i++) {
        await networkProxy.addHeartRateDateForPoolUser(
          `0x00156c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100`,
          `0x01/123-heartRateData.xml`,
          { from: users[i] }
        )
      }

      await increase(duration.days(7).add(duration.minutes(5)))

      const proofIndexes = [10, 22, 32]
      const wasCompliantData = [true, true, false]
      const randomNonces = [
        '0x48656c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100',
        '0x48656c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100',
        '0x58656c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100',
      ]
      const commitments = [
        Web3Utils.soliditySha3(wasCompliantData[0], randomNonces[0]),
        Web3Utils.soliditySha3(wasCompliantData[1], randomNonces[1]),
        Web3Utils.soliditySha3(wasCompliantData[2], randomNonces[2]),
      ]

      await networkProxy.addWasCompliantDataCommitmentsForUsers(
        users,
        commitments,
        proofIndexes,
        { from: juriNode1 }
      )

      await increase(duration.hours(1).add(duration.minutes(5)))
      await networkProxy.addWasCompliantDataForUsers(
        users.slice(1),
        wasCompliantData.slice(1),
        randomNonces.slice(1),
        { from: juriNode1 }
      )

      await increase(duration.hours(1).add(duration.minutes(5)))
      await networkProxy.moveToDissentPeriod()
      await increase(duration.hours(1).add(duration.minutes(5)))
      await networkProxy.moveFromDissentToNextPeriod()
      await increase(duration.hours(1).add(duration.minutes(5)))
      await networkProxy.moveToNextRound()

      for (let i = 0; i < users.length; i++) {
        const wasCompliant = (await networkProxy.getUserComplianceData(
          2,
          users[i]
        )).gt(new BN(0))

        expect(wasCompliant).to.be.equal(wasCompliantData[i])
      }

      const getNodeActivityCount = await networkProxy.getNodeActivityCount(
        2,
        juriNode1
      )
      expect(getNodeActivityCount).to.be.bignumber.equal(new BN(users.length))
    })

    it('runs the round correctly with offline slashing', async () => {
      const nodes = [juriNode1, juriNode2, juriNode3, juriNode4]
      const users = [poolUser1, poolUser2, poolUser3, poolUser4]
      const wasCompliantData = [true, false, false, true]
      const randomNonces = [
        '0x48656c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100',
        '0x58656c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100',
        '0x68656c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100',
        '0x78656c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100',
      ]
      const proofIndexes = [
        [1, 2, 3, 4],
        [1, 2, 3, 4],
        [1, 2, 3, 4],
        [14, 24, 32, 4],
      ]
      const commitments = [
        Web3Utils.soliditySha3(wasCompliantData[0], randomNonces[0]),
        Web3Utils.soliditySha3(wasCompliantData[1], randomNonces[1]),
        Web3Utils.soliditySha3(wasCompliantData[2], randomNonces[2]),
        Web3Utils.soliditySha3(wasCompliantData[3], randomNonces[3]),
      ]

      await runFirstHalfOfRound({
        proxy: networkProxy,
        commitments,
        nodes,
        proofIndexes,
        randomNonces,
        users,
        wasCompliantData,
      })

      const dissentNodes = [juriNode5]
      const dissentUsers = [poolUser1]
      const dissentWasCompliantData = [wasCompliantData[0]]
      const dissentRandomNonces = [
        '0x68656c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100',
      ]
      const dissentCommitments = [
        Web3Utils.soliditySha3(
          dissentWasCompliantData[0],
          dissentRandomNonces[0]
        ),
      ]

      await runDissentRound({
        proxy: networkProxy,
        dissenterNode: nodes[0],
        commitments: dissentCommitments,
        nodes: dissentNodes,
        randomNonces: dissentRandomNonces,
        users: dissentUsers,
        wasCompliantData: dissentWasCompliantData,
      })

      const stakedBalanceToSlashBefore = await bonding.bondedStakes(juriNode6)
      const stakedBalanceSlasherBefore = await bonding.bondedStakes(nodes[1])
      await bonding.slashStakeForBeingOffline(juriNode6, users[0], {
        from: nodes[1],
      })
      const stakedBalanceToSlashAfter = await bonding.bondedStakes(juriNode6)
      const stakedBalanceSlasherAfter = await bonding.bondedStakes(nodes[1])

      expect(stakedBalanceToSlashAfter.newStake).to.be.bignumber.equal(
        stakedBalanceToSlashBefore.newStake.sub(
          stakedBalanceToSlashBefore.newStake
            .mul(offlinePenalty)
            .div(new BN(100))
        )
      )

      expect(stakedBalanceSlasherAfter.newStake).to.be.bignumber.equal(
        stakedBalanceSlasherBefore.newStake.add(
          stakedBalanceToSlashBefore.newStake
            .mul(offlinePenalty)
            .div(new BN(100))
            .div(new BN(2))
        )
      )

      await increase(duration.hours(1).add(duration.minutes(5)))
      await networkProxy.moveToNextRound()
    })

    it('runs the round correctly with not reveal slashing', async () => {
      const nodes = [juriNode1, juriNode2, juriNode3, juriNode4]
      const users = [poolUser1, poolUser2, poolUser3, poolUser4]
      const wasCompliantData = [true, false, false, true]
      const randomNonces = [
        '0x48656c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100',
        '0x58656c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100',
        '0x68656c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100',
        '0x78656c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100',
      ]
      const proofIndexes = [
        [1, 2, 3, 4],
        [1, 2, 3, 4],
        [1, 2, 3, 4],
        [14, 24, 32, 4],
      ]
      const commitments = [
        Web3Utils.soliditySha3(wasCompliantData[0], randomNonces[0]),
        Web3Utils.soliditySha3(wasCompliantData[1], randomNonces[1]),
        Web3Utils.soliditySha3(wasCompliantData[2], randomNonces[2]),
        Web3Utils.soliditySha3(wasCompliantData[3], randomNonces[3]),
      ]

      await runFirstHalfOfRound({
        proxy: networkProxy,
        commitments,
        nodes,
        proofIndexes,
        randomNonces,
        users,
        wasCompliantData,
        notRevealNodes: [nodes[0]],
      })

      await increase(duration.hours(1).add(duration.minutes(5)))
      await networkProxy.moveToDissentPeriod()
      await increase(duration.hours(1).add(duration.minutes(5)))
      await networkProxy.moveFromDissentToNextPeriod()

      const stakedBalanceToSlashBefore = await bonding.bondedStakes(nodes[0])
      const stakedBalanceSlasherBefore = await bonding.bondedStakes(nodes[1])
      await bonding.slashStakeForNotRevealing(nodes[0], users[0], {
        from: nodes[1],
      })
      const stakedBalanceToSlashAfter = await bonding.bondedStakes(nodes[0])
      const stakedBalanceSlasherAfter = await bonding.bondedStakes(nodes[1])

      expect(stakedBalanceToSlashAfter.newStake).to.be.bignumber.equal(
        stakedBalanceToSlashBefore.newStake.sub(
          stakedBalanceToSlashBefore.newStake
            .mul(notRevealPenalty)
            .div(new BN(100))
        )
      )

      expect(stakedBalanceSlasherAfter.newStake).to.be.bignumber.equal(
        stakedBalanceSlasherBefore.newStake.add(
          stakedBalanceToSlashBefore.newStake
            .mul(notRevealPenalty)
            .div(new BN(100))
            .div(new BN(2))
        )
      )

      await increase(duration.hours(1).add(duration.minutes(5)))
      await networkProxy.moveToNextRound()
    })

    it('runs the round correctly with incorrect dissent slashing', async () => {
      const nodes = [juriNode1, juriNode2, juriNode3, juriNode4]
      const users = [poolUser1, poolUser2, poolUser3, poolUser4]
      const wasCompliantData = [true, false, false, true]
      const randomNonces = [
        '0x48656c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100',
        '0x58656c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100',
        '0x68656c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100',
        '0x78656c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100',
      ]
      const proofIndexes = [
        [1, 2, 3, 4],
        [1, 2, 3, 4],
        [1, 2, 3, 4],
        [14, 24, 32, 4],
      ]
      const commitments = [
        Web3Utils.soliditySha3(wasCompliantData[0], randomNonces[0]),
        Web3Utils.soliditySha3(wasCompliantData[1], randomNonces[1]),
        Web3Utils.soliditySha3(wasCompliantData[2], randomNonces[2]),
        Web3Utils.soliditySha3(wasCompliantData[3], randomNonces[3]),
      ]

      await runFirstHalfOfRound({
        proxy: networkProxy,
        commitments,
        nodes,
        proofIndexes,
        randomNonces,
        users,
        wasCompliantData,
      })

      const dissentNodes = [juriNode5, juriNode6]
      const dissentUsers = [poolUser1]
      const dissentWasCompliantData = [wasCompliantData[0]]
      const dissentRandomNonces = [
        '0x68656c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100',
      ]
      const dissentCommitments = [
        Web3Utils.soliditySha3(
          dissentWasCompliantData[0],
          dissentRandomNonces[0]
        ),
      ]

      await runDissentRound({
        proxy: networkProxy,
        dissenterNode: nodes[0],
        commitments: dissentCommitments,
        nodes: dissentNodes,
        randomNonces: dissentRandomNonces,
        users: dissentUsers,
        wasCompliantData: dissentWasCompliantData,
      })

      const stakedBalanceToSlashBefore = await bonding.bondedStakes(nodes[0])
      const stakedBalanceSlasherBefore = await bonding.bondedStakes(nodes[1])
      await bonding.slashStakeForIncorrectDissenting(nodes[0], users[0], {
        from: nodes[1],
      })
      const stakedBalanceToSlashAfter = await bonding.bondedStakes(nodes[0])
      const stakedBalanceSlasherAfter = await bonding.bondedStakes(nodes[1])

      expect(stakedBalanceToSlashAfter.newStake).to.be.bignumber.equal(
        stakedBalanceToSlashBefore.newStake.sub(
          stakedBalanceToSlashBefore.newStake
            .mul(incorrectDissentPenalty)
            .div(new BN(100))
        )
      )

      expect(stakedBalanceSlasherAfter.newStake).to.be.bignumber.equal(
        stakedBalanceSlasherBefore.newStake.add(
          stakedBalanceToSlashBefore.newStake
            .mul(incorrectDissentPenalty)
            .div(new BN(100))
            .div(new BN(2))
        )
      )

      await increase(duration.hours(1).add(duration.minutes(5)))
      await networkProxy.moveToNextRound()
    })

    it('runs the round correctly with incorrect result slashing', async () => {
      // FIRST ROUND DATA
      const nodes = [juriNode1, juriNode2]
      const users = [poolUser1, poolUser2]
      const wasCompliantData = [true, true]
      const randomNonces = [
        '0x48656c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100',
        '0x58656c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100',
      ]
      const proofIndexes = [[100, 200], [100, 200]]
      const commitments = [
        Web3Utils.soliditySha3(wasCompliantData[0], randomNonces[0]),
        Web3Utils.soliditySha3(wasCompliantData[1], randomNonces[1]),
      ]

      // DISSENT ROUND DATA
      const dissentNodes = [juriNode3, juriNode4, juriNode5, juriNode6]
      const dissentUsers = [poolUser1]
      const dissentWasCompliantData = [false]
      const dissentRandomNonces = [
        '0x68656c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100',
      ]
      const dissentCommitments = [
        Web3Utils.soliditySha3(
          dissentWasCompliantData[0],
          dissentRandomNonces[0]
        ),
      ]

      await runFirstHalfOfRound({
        proxy: networkProxy,
        commitments,
        nodes,
        proofIndexes,
        randomNonces,
        users,
        wasCompliantData,
      })

      await runDissentRound({
        proxy: networkProxy,
        dissenterNode: nodes[0],
        commitments: dissentCommitments,
        nodes: dissentNodes,
        randomNonces: dissentRandomNonces,
        users: dissentUsers,
        wasCompliantData: dissentWasCompliantData,
      })

      const slashedNode = nodes[0]
      const slasherNode = juriNode3

      const stakedBalanceToSlashBefore = await bonding.bondedStakes(slashedNode)
      const stakedBalanceSlasherBefore = await bonding.bondedStakes(slasherNode)
      await bonding.slashStakeForIncorrectResult(slashedNode, users[0], {
        from: slasherNode,
      })
      const stakedBalanceToSlashAfter = await bonding.bondedStakes(slashedNode)
      const stakedBalanceSlasherAfter = await bonding.bondedStakes(slasherNode)

      expect(stakedBalanceToSlashAfter.newStake).to.be.bignumber.equal(
        stakedBalanceToSlashBefore.newStake.sub(
          stakedBalanceToSlashBefore.newStake
            .mul(incorrectResultPenalty)
            .div(new BN(100))
        )
      )

      expect(stakedBalanceSlasherAfter.newStake).to.be.bignumber.equal(
        stakedBalanceSlasherBefore.newStake.add(
          stakedBalanceToSlashBefore.newStake
            .mul(incorrectResultPenalty)
            .div(new BN(100))
            .div(new BN(2))
        )
      )

      await increase(duration.hours(1).add(duration.minutes(5)))
      await networkProxy.moveToNextRound()
    })

    it('allows retrieving juri fees as round reward for participating nodes', async () => {
      const nodes = [juriNode1, juriNode2]
      const users = [poolUser1, poolUser2]
      const wasCompliantData = [true, true]
      const randomNonces = [
        '0x48656c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100',
        '0x58656c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100',
      ]
      const proofIndexes = [[100, 200], [100, 200]]
      const commitments = [
        Web3Utils.soliditySha3(wasCompliantData[0], randomNonces[0]),
        Web3Utils.soliditySha3(wasCompliantData[1], randomNonces[1]),
      ]

      await runFirstHalfOfRound({
        proxy: networkProxy,
        commitments,
        nodes,
        proofIndexes,
        randomNonces,
        users,
        wasCompliantData,
      })

      await increase(duration.hours(1).add(duration.minutes(5)))
      await networkProxy.moveToDissentPeriod()
      await increase(duration.hours(1).add(duration.minutes(5)))
      await networkProxy.moveFromDissentToNextPeriod()
      await juriFeesToken.mint(networkProxy.address, ether('100'))
      await increase(duration.hours(1).add(duration.minutes(5)))
      await networkProxy.moveToNextRound()

      await networkProxy.retrieveRoundJuriFees(2, { from: juriNode1 })
      await networkProxy.retrieveRoundJuriFees(2, { from: juriNode2 })

      await shouldFail.reverting.withMessage(
        networkProxy.retrieveRoundJuriFees(2, { from: juriNode3 }),
        'Node did not participate this round!'
      )

      const balanceJuriNode1After = await juriFeesToken.balanceOf(juriNode1)
      const balanceJuriNode2After = await juriFeesToken.balanceOf(juriNode2)
      const balanceJuriNode3After = await juriFeesToken.balanceOf(juriNode3)

      expect(balanceJuriNode1After).to.be.bignumber.equal(ether('50'))
      expect(balanceJuriNode2After).to.be.bignumber.equal(ether('50'))
      expect(balanceJuriNode3After).to.be.bignumber.equal(ether('0'))
    })
  })
}

module.exports = itRunsProxyRoundCorrectly

/* const currentHighestHash0 = await proxy.getCurrentHighestHashForUser(
  users[0]
)
const verifierHash0 = [
  Web3Utils.soliditySha3(
    '0x00156c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100',
    nodes[0],
    proofIndexes[0]
  ),
  Web3Utils.soliditySha3(
    '0x00156c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100',
    nodes[1],
    proofIndexes[0]
  ),
  Web3Utils.soliditySha3(
    '0x00156c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100',
    nodes[2],
    proofIndexes[0]
  ),
  Web3Utils.soliditySha3(
    '0x00156c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100',
    nodes[3],
    proofIndexes[0]
  ),
]
console.log({
  currentHighestHash0: '0x' + currentHighestHash0.toString(16),
  verifierHash0,
})

const currentHighestHash1 = await proxy.getCurrentHighestHashForUser(
  users[1]
)
const verifierHash1 = [
  Web3Utils.soliditySha3(
    '0x00156c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100',
    nodes[0],
    proofIndexes[1]
  ),
  Web3Utils.soliditySha3(
    '0x00156c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100',
    nodes[1],
    proofIndexes[1]
  ),
  Web3Utils.soliditySha3(
    '0x00156c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100',
    nodes[2],
    proofIndexes[1]
  ),
  Web3Utils.soliditySha3(
    '0x00156c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100',
    nodes[3],
    proofIndexes[1]
  ),
]
console.log({
  currentHighestHash1: '0x' + currentHighestHash1.toString(16),
  verifierHash1,
})

const currentHighestHash2 = await proxy.getCurrentHighestHashForUser(
  users[2]
)
const verifierHash2 = [
  Web3Utils.soliditySha3(
    '0x00156c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100',
    nodes[0],
    proofIndexes[2]
  ),
  Web3Utils.soliditySha3(
    '0x00156c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100',
    nodes[1],
    proofIndexes[2]
  ),
  Web3Utils.soliditySha3(
    '0x00156c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100',
    nodes[2],
    proofIndexes[2]
  ),
  Web3Utils.soliditySha3(
    '0x00156c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100',
    nodes[3],
    proofIndexes[2]
  ),
]
console.log({
  currentHighestHash2: '0x' + currentHighestHash2.toString(16),
  verifierHash2,
})

const currentHighestHash3 = await proxy.getCurrentHighestHashForUser(
  users[3]
)
const verifierHash3 = [
  Web3Utils.soliditySha3(
    '0x00156c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100',
    nodes[0],
    proofIndexes[3]
  ),
  Web3Utils.soliditySha3(
    '0x00156c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100',
    nodes[1],
    proofIndexes[3]
  ),
  Web3Utils.soliditySha3(
    '0x00156c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100',
    nodes[2],
    proofIndexes[3]
  ),
  Web3Utils.soliditySha3(
    '0x00156c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100',
    nodes[3],
    proofIndexes[3]
  ),
]
console.log({
  currentHighestHash3: '0x' + currentHighestHash3.toString(16),
  verifierHash3,
}) */
