const Tx = require('ethereumjs-tx').Transaction

const { account, getWeb3, privateKey, schainID } = require('./skale/config')
const rinkebyABIs = require('../contracts/lib/skale/rinkeby_ABIs.json')
const erc20ABI = require('../build/contracts/ERC20Mintable').abi

const depositBoxAddress = rinkebyABIs.deposit_box_address
const depositBoxABI = rinkebyABIs.deposit_box_abi

const { juriTokenSide, juriTokenMain } = require('../migrations/data/deployed')

const makeDeposit = async () => {
  const web3ForMainnet = getWeb3(true)
  const depositBox = new web3ForMainnet.eth.Contract(
    depositBoxABI,
    depositBoxAddress
  )
  const contractERC20 = new web3ForMainnet.eth.Contract(erc20ABI, juriTokenMain)

  const rawTxApprove = {
    from: account,
    nonce:
      '0x' +
      (await web3ForMainnet.eth.getTransactionCount(account)).toString(16),
    data: contractERC20.methods
      .approve(
        depositBoxAddress,
        web3ForMainnet.utils.toHex(web3ForMainnet.utils.toWei('1', 'ether'))
      )
      .encodeABI(),
    to: juriTokenMain,
    gas: 6500000,
    gasPrice: 100000000000,
  }

  const txApprove = new Tx(rawTxApprove, { chain: 'rinkeby' })
  txApprove.sign(privateKey)
  const serializedTxApprove = txApprove.serialize()

  const receiptApprove = await web3ForMainnet.eth.sendSignedTransaction(
    '0x' + serializedTxApprove.toString('hex')
  )
  console.log({ receiptApprove })

  const rawTxDeposit = {
    from: account,
    nonce:
      '0x' +
      (await web3ForMainnet.eth.getTransactionCount(account)).toString(16),
    data: depositBox.methods
      .rawDepositERC20(
        schainID,
        juriTokenMain,
        juriTokenSide,
        account,
        web3ForMainnet.utils.toHex(web3ForMainnet.utils.toWei('1', 'ether'))
      )
      .encodeABI(),
    to: depositBoxAddress,
    gas: 6500000,
    gasPrice: 100000000000,
    value: web3ForMainnet.utils.toHex(
      web3ForMainnet.utils.toWei('0.1', 'ether')
    ),
  }

  const txDeposit = new Tx(rawTxDeposit, { chain: 'rinkeby' })
  txDeposit.sign(privateKey)
  const serializedTxDeposit = txDeposit.serialize()

  const receiptDeposit = await web3ForMainnet.eth.sendSignedTransaction(
    '0x' + serializedTxDeposit.toString('hex')
  )
  console.log({ receiptDeposit })
}

makeDeposit()

module.exports = makeDeposit
