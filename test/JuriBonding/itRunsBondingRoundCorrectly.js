const { expect } = require('chai')
const { BN, ether, shouldFail } = require('openzeppelin-test-helpers')

const ERC20Mintable = artifacts.require('./lib/ERC20Mintable.sol')
const JuriBonding = artifacts.require('./JuriBonding.sol')
const JuriNetworkProxyMock = artifacts.require('./JuriNetworkProxyMock.sol')

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
      juriToken = await ERC20Mintable.new()
      proxyMock = await JuriNetworkProxyMock.new(
        juriFeesToken.address,
        juriToken.address,
        juriFoundation,
        ether('1000'),
        10,
        20,
        40,
        40
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
      await proxyMock.incrementRoundIndex()
      await bonding.unbondStake(ether('10000'), { from: juriNode1 })

      const allowedWithdrawal1 = await bonding.allowedWithdrawalAmounts(
        juriNode1
      )

      await shouldFail.reverting.withMessage(
        bonding.withdrawAllowedStakes({ from: juriNode1 }),
        'Not yet allowed to withdraw!'
      )
      const bondedStake4 = await bonding.getBondedStakeOfNode(juriNode1)
      await proxyMock.incrementRoundIndex()
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
