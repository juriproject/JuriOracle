const itRunsBondingRoundCorrectly = require('./itRunsBondingRoundCorrectly')

const itRunsBondingTestsCorrectlyWithUsers = async addresses => {
  itRunsBondingRoundCorrectly(addresses)
}

module.exports = itRunsBondingTestsCorrectlyWithUsers
