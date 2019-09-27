const ERC20Mintable = artifacts.require('ERC20Mintable')
const JuriStakingPool = artifacts.require('JuriStakingPool')

const BN = require('bn.js')

const toEther = number => number.pow(new BN(18))

module.exports = (deployer, network) => {
  deployer.then(async () => {
    if (network !== 'rinkeby') {
      const token = await deployer.deploy(ERC20Mintable)
      await token.mint(
        '0x15ae150d7dC03d3B635EE90b85219dBFe071ED35',
        new BN(1000)
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

      await deployer.deploy(
        JuriStakingPool,
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
    }
  })
}
