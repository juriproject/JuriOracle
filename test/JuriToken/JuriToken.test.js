const itRunsTokenRoundCorrectly = require('./itRunsTokenRoundCorrectly')

const itRunsTokenTestsCorrectlyWithUsers = async addresses => {
  itRunsTokenRoundCorrectly(addresses)
}

module.exports = itRunsTokenTestsCorrectlyWithUsers
