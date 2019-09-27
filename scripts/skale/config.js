/*
SKALE Chain ID: UPPC7EI4
SKALE Chain Proxy (ABIs): http://bit.ly/2Xl3Iqh
SKALE Private Net Proxy (ABIs): http://bit.ly/2XlRUo3
SKALE Private Net Endpoint: http://134.209.56.46:1919


Chain ID 2: '1KYUQ531'
SKALE Private Net Endpoint 2: http://165.22.133.157:10101
*/

const Tx = require('ethereumjs-tx')
const Web3 = require('web3')

// const schainEndpointMain = 'http://134.209.56.46:1919'
const schainEndpointMain =
  'https://rinkeby.infura.io/v3/4744851d37ac46bd95eddf0d50f062a4'

const schainEndpointSide = 'https://sip0.skalenodes.com:10018'
const schainID = 'quiet-alkalurops'

const getEndpoint = isMain => (isMain ? schainEndpointMain : schainEndpointSide)

const getWeb3Provider = isMain =>
  new Web3.providers.HttpProvider(getEndpoint(isMain))

const getWeb3 = isMain => new Web3(getWeb3Provider(isMain))

const getLocalWeb3 = () =>
  new Web3(new Web3.providers.HttpProvider('http://localhost:7545'))

const privateKey = process.env.KEY
  ? Buffer.from(process.env.KEY, 'hex')
  : undefined

// const account = '0x15ae150d7dC03d3B635EE90b85219dBFe071ED35'
const account = '0x350c1088a07AfFCe586695A6a4500F261e68c350'

// const privateTestnetJson = require('../../contracts/skale/private_skale_testnet_proxy.json')
// const privateTestnetJson = require('../../contracts/skale/rinkeby_ABIs.json')

// const schainJson = require('../../contracts/skale/schain_proxy.json')
// const schainJson = require('../../contracts/skale/schain_ABIs.json')

module.exports = {
  account,
  getLocalWeb3,
  getWeb3,
  getWeb3Provider,
  privateKey,
  // privateTestnetJson,
  schainID,
  // schainJson,
  Tx,
}
