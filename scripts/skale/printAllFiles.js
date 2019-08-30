const Filestorage = require('@skalenetwork/filestorage.js/src/index')

const { account, getWeb3Provider } = require('./config')

const exec = async () => {
  const web3Provider = getWeb3Provider(false)
  const fileStorage = new Filestorage(web3Provider, true)

  const files = await fileStorage.getFileInfoListByAddress(account)
  console.log({ files })
}

exec()
