const fs = require('fs')
const erc20PrivateTestnetJson = require('../../contracts/ERC20_private_skale_testnet.json')

const { account, getWeb3, privateTestnetJson, schainJson } = require('./config')

const accountForMainnet = account
const accountForSchain = account

const depositBoxAddress = privateTestnetJson.deposit_box_address
const tokenManagerAddress = schainJson.token_manager_address
const erc20ABI = schainJson.zhelcoin_abi
const erc20Address = schainJson.zhelcoin_address

const web3ForMainnet = getWeb3(false)
const web3ForSchain = getWeb3(true)

const exec = async () => {
  let contract = new web3ForMainnet.eth.Contract(erc20ABI, erc20Address)

  console.log('ERC20 contract address: ' + erc20Address)

  const balanceMainnet = await contract.methods
    .balanceOf(accountForMainnet)
    .call()
  console.log('Account balance on private SKALE: ' + balanceMainnet)

  const balanceDeposit = await contract.methods
    .balanceOf(depositBoxAddress)
    .call()
  console.log('Balance in private SKALE testnet Deposit Box: ' + balanceDeposit)

  if (fs.existsSync('../contracts/ERC20_schain_proxy.json') == true) {
    const erc20SchainJson = require('../contracts/ERC20_schain_proxy.json')
    const erc20ABISchain = erc20SchainJson.erc20_abi
    const erc20AddressSchain = erc20SchainJson.erc20_address
    const contractSchain = new web3ForSchain.eth.Contract(
      erc20ABISchain,
      erc20AddressSchain
    )

    const balanceSChain = await contractSchain.methods
      .balanceOf(accountForSchain)
      .call()

    console.log('Account balance on SKALE chain: ' + balanceSChain)

    const balanceTokenManageer = await contractSchain.methods
      .balanceOf(tokenManagerAddress)
      .call()
    console.log('Balance in SKALE chain TokenManager: ' + balanceTokenManageer)
  }
}

exec()
