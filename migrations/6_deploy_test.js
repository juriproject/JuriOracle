const TestContract = artifacts.require('./TestContract.sol')

const {
  message_proxy_for_schain_address,
} = require('../contracts/lib/skale/rinkeby_ABIs.json')

const testProxyAddress = '0x6C989A448cDE99F6dd4B35ad93ae767Ce47cfA36'

module.exports = deployer => {
  deployer.then(async () => {
    const deployedTest = await deployer.deploy(
      TestContract,
      testProxyAddress,
      message_proxy_for_schain_address
    )
    console.log({ deployedTest: deployedTest.address })
  })
}
