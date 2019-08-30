const itRunsBondingTestsCorrectlyWithUsers = require('./JuriBonding/JuriBonding.test')
const itRunsProxyTestsCorrectlyWithUsers = require('./JuriNetworkProxy/JuriNetworkProxy.test')
const itRunsStakingPoolWithOracleTestsCorrectlyWithUsers = require('./JuriStakingPoolWithOracle/JuriStakingPoolWithOracle.test')
const itRunsTokenTestsCorrectlyWithUsers = require('./JuriToken/JuriToken.test')

contract('JuriNetworkProxy', accounts => {
  itRunsProxyTestsCorrectlyWithUsers(accounts)
})

contract('JuriBonding', accounts => {
  itRunsBondingTestsCorrectlyWithUsers(accounts)
})

contract('JuriStakingPoolWithOracle', accounts => {
  itRunsStakingPoolWithOracleTestsCorrectlyWithUsers(accounts)
})

contract('JuriToken', accounts => {
  itRunsTokenTestsCorrectlyWithUsers(accounts)
})
