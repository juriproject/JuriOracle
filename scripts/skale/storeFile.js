#!/usr/bin/env node

const Filestorage = require('@skalenetwork/filestorage.js/src/index')

const { account, getWeb3Provider } = require('./config')

const exec = async () => {
  const web3Provider = getWeb3Provider(false)
  const fileStorage = new Filestorage(web3Provider, true)

  const fileName = 'testFileName4'
  const fileBuffer = Buffer.from('Hello World')
  const formattedPrivateKey = '0x' + process.env.KEY

  try {
    const storedFilePath = await fileStorage.uploadFile(
      account,
      fileName,
      fileBuffer,
      formattedPrivateKey
    )

    console.log({ storedFilePath })
  } catch (error) {
    console.log({ error })
  }
}

exec()
