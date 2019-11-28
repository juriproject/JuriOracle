const { expect } = require('chai')
const { BN, ether, expectRevert, time } = require('@openzeppelin/test-helpers')

const { duration } = time

const ERC20Mintable = artifacts.require('./lib/ERC20Mintable.sol')
const JuriTokenMock = artifacts.require('./lib/JuriTokenMock.sol')
const JuriBonding = artifacts.require('./JuriBonding.sol')
const JuriNetworkProxyMock = artifacts.require('./JuriNetworkProxyMock.sol')
const SkaleFileStorageMock = artifacts.require('./SkaleFileStorageMock.sol')
const SkaleMessageProxySideMock = artifacts.require(
  './SkaleMessageProxySideMock.sol'
)

const itRunsProxyRoundCorrectly = async addresses => {
  describe('when running a round', async () => {
    let bonding, juriFeesToken, juriNode1, juriToken, proxyMock

    beforeEach(async () => {
      poolUser = addresses[0]
      juriNode1 = addresses[1]
      juriNode2 = addresses[2]
      juriNode3 = addresses[3]
      juriNode4 = addresses[4]
      juriFoundation = addresses[5]

      juriFeesToken = await ERC20Mintable.new()
      juriToken = await JuriTokenMock.new()
      const skaleMessageProxySideMock = await SkaleMessageProxySideMock.new()
      const skaleMessageProxyMain = await juriToken.skaleMessageProxy()
      const skaleFileStorage = await SkaleFileStorageMock.new()

      proxyMock = await JuriNetworkProxyMock.new(
        juriFeesToken.address,
        juriToken.address,
        juriToken.address,
        skaleMessageProxySideMock.address,
        skaleMessageProxyMain,
        skaleFileStorage.address,
        juriFoundation,
        [
          duration.days(7),
          duration.hours(1),
          duration.hours(1),
          duration.hours(1),
          duration.hours(1),
          duration.hours(1),
          duration.hours(1),
        ],
        [new BN(10), new BN(20), new BN(35), new BN(40)],
        ether('1000')
      )
      bonding = await JuriBonding.at(await proxyMock.bonding())

      await Promise.all(
        addresses
          .slice(0, 10)
          .map(address => juriToken.mint(address, ether('1000000')))
      )
      await Promise.all(
        addresses
          .slice(1, 5)
          .map(node =>
            juriToken
              .approve(bonding.address, ether('10000'), { from: node })
              .then(() => bonding.bondStake(ether('10000'), { from: node }))
          )
      )
    })

    it('runs the round correctly', async () => {
      await proxyMock.debugIncreaseRoundIndex()
      await bonding.unbondStake(ether('10000'), { from: juriNode1 })

      const allowedWithdrawal1 = await bonding.allowedWithdrawalAmounts(
        juriNode1
      )

      await expectRevert(
        bonding.withdrawAllowedStakes({ from: juriNode1 }),
        'Not yet allowed to withdraw!'
      )

      const bondedStake4 = await bonding.getBondedStakeOfNode(juriNode1)
      await proxyMock.debugIncreaseRoundIndex()
      const bondedStake5 = await bonding.getBondedStakeOfNode(juriNode1)

      await bonding.withdrawAllowedStakes({ from: juriNode1 })
      const juriTokenBalance = await juriToken.balanceOf(juriNode1)

      expect(juriTokenBalance).to.be.bignumber.equal(ether('1000000'))
      expect(bondedStake4).to.be.bignumber.equal(ether('10000'))
      expect(bondedStake5).to.be.bignumber.equal(ether('0'))
      expect(allowedWithdrawal1.amount).to.be.bignumber.equal(ether('10000'))
      expect(allowedWithdrawal1.minRoundIndex).to.be.bignumber.equal(new BN(2))
    })
  })
}

// await proxyMock.moveToNextStage()

module.exports = itRunsProxyRoundCorrectly
