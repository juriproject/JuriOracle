const { account, getWeb3, privateKey, Tx } = require('./config')

const privateTestnetJson = require('../../contracts/private_skale_testnet_proxy.json')

const exec = async () => {
  const lockAndDataForMainnetAddress =
    privateTestnetJson.lock_and_data_for_mainnet_address
  const lockAndDataForMainnetABI =
    privateTestnetJson.lock_and_data_for_mainnet_abi

  const web3 = getWeb3(true)

  const LockAndDataForMainnet = new web3.eth.Contract(
    lockAndDataForMainnetABI,
    lockAndDataForMainnetAddress
  )

  const getMyEth = LockAndDataForMainnet.methods.getMyEth().encodeABI()

  const nonce = await web3.eth.getTransactionCount(account)
  const rawTxGetMyEth = {
    from: account,
    nonce: '0x' + nonce.toString(16),
    data: getMyEth,
    to: lockAndDataForMainnetAddress,
    gasPrice: 0,
    gas: 8000000,
    value: 0,
  }

  const txGetMyEth = new Tx(rawTxGetMyEth)
  txGetMyEth.sign(privateKey)

  const serializedTxGetMyEth = txGetMyEth.serialize()

  const receipt = await web3.eth.sendSignedTransaction(
    '0x' + serializedTxGetMyEth.toString('hex')
  )

  console.log({ receipt })
}

exec()
