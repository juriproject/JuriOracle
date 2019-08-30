const { expect } = require('chai')
const { BN, ether } = require('openzeppelin-test-helpers')

const ERC20Mintable = artifacts.require('./lib/ERC20Mintable.sol')
const JuriBonding = artifacts.require('./JuriBonding.sol')
const JuriNetworkProxyMock = artifacts.require('./JuriNetworkProxyMock.sol')
const JuriTokenMock = artifacts.require('./JuriTokenMock.sol')

const itRunsProxyRoundCorrectly = async addresses => {
  describe('when running a round', async () => {
    let bonding,
      juriFeesToken,
      juriNode1,
      juriNode2,
      juriNode3,
      juriNode4,
      inflationChange,
      juriTokenMock,
      proxyMock,
      targetBondingRatePer1000000

    beforeEach(async () => {
      poolUser = addresses[0]
      juriNode1 = addresses[1]
      juriNode2 = addresses[2]
      juriNode3 = addresses[3]
      juriNode4 = addresses[4]
      juriFoundation = addresses[5]

      inflationChange = new BN(10)
      targetBondingRatePer1000000 = new BN(500000)

      juriFeesToken = await ERC20Mintable.new()
      juriTokenMock = await JuriTokenMock.new()
      proxyMock = await JuriNetworkProxyMock.new(
        juriFeesToken.address,
        juriTokenMock.address,
        juriFoundation,
        ether('100'),
        10,
        20,
        40,
        40
      )
      bonding = await JuriBonding.at(await proxyMock.bonding())

      await juriTokenMock.setJuriBonding(bonding.address)
      await juriTokenMock.setJuriNetworkProxy(proxyMock.address)
      await juriTokenMock.setInflationChange(inflationChange)
      await juriTokenMock.setTargetBondingRate(targetBondingRatePer1000000)

      await Promise.all(
        addresses
          .slice(0, 10)
          .map(address => juriTokenMock.mint(address, ether('1000')))
      )
      await Promise.all(
        addresses
          .slice(1, 6)
          .map(node =>
            juriTokenMock
              .approve(bonding.address, ether('1000'), { from: node })
              .then(() => bonding.bondStake(ether('1000'), { from: node }))
          )
      )
    })

    it('runs the round correctly', async () => {
      await proxyMock.incrementRoundIndex()
      await juriTokenMock.setCurrentRewardTokens()

      const inflationRound1 = await juriTokenMock.inflation()
      const currentMintableTokensRound1 = await juriTokenMock.currentMintableTokens()

      expect(inflationRound1).to.be.bignumber.equal(new BN(0))
      expect(currentMintableTokensRound1).to.be.bignumber.equal(new BN(0))

      await bonding.unbondStake(ether('1000'), { from: juriNode1 })
      await proxyMock.incrementRoundIndex()
      await juriTokenMock.setCurrentRewardTokens()

      const inflationRound2 = await juriTokenMock.inflation()
      const currentMintableTokensRound2 = await juriTokenMock.currentMintableTokens()

      const totalSupply = ether('10000')
      expect(inflationRound2).to.be.bignumber.equal(inflationChange)
      expect(currentMintableTokensRound2).to.be.bignumber.equal(
        totalSupply.mul(inflationChange).div(new BN(100))
      )

      await proxyMock.increaseNodeActivity(juriNode1)
      await proxyMock.increaseNodeActivity(juriNode1)
      await proxyMock.increaseNodeActivity(juriNode2)
      await proxyMock.increaseNodeActivity(juriNode3)

      await proxyMock.incrementRoundIndex()
      await juriTokenMock.setCurrentRewardTokens()

      const inflationRound3 = await juriTokenMock.inflation()
      const currentMintableTokensRound3 = await juriTokenMock.currentMintableTokens()

      const inflation = inflationChange.mul(new BN(2))
      const mintableTokens = totalSupply.mul(inflation).div(new BN(100))
      expect(inflationRound3).to.be.bignumber.equal(inflation)
      expect(currentMintableTokensRound3).to.be.bignumber.equal(mintableTokens)

      const balanceJuriNode1Before = await juriTokenMock.balanceOf(juriNode1)
      const balanceJuriNode2Before = await juriTokenMock.balanceOf(juriNode2)
      const balanceJuriNode3Before = await juriTokenMock.balanceOf(juriNode3)
      const balanceJuriNode4Before = await juriTokenMock.balanceOf(juriNode4)

      await juriTokenMock.retrieveRoundInflationRewards({ from: juriNode1 })
      await juriTokenMock.retrieveRoundInflationRewards({ from: juriNode2 })
      await juriTokenMock.retrieveRoundInflationRewards({ from: juriNode3 })
      await juriTokenMock.retrieveRoundInflationRewards({ from: juriNode4 })

      const balanceJuriNode1After = await juriTokenMock.balanceOf(juriNode1)
      const balanceJuriNode2After = await juriTokenMock.balanceOf(juriNode2)
      const balanceJuriNode3After = await juriTokenMock.balanceOf(juriNode3)
      const balanceJuriNode4After = await juriTokenMock.balanceOf(juriNode4)

      expect(balanceJuriNode1After).to.be.bignumber.equal(
        balanceJuriNode1Before.add(mintableTokens.div(new BN(2)))
      )
      expect(balanceJuriNode2After).to.be.bignumber.equal(
        balanceJuriNode2Before.add(mintableTokens.div(new BN(4)))
      )
      expect(balanceJuriNode3After).to.be.bignumber.equal(
        balanceJuriNode3Before.add(mintableTokens.div(new BN(4)))
      )
      expect(balanceJuriNode4After).to.be.bignumber.equal(
        balanceJuriNode4Before
      )
    })
  })
}

module.exports = itRunsProxyRoundCorrectly
