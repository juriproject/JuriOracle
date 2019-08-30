const Filestorage = require('@skalenetwork/filestorage.js/src/index')

const { getWeb3Provider } = require('./config')

const exec = async () => {
  const web3Provider = getWeb3Provider(false)
  const fileStorage = new Filestorage(web3Provider, true)

  const storagePath = '15ae150d7dC03d3B635EE90b85219dBFe071ED35/testFileName1'

  const file = await fileStorage.downloadToBuffer(storagePath)
  console.log({ file })

  const result = file.toString('utf-8')
  console.log({ result })
}

exec()
