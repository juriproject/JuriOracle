const assert = require('assert')
const HDWalletProvider = require('truffle-hdwallet-provider')

const DEFAULT_GAS_PRICE_GWEI = 50
const DEFAULT_MNEMONIC =
  'student still brass plug auto harvest sign dry bulb napkin bitter decrease'
// 0x350c1088a07AfFCe586695A6a4500F261e68c350
const GAS_LIMIT = 6.5e6

const awsControllerUrl = require('../JuriNodeApp/management/awsControllerUrl')

function truffleConfig({
  mnemonic = DEFAULT_MNEMONIC,
  gasPriceGWei = DEFAULT_GAS_PRICE_GWEI,
  gas = GAS_LIMIT,
  optimizedEnabled = false,
  urlRinkeby = 'https://rinkeby.infura.io/v3/4744851d37ac46bd95eddf0d50f062a4',
  urlMainnet = 'https://mainnet.infura.io/v3/4744851d37ac46bd95eddf0d50f062a4',
  urlSkaleMain = 'http://134.209.56.46:1919',
  // urlSkaleSide = 'http://165.22.133.157:10101',
  urlSkaleSide = 'https://sip0.skalenodes.com:10018',
  urlAwsController = `http://${awsControllerUrl}:7545`,
  urlDevelopment = 'localhost',
  portDevelopment = 7545,
} = {}) {
  assert(mnemonic, 'The mnemonic has not been provided')

  console.log('')
  console.log(`Using gas limit: ${gas / 1000} K`)
  console.log(`Using gas price: ${gasPriceGWei} Gwei`)
  console.log(`Optimizer enabled: ${optimizedEnabled}`)
  console.log('Using default mnemonic: %s', mnemonic === DEFAULT_MNEMONIC)
  console.log('')

  const gasPrice = gasPriceGWei * 1e9
  const _getProvider = (url, key) => () =>
    new HDWalletProvider(key || mnemonic, url)

  return {
    networks: {
      development: {
        host: urlDevelopment,
        port: portDevelopment,
        gasPrice: 0,
        gas: 50000000,
        network_id: '*',
      },
      mainnet: {
        provider: _getProvider(urlMainnet),
        network_id: '1',
        gas,
        gasPrice,
      },
      rinkeby: {
        provider: _getProvider(urlRinkeby),
        network_id: '4',
        gas,
        gasPrice,
      },
      skaleMain: {
        provider: _getProvider(urlSkaleMain, process.env.KEY),
        gas: 50000000,
        gasPrice: 0,
        network_id: '*',
      },
      skaleSide: {
        provider: _getProvider(urlSkaleSide, process.env.KEY),
        gas: 50000000,
        gasPrice: 0,
        network_id: '*',
      },
      awsController: {
        provider: _getProvider(urlAwsController),
        gas: 50000000,
        gasPrice: 0,
        network_id: '*',
      },
    },
    solc: {
      optimizer: {
        enabled: optimizedEnabled,
      },
    },
    compilers: {
      solc: {
        version: '0.5.10',
      },
    },
    plugins: ['truffle-plugin-verify'],
    api_keys: {
      etherscan: process.env.ETHER_KEY,
    },
  }
}

module.exports = truffleConfig({
  optimizedEnabled: true,
  mnemonic: process.env.MNEMONIC,
})
