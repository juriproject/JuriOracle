const fs = require('fs')

const JuriTokenMock = artifacts.require('./JuriTokenMock.sol')

const { account } = require('../scripts/skale/config')

const ONE_HUNDRED_TOKEN = '1000000000000000000'

module.exports = deployer => {
  deployer.then(async () => {
    const juriToken = await deployer.deploy(JuriTokenMock)
    await juriToken.mint(account, ONE_HUNDRED_TOKEN)
    const skaleMessageProxyMain = await juriToken.skaleMessageProxy()

    console.log({
      juriTokenMain: juriToken.address,
      skaleMessageProxyMain: skaleMessageProxyMain,
    })

    fs.writeFileSync(
      __dirname + '\\data\\deployed.json',
      JSON.stringify({
        juriTokenMain: juriToken.address,
        juriTokenSide: '- waiting for deployment -',
        skaleMessageProxyMain: skaleMessageProxyMain,
      })
    )
  })
}
