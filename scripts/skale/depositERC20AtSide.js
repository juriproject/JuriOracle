// const fs = require('fs')
const {
  account,
  getWeb3,
  privateKey,
  privateTestnetJson,
  schainID,
  schainJson,
  Tx,
} = require('./config')

const accountForMainnet = account
const accountForSchain = account

const depositBoxAddress = privateTestnetJson.deposit_box_address
const depositBoxABI = privateTestnetJson.deposit_box_abi

const tokenManagerAddress = schainJson.token_manager_address
const tokenManagerABI = schainJson.token_manager_abi

const erc20ABI = schainJson.eth_erc20_abi
const erc20Address = schainJson.eth_erc20_address

const web3ForMainnet = getWeb3(false)
const web3ForSchain = getWeb3(true)

const exec = async () => {
  const depositBox = new web3ForMainnet.eth.Contract(
    depositBoxABI,
    depositBoxAddress
  )

  const tokenManager = new web3ForSchain.eth.Contract(
    tokenManagerABI,
    tokenManagerAddress
  )

  const contractERC20 = new web3ForMainnet.eth.Contract(erc20ABI, erc20Address)

  const approve = contractERC20.methods
    .approve(
      depositBoxAddress,
      web3ForMainnet.utils.toHex(web3ForMainnet.utils.toWei('1', 'ether'))
    )
    .encodeABI()

  const deposit = depositBox.methods
    .depositERC20(
      schainID,
      erc20Address,
      accountForSchain,
      web3ForMainnet.utils.toHex(web3ForMainnet.utils.toWei('1', 'ether'))
    )
    .encodeABI()

  let nonce = await web3ForMainnet.eth.getTransactionCount(accountForMainnet)

  const rawTxApprove = {
    from: accountForMainnet,
    nonce: '0x' + nonce.toString(16),
    data: approve,
    to: erc20Address,
    gasPrice: 0,
    gas: 8000000,
  }
  nonce += 1
  const rawTxDeposit = {
    from: accountForMainnet,
    nonce: '0x' + nonce.toString(16),
    data: deposit,
    to: depositBoxAddress,
    gasPrice: 0,
    gas: 8000000,
    value: web3ForMainnet.utils.toHex(web3ForMainnet.utils.toWei('1', 'ether')),
  }

  const txApprove = new Tx(rawTxApprove)
  const txDeposit = new Tx(rawTxDeposit)
  txApprove.sign(privateKey)
  txDeposit.sign(privateKey)

  const serializedTxApprove = txApprove.serialize()
  const serializedTxDeposit = txDeposit.serialize()

  try {
    const approveReceipt = await web3ForMainnet.eth.sendSignedTransaction(
      '0x' + serializedTxApprove.toString('hex')
    )
    console.log({ approveReceipt })

    const depositReceipt = await web3ForMainnet.eth.sendSignedTransaction(
      '0x' + serializedTxDeposit.toString('hex')
    )
    console.log({ depositReceipt })

    /* const events = await tokenManager.getPastEvents(
      'ERC20TokenCreated',
      {
        filter: { contractThere: [erc20Address] },
        fromBlock: 0,
        toBlock: 'latest',
      },
      (_, events) => {
        console.log(events)
      }
    )

    console.log(
      'New Created ERC20 clone on Skale Chain: ' +
        events[0].returnValues.contractHere
    )
    const jsonObject = {
      erc20_address: events[0].returnValues.contractHere,
      erc20_abi: erc20ABI,
    }

    fs.writeFile(
      './contracts/ERC20_schain_proxy.json',
      JSON.stringify(jsonObject),
      err => {
        if (err) {
          return console.log(err)
        }

        console.log('Done, check ERC20_schain_proxy.json file in data folder.')
        process.exit(0)
      }
    ) */
  } catch (error) {
    console.log({ error })
  }
}

exec()
