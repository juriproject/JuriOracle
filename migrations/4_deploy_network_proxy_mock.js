const ERC20Mintable = artifacts.require('./lib/ERC20Mintable.sol')
const JuriNetworkProxyMock = artifacts.require('./JuriNetworkProxyMock.sol')
const MaxHeapLibrary = artifacts.require('./MaxHeapLibrary.sol')

module.exports = deployer => {
  deployer.then(async () => {
    await deployer.deploy(MaxHeapLibrary)
    await deployer.link(MaxHeapLibrary, [JuriNetworkProxyMock])

    const juriToken = await deployer.deploy(ERC20Mintable)
    const juriFeesToken = await deployer.deploy(ERC20Mintable)
    const juriFoundation = '0x15ae150d7dc03d3b635ee90b85219dbfe071ed35'

    await deployer.deploy(
      JuriNetworkProxyMock,
      juriFeesToken.address,
      juriToken.address,
      juriFoundation,
      '10000000000000000000',
      10,
      20,
      40,
      40
    )
  })
}
