const {
  account,
  getWeb3,
  privateKey,
  privateTestnetJson,
  schainID,
  Tx,
} = require('./config')

const exec = async () => {
  const depositBoxAddress = privateTestnetJson.deposit_box_address
  const abi = privateTestnetJson.deposit_box_abi
  const web3 = getWeb3(true)

  const contract = new web3.eth.Contract(abi, depositBoxAddress)
  const deposit = contract.methods.deposit(schainID, account).encodeABI()

  const rawTx = {
    from: account,
    nonce: await web3.eth.getTransactionCount(account),
    data: deposit,
    to: depositBoxAddress,
    gasPrice: 0,
    gas: 8000000,
    value: web3.utils.toHex(web3.utils.toWei('1', 'ether')),
  }

  const tx = new Tx(rawTx)
  tx.sign(privateKey)

  const serializedTx = tx.serialize()

  const result = await web3.eth.sendSignedTransaction(
    '0x' + serializedTx.toString('hex')
  )
  console.log({ result })
}

exec()
