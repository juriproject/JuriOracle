const BN = require('bn.js')

const { users } = require('../config/accounts')

const ERC20Mintable = artifacts.require('./lib/ERC20Mintable.sol')
const JuriNetworkProxy = artifacts.require('./JuriNetworkProxy.sol')
const JuriStakingPoolWithOracleMock = artifacts.require(
  'JuriStakingPoolWithOracleMock'
)
const MaxHeapLibrary = artifacts.require('./MaxHeapLibrary.sol')

const {
  juriTokenMain,
  juriTokenSide,
  skaleMessageProxyMain,
} = require('./data/deployed')

const {
  message_proxy_for_schain_address,
} = require('../contracts/lib/skale/rinkeby_ABIs.json')

// const ONE_HOUR = 60 * 60
// const ONE_WEEK = ONE_HOUR * 24 * 7

const TWO_MINUTES = 2 * 60
const FIFTEEN_MINUTES = 15 * 60

const toEther = number => number.mul(new BN(10).pow(new BN(18)))

module.exports = deployer => {
  deployer.then(async () => {
    await deployer.deploy(MaxHeapLibrary)
    await deployer.link(MaxHeapLibrary, [JuriNetworkProxy])

    /* const skaleFileStorage = await deployer.deploy(
      artifacts.require('./SkaleFileStorageMock.sol')
    ) */
    const skaleFileStorage = '0x69362535ec535f0643cbf62d16adedcaf32ee6f7'

    const juriFeesToken = await deployer.deploy(ERC20Mintable)
    const juriFoundation = '0x15ae150d7dc03d3b635ee90b85219dbfe071ed35'
    const oneEther = '1000000000000000000'

    const networkProxy = await deployer.deploy(
      JuriNetworkProxy,
      juriFeesToken.address,
      juriTokenSide,
      juriTokenMain,
      message_proxy_for_schain_address,
      skaleMessageProxyMain,
      skaleFileStorage, // skaleFileStorage.address,
      juriFoundation,
      [
        FIFTEEN_MINUTES, // ONE_WEEK,
        TWO_MINUTES,
        TWO_MINUTES,
        TWO_MINUTES,
        TWO_MINUTES,
        TWO_MINUTES,
        TWO_MINUTES,
      ],
      [10, 20, 30, 40],
      oneEther
    )

    const startTime = new BN(Math.round(Date.now() / 1000)).add(
      new BN(1000000000000)
    )
    const periodLength = new BN(60 * 60 * 24 * 7)
    const feePercentage = new BN(1)
    const compliantGainPercentage = new BN(4)
    const maxNonCompliantPenaltyPercentage = new BN(5)
    const minStakePerUser = toEther(new BN(5))
    const maxStakePerUser = toEther(new BN(100))
    const maxTotalStake = toEther(new BN(50000))
    const juriAddress = '0x15ae150d7dC03d3B635EE90b85219dBFe071ED35'

    const stakingContract1 = await deployer.deploy(
      JuriStakingPoolWithOracleMock,
      networkProxy.address,
      juriFeesToken.address,
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
    const pool1Users = users
      .slice(0, users.length / 2)
      .map(({ address }) => address)
    await stakingContract1.insertUsers(pool1Users)

    const stakingContract2 = await deployer.deploy(
      JuriStakingPoolWithOracleMock,
      networkProxy.address,
      juriFeesToken.address,
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

    const pool2Users = users
      .slice(users.length / 2)
      .map(({ address }) => address)
    await stakingContract2.insertUsers(pool2Users)

    await networkProxy.registerJuriStakingPool(stakingContract1.address)
    await networkProxy.registerJuriStakingPool(stakingContract2.address)

    console.log({
      networkProxyAddress: networkProxy.address,
      stakingAddress1: stakingContract1.address,
      stakingAddress2: stakingContract2.address,
    })
  })
}
