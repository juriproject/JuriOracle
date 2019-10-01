const fs = require('fs')

const ERC20Mintable = artifacts.require('./ERC20Mintable.sol')

const lockAndDataForSchainERC20Address =
  '0xc4345Ea69018c9E6dc829DF362C8A9aa18b9e39e'

const fs_writeFile = require('util').promisify(fs.writeFile)

module.exports = async deployer => {
  await deployer.then(async () => {
    const erc20Mintable = await deployer.deploy(ERC20Mintable)

    console.log({
      juriTokenSide: erc20Mintable.address,
    })

    await erc20Mintable.addMinter(lockAndDataForSchainERC20Address)
    await fs_writeFile(
      __dirname + '\\data\\deployed.json',
      JSON.stringify({
        ...require('./data/deployed'),
        juriTokenSide: erc20Mintable.address,
      })
    )

    return deployer.deploy(ERC20Mintable)
  })
}
