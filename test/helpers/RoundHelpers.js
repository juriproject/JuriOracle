const Heap = require('heap')

const { BN, ether, time } = require('@openzeppelin/test-helpers')
const Web3Utils = require('web3-utils')

const JuriStakingPoolWithOracle = artifacts.require(
  'JuriStakingPoolWithOracle.sol'
)
const ERC20Mintable = artifacts.require('ERC20Mintable.sol')

const { duration, increase } = time

const StageMapping = {
  '0': 'USER_ADDING_HEART_RATE_DATA',
  '1': 'NODES_ADDING_RESULT_COMMITMENTS',
  '2': 'NODES_ADDING_RESULT_REVEALS',
  '3': 'DISSENTING_PERIOD',
  '4': 'DISSENTS_NODES_ADDING_RESULT_COMMITMENTS',
  '5': 'DISSENTS_NODES_ADDING_RESULT_REVEALS',
  '6': 'SLASHING_PERIOD',
}

const findLowestHashProofIndexes = ({ bondedStake, node }) => {
  const heap = new Heap((a, b) => (a.gt(b) ? -1 : 1))
  const hashesToProofIndex = {}

  for (let proofIndex = 0; proofIndex < bondedStake; proofIndex++) {
    const currentSmallest = heap.peek()
    const hash = new BN(
      Web3Utils.soliditySha3(
        '0x00156c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100',
        node,
        proofIndex
      ).slice(2),
      16
    )

    if (proofIndex <= 3) {
      heap.push(hash)
      hashesToProofIndex[hash] = proofIndex
    } else if (currentSmallest.gt(hash)) {
      heap.pushpop(hash)
      hashesToProofIndex[hash] = proofIndex
    }
  }

  const lowestHashes = heap.toArray()
  const proofIndexes = lowestHashes.map(hash => hashesToProofIndex[hash])

  return { lowestHashes, proofIndexes }
}

const removeEmptyKeys = obj => {
  for (var propName in obj) {
    if (
      obj[propName] === null ||
      obj[propName] === undefined ||
      obj[propName] === '0' ||
      obj[propName] ===
        '0x0000000000000000000000000000000000000000000000000000000000000000'
    )
      delete obj[propName]
  }
}

const printState = async ({ proxy, nodes, users }) => {
  const roundIndex = await proxy.roundIndex()

  console.log('******************* NODE STATE *********************')
  for (let i = 0; i < nodes.length; i++) {
    console.log(`******************* NODE STATE ${i} *********************`)
    const node = nodes[i]

    const hasRevealed = await proxy.getHasRevealed(roundIndex, node)
    const nodeActivity = await proxy.getNodeActivityCount(roundIndex, node)

    const result = { hasRevealed, nodeActivity: nodeActivity.toString() }
    removeEmptyKeys(result)

    console.log(result)
  }

  console.log('******************* USER STATE *********************')
  for (let i = 0; i < users.length; i++) {
    console.log(`******************* USER STATE ${i} *********************`)
    const user = users[i]

    const dissented = await proxy.getDissented(roundIndex, user)
    const complianceDataBeforeDissent = await proxy.getComplianceDataBeforeDissent(
      roundIndex,
      user
    )
    const userComplianceData = await proxy.getUserComplianceData(
      roundIndex,
      user
    )

    const result = {
      dissented,
      complianceDataBeforeDissent: complianceDataBeforeDissent.toString(),
      userComplianceData: userComplianceData.toString(),
    }
    removeEmptyKeys(result)

    console.log(result)
  }

  console.log('******************* NODE/USER STATE *********************')
  for (let i = 0; i < nodes.length; i++) {
    for (let j = 0; j < users.length; j++) {
      console.log(
        `******************* NODE/USER STATE ${i}/${j} *********************`
      )
      const node = nodes[i]
      const user = users[j]

      const userComplianceDataCommitment = await proxy.getUserComplianceDataCommitment(
        roundIndex,
        node,
        user
      )
      const givenNodeResult = await proxy.getGivenNodeResult(
        roundIndex,
        node,
        user
      )
      const hasDissented = await proxy.getHasDissented(roundIndex, node, user)

      const result = {
        userComplianceDataCommitment,
        givenNodeResult,
        hasDissented,
      }
      removeEmptyKeys(result)

      console.log(result)
    }
  }

  const totalActivityCount = await proxy.getTotalActivityCount(roundIndex)
  const currentStage = await proxy.currentStage()
  const startTime = await proxy.startTime()
  const lastStageUpdate = await proxy.lastStageUpdate()
  const totalJuriFees = await proxy.totalJuriFees()
  const nodeVerifierCount = await proxy.nodeVerifierCount()

  console.log('******************* GENERAL STATE *********************')
  console.log({ currentStage: StageMapping[currentStage.toString()] })

  const result = {
    roundIndex: roundIndex.toString(),
    totalActivityCount: totalActivityCount.toString(),
    startTime: startTime.toString(),
    lastStageUpdate: lastStageUpdate.toString(),
    totalJuriFees: totalJuriFees.toString(),
    nodeVerifierCount: nodeVerifierCount.toString(),
  }

  removeEmptyKeys(result)

  console.log(result)

  try {
    const firstDissentedUser = await proxy.dissentedUsers(1)
    console.log({ firstDissentedUser })
  } catch (error) {}
}

const runSetupRound = async ({ node, proxy, user }) => {
  await proxy.addHeartRateDateForPoolUser(
    '0x48656c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100',
    '0x02163123/123-heartRateData.xml',
    { from: user }
  )

  await increase(duration.days(7))

  const users = [user]
  const wasCompliant = true
  const randomNonce =
    '0x48656c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100'
  const proofIndex = 100
  const commitment = Web3Utils.soliditySha3(wasCompliant, randomNonce)

  await proxy.moveToNextStage()
  await proxy.addWasCompliantDataCommitmentsForUsers(
    users,
    [commitment],
    [proofIndex],
    [],
    { from: node }
  )
  await increase(duration.hours(1).add(duration.minutes(5)))

  await proxy.moveToNextStage()
  await proxy.addWasCompliantDataForUsers(
    users,
    [wasCompliant],
    [randomNonce],
    { from: node }
  )

  await increase(duration.hours(1).add(duration.minutes(5)))
  await proxy.moveToNextStage()
  await increase(duration.hours(1).add(duration.minutes(5)))
  await proxy.moveToNextStage()
  await increase(duration.hours(1).add(duration.minutes(5)))

  await proxy.moveToNextRound()
}

const hasNewHashesToAdd = ({
  currentLowestHashesForUser,
  lowestHashFromNodeForUser,
}) => {
  const currentLowestHashesForUserBN = currentLowestHashesForUser
    .map(hash => new BN(hash.slice(2), 16))
    .sort((a, b) => (a.gt(b) ? 1 : -1))
  const currentMaxHashForUser = currentLowestHashesForUserBN[1]
  const lowestHashFromNodeForUserBN = new BN(
    lowestHashFromNodeForUser.slice(2),
    16
  )

  return currentMaxHashForUser.gt(lowestHashFromNodeForUserBN)
}

const addLowestHashes = async ({
  commitments,
  lowestHashesForNode,
  node,
  proofIndexesForNode,
  proxy,
  users,
}) => {
  const hashesToAddIndexes = []

  const currentLowestHashes = [
    await proxy.getUserWorkAssignmentHashes(2, users[0]),
    await proxy.getUserWorkAssignmentHashes(2, users[1]),
    await proxy.getUserWorkAssignmentHashes(2, users[2]),
    await proxy.getUserWorkAssignmentHashes(2, users[3]),
  ].map(hashList =>
    hashList.map(hashBN => '0x' + hashBN.toString(16).padStart(64, '0'))
  )

  for (let j = 0; j < users.length; j++) {
    if (
      hasNewHashesToAdd({
        currentLowestHashesForUser: currentLowestHashes[j],
        lowestHashFromNodeForUser: lowestHashesForNode[j],
      })
    )
      hashesToAddIndexes.push(j)
  }

  if (hashesToAddIndexes.length > 0) {
    const mappedUsers = hashesToAddIndexes.map(index => users[index])
    const mappedCommitments = hashesToAddIndexes.map(
      index => commitments[index]
    )
    const mappedProofIndexes = hashesToAddIndexes.map(
      index => proofIndexesForNode[index]
    )

    await proxy.addWasCompliantDataCommitmentsForUsers(
      mappedUsers,
      mappedCommitments,
      mappedProofIndexes,
      mappedProofIndexes.map((_, i) => i).filter(e => e !== 0),
      { from: node }
    )
  }
}

const getAssignedUsersIndexes = async ({ node, proxy, users }) => {
  const assignedUsersIndexes = []

  for (let i = 0; i < users.length; i++) {
    const wasAssignedToUser = await proxy.getWasAssignedToUser(
      2,
      node,
      users[i]
    )

    if (wasAssignedToUser) assignedUsersIndexes.push(i)
  }

  return assignedUsersIndexes
}

const runFirstHalfOfRound = async ({
  commitments,
  lowestHashes,
  nodes,
  proofIndexes,
  proxy,
  randomNonces,
  users,
  wasCompliantData,
  notRevealNodes = [],
}) => {
  for (let i = 0; i < users.length; i++) {
    await proxy.addHeartRateDateForPoolUser(
      `0x00156c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100`,
      `0x01/123-heartRateData.xml`,
      { from: users[i] }
    )
  }

  await increase(duration.days(7).add(duration.minutes(5)))
  await proxy.moveToNextStage()

  for (let i = 0; i < nodes.length; i++) {
    if (i > 1 && lowestHashes) {
      await addLowestHashes({
        lowestHashesForNode: lowestHashes[i],
        node: nodes[i],
        proofIndexesForNode: proofIndexes[i],
        commitments,
        proxy,
        users,
      })
    } else {
      if (i > 1) {
        const currentLowestHashesBN = [
          await proxy.getUserWorkAssignmentHashes(2, users[0]),
          await proxy.getUserWorkAssignmentHashes(2, users[1]),
          await proxy.getUserWorkAssignmentHashes(2, users[2]),
          await proxy.getUserWorkAssignmentHashes(2, users[3]),
        ]

        /* .map(hashList =>
          hashList.map(hashBN => '0x' + hashBN.toString(16).padStart(64, '0'))
        ) */

        const newToAddHashesBN = proofIndexes[i].map(
          proofIndex =>
            new BN(
              Web3Utils.soliditySha3(
                '0x00156c6c6f576f726c6448656c6c6f576f726c6448656c6c6f576f726c642100',
                nodes[i],
                proofIndex
              ).slice(2),
              16
            )
        )

        const validNewAdditionHashes = newToAddHashesBN.filter(
          (newToAddHashBN, i) =>
            currentLowestHashesBN[i][0].gt(newToAddHashBN) ||
            currentLowestHashesBN[i][1].gt(newToAddHashBN)
        )

        const validNewAdditionIndexes = validNewAdditionHashes.map(newHash =>
          newToAddHashesBN.indexOf(newHash)
        )

        const mappedUsers = validNewAdditionIndexes.map(j => users[j])
        const mappedCommitments = validNewAdditionIndexes.map(
          j => commitments[j]
        )
        const mappedProofIndexes = validNewAdditionIndexes.map(
          j => proofIndexes[i][j]
        )

        await proxy.addWasCompliantDataCommitmentsForUsers(
          mappedUsers,
          mappedCommitments,
          mappedProofIndexes,
          mappedProofIndexes.map((_, i) => i).filter(e => e !== 0),
          { from: nodes[i] }
        )
      } else
        await proxy.addWasCompliantDataCommitmentsForUsers(
          users,
          commitments,
          proofIndexes[i],
          proofIndexes[i].map((_, i) => i).filter(e => e !== 0),
          { from: nodes[i] }
        )
    }
  }

  await increase(duration.hours(1).add(duration.minutes(5)))
  await proxy.moveToNextStage()

  for (let i = 0; i < nodes.length; i++) {
    const node = nodes[i]

    if (!notRevealNodes.includes(node)) {
      const assignedUsersIndexes = await getAssignedUsersIndexes({
        node,
        proxy,
        users,
      })

      if (assignedUsersIndexes.length > 0) {
        const mappedUsers = assignedUsersIndexes.map(index => users[index])
        const mappedWasCompliantData = assignedUsersIndexes.map(
          index => wasCompliantData[index]
        )
        const mappedRandomNonces = assignedUsersIndexes.map(
          index => randomNonces[index]
        )

        await proxy.addWasCompliantDataForUsers(
          mappedUsers,
          mappedWasCompliantData,
          mappedRandomNonces,
          { from: node }
        )
      }
    }
  }
}

const runDissentRound = async ({
  proxy,
  dissenterNode,
  commitments,
  nodes,
  randomNonces,
  users,
  wasCompliantData,
}) => {
  await increase(duration.hours(1).add(duration.minutes(5)))
  await proxy.moveToNextStage()

  for (let i = 0; i < users.length; i++) {
    const dissentedUser = users[i]
    await proxy.dissentToAcceptedAnswers([dissentedUser], {
      from: dissenterNode,
    })
  }

  await increase(duration.hours(1).add(duration.minutes(5)))
  await proxy.moveToNextStage()

  for (let i = 0; i < nodes.length; i++) {
    await proxy.addDissentWasCompliantDataCommitmentsForUsers(
      users,
      commitments,
      { from: nodes[i] }
    )
  }

  await increase(duration.hours(1).add(duration.minutes(5)))
  await proxy.moveToNextStage()

  for (let i = 0; i < nodes.length; i++) {
    await proxy.addDissentWasCompliantDataForUsers(
      users,
      wasCompliantData,
      randomNonces,
      { from: nodes[i] }
    )
  }

  await increase(duration.hours(1).add(duration.minutes(5)))
  await proxy.moveToNextStage()
}

const approveAndAddUser = ({ pool, stake, token, user }) =>
  token
    .approve(pool.address, stake, { from: user })
    .then(() => pool.addUserInNextPeriod(stake, { from: user }))

const deployJuriStakingPool = async ({
  addresses,
  networkProxy,
  periodLength,
  feePercentage,
  compliantGainPercentage,
  maxNonCompliantPenaltyPercentage,
  minStakePerUser,
  maxStakePerUser,
  maxTotalStake,
  token,
  juriAddress,
}) => {
  await Promise.all(addresses.map(user => token.mint(user, ether('200'))))

  const startTime = (await time.latest()).add(time.duration.seconds(20))
  const pool = await JuriStakingPoolWithOracle.new(
    networkProxy.address,
    token.address,
    startTime,
    periodLength,
    feePercentage,
    compliantGainPercentage,
    maxNonCompliantPenaltyPercentage,
    minStakePerUser,
    maxStakePerUser,
    maxTotalStake,
    juriAddress
  )

  return pool
}

const asyncForEach = async ({ array, callback }) => {
  for (let i = 0; i < array.length; i++) {
    await callback(array[i], i, array)
  }
}

const initialPoolSetup = async ({ pool, poolStakes, poolUsers, token }) => {
  await token.approve(pool.address, ether('100'))
  await pool.addOwnerFunds(ether('100'))

  await asyncForEach({
    array: poolUsers,
    callback: async (user, i) =>
      approveAndAddUser({
        pool,
        stake: poolStakes[i],
        token,
        user,
      }),
  })

  await time.increase(duration.days(7))

  await pool.checkNewAddedComplianceData(50)
  await pool.firstUpdateStakeForNextXAmountOfUsers(50)
  await pool.secondUpdateStakeForNextXAmountOfUsers(50)
}

const runPoolRound = async ({ complianceData, pool, proxyMock, poolUsers }) => {
  await time.increase(duration.days(7))

  await proxyMock.debugIncreaseRoundIndex()
  await proxyMock.addComplianceDataForUsers(poolUsers, complianceData)

  await pool.checkNewAddedComplianceData(50)
  await pool.firstUpdateStakeForNextXAmountOfUsers(50)
  await pool.secondUpdateStakeForNextXAmountOfUsers(50)
}

module.exports = {
  deployJuriStakingPool,
  findLowestHashProofIndexes,
  initialPoolSetup,
  printState,
  runDissentRound,
  runFirstHalfOfRound,
  runPoolRound,
  runSetupRound,
}
