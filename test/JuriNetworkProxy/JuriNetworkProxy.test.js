const itRunsProxyRoundCorrectly = require('./itRunsProxyRoundCorrectly')

const itRunsProxyTestsCorrectlyWithUsers = async addresses => {
  itRunsProxyRoundCorrectly(addresses)
}

module.exports = itRunsProxyTestsCorrectlyWithUsers
