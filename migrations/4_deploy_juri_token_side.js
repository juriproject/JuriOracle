const fs = require('fs')

const ERC20Mintable = artifacts.require('./ERC20Mintable.sol')

const deployedTokens = require('./data/deployed')

const lockAndDataForSchainERC20Address =
  '0xc4345Ea69018c9E6dc829DF362C8A9aa18b9e39e'

module.exports = deployer => {
  deployer.then(async () => {
    const erc20Mintable = await deployer.deploy(ERC20Mintable)

    console.log({
      juriTokenSide: erc20Mintable.address,
    })

    await erc20Mintable.addMinter(lockAndDataForSchainERC20Address)

    fs.writeFileSync(
      __dirname + '\\data\\deployed.json',
      JSON.stringify({
        ...deployedTokens,
        juriTokenSide: erc20Mintable.address,
      })
    )
  })
}
