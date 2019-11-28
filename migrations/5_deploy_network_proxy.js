const BN = require('bn.js')
const clearModule = require('clear-module')
const fs = require('fs')

const { users } = require('../config/accounts')

const ERC20Mintable = artifacts.require('./lib/ERC20Mintable.sol')
const JuriNetworkProxy = artifacts.require('./JuriNetworkProxy.sol')
const JuriNetworkProxyMock = artifacts.require('./JuriNetworkProxyMock.sol')
const JuriStakingPoolWithOracleMock = artifacts.require(
  'JuriStakingPoolWithOracleMock'
)
const MaxHeapLibrary = artifacts.require('./MaxHeapLibrary.sol')
const SkaleMessageProxySideMock = artifacts.require(
  './SkaleMessageProxySideMock.sol'
)

const {
  message_proxy_for_schain_address,
} = require('../contracts/lib/skale/rinkeby_ABIs.json')

const fs_writeFile = require('util').promisify(fs.writeFile)

const sleep = require('util').promisify(setTimeout)

const ONE_HOUR = 60 * 60
const ONE_WEEK = ONE_HOUR * 24 * 7

// const TWO_MINUTES = 2 * 60
// const FIFTEEN_MINUTES = 15 * 60

const toEther = number => number.mul(new BN(10).pow(new BN(18)))

module.exports = (deployer, network) => {
  deployer.then(async () => {
    await deployer.deploy(MaxHeapLibrary)
    await deployer.link(MaxHeapLibrary, [JuriNetworkProxy])
    await deployer.link(MaxHeapLibrary, [JuriNetworkProxyMock])

    const skaleFileStorageAddress =
      network === 'development'
        ? (
            await deployer.deploy(
              artifacts.require('./SkaleFileStorageMock.sol')
            )
          ).address
        : '0x69362535ec535f0643cbf62d16adedcaf32ee6f7'

    const juriFeesToken = await deployer.deploy(ERC20Mintable)
    const juriFoundation = '0x15ae150d7dc03d3b635ee90b85219dbfe071ed35'
    const oneEther = '1000000000000000000'

    const deployedFileName = './data/deployed.json'

    let {
      juriTokenMain,
      juriTokenSide,
      skaleMessageProxyMain,
    } = require(deployedFileName)

    console.log({
      juriTokenMain,
      juriTokenSide,
      skaleMessageProxyMain,
    })

    while (juriTokenSide === '- waiting for deployment -') {
      await sleep(2000)

      clearModule(deployedFileName)
      const deployed = require(deployedFileName)

      juriTokenSide = deployed.juriTokenSide
    }

    const skaleMessageProxySide =
      network !== 'skaleSide'
        ? (await deployer.deploy(SkaleMessageProxySideMock)).address
        : message_proxy_for_schain_address

    const networkProxy = await deployer.deploy(
      JuriNetworkProxyMock,
      juriFeesToken.address,
      juriTokenSide,
      juriTokenMain,
      skaleMessageProxySide,
      skaleMessageProxyMain,
      skaleFileStorageAddress,
      juriFoundation,
      [ONE_WEEK, ONE_HOUR, ONE_HOUR, ONE_HOUR, ONE_HOUR, ONE_HOUR, ONE_HOUR],
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

    await fs_writeFile(
      __dirname + '\\data\\deployed.json',
      JSON.stringify({
        ...require('./data/deployed'),
      })
    )

    await fs_writeFile(
      __dirname +
        '..\\..\\..\\JuriNodeApp\\config\\lastDeployedNetworkProxyAddress.json',
      JSON.stringify({ networkProxyAddress: networkProxy.address })
    )

    return deployer
  })
}
