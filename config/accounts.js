const nodes = [
  {
    address: '0x609090313b64c65e968162288E619c39D03a69c6',
    privateKey:
      '0xbb5652eb50c53cb1c945b9739430c30fd299343781b1b8b99cb83e2ee5b32783',
  },
  {
    address: '0xDa12C700772F053B5a57CcF403339AA89c060926',
    privateKey:
      '0x194ea715a81f524230b8ff0c373926fd48fabf6030beb9e87ff6d34d8ab9ec86',
  },
  {
    address: '0xCb7B84Dc118D6842248B10a966ce5e62364c2B3F',
    privateKey:
      '0x92fb8c3a5d4fe75d12e3942551d211af1c4143bcdd76971632cb284a2a6b4f34',
  },
  {
    address: '0x69a2A1F51c593295244C5eDa90378Bed74094583',
    privateKey:
      '0x963d056e0d820a47ead9a2c6eca6605104c5414cbe840b8cd4c5024ec8214ba2',
  },
  {
    address: '0x886D615D50789ee2CCc3De7F90b58072C538192d',
    privateKey:
      '0xe5013e07f864fd94dc14a2f3e3a9999eb992ab3354a8c14ed12a419afdad0b36',
  },
  {
    address: '0x2c82aFaB0141e519B1250Be99c76A795b31cCc39',
    privateKey:
      '0x74c3a74492aaee16ffecdd36f1647f72852551b03fe1c5d9e363c657626e4e5f',
  },
  {
    address: '0x210906BCAe4aD9e5eFc4d06971810c95422CE618',
    privateKey:
      '0x21e8700449775c154db2cda13438678dfd7193649263bb9f761da091c0866601',
  },
  {
    address: '0x07d14d4505158F81A0B5D3Fd0252265F37884a3c',
    privateKey:
      '0x245ce2b29789a44a88ea2fe49bf6f8e454141cf869409ae9bc6b286dec857cef',
  },
  {
    address: '0x4c6B770aa009221b39e4A0752C804128D2b49A7b',
    privateKey:
      '0x245f8ceb660d7e6edf2d2bafd79e73da25a2969e2cab379f516c6bc737e42209',
  },
  {
    address: '0x85e421954606B4d7588FBCf1C1D8B3baF594aD70',
    privateKey:
      '0x0f3ab12d7bb70dd3f119e7f246a8a77ffc32ef949dd75a818bb61240fee9f890',
  },
  {
    address: '0x0Ac2FcbC65D791745cbC12c89CD1397DBE9C88E3',
    privateKey:
      '0x3fcb63aff859ca283e831acf01d338f358654694e8aeb8164d597b7a35c6e0fb',
  },
  {
    address: '0x198367D401C5Ff508ad540697A62F2A20F73e4ec',
    privateKey:
      '0xe25cf68c58d36e0914c0d0d350922621c88fc38cba6aedc76d4dba156880ce5f',
  },
  {
    address: '0x0bE5a7B2db114699ec990c614Bf858B9899fDA86',
    privateKey:
      '0xdf71676561b8b88608d49e701ab0eecdca180f21777eb35f17d1aea9ecb69233',
  },
  {
    address: '0xA5Cf98079BEE9F7e40503fdd4D5138358292aCf1',
    privateKey:
      '0x8f465c2e1220c32be9686e132eefa98a93cc697d2964983bc8c51af58f8b9800',
  },
  {
    address: '0x7f642562D4c088d4c7e4Be424ACb9a370463388b',
    privateKey:
      '0xad6603ace3381c36599d11bb27109a56ef42a26be786c017a809f225d548a21b',
  },
  {
    address: '0xA1Bd45D4EBf3a4Be5828816AD8A07c839cFF3Bad',
    privateKey:
      '0x0579ba5e1acd34092b6f50ca5aed7cc8cd73950f12424c60594dba55a0be16e3',
  },
  {
    address: '0x4cE747168F4ce6a63a874b6cbc8636005Ae02137',
    privateKey:
      '0x03e633d3df5b9779efdb28407412a7386ed8bfbc76d4259437effc34483ceb24',
  },
  {
    address: '0x3c2212bc25807746678fF074242d0CF83ADDfe77',
    privateKey:
      '0x8013fd0b50933268647f3707d9da782a792ee331dc71c4ecca239b5a49ee0313',
  },
  {
    address: '0xf0C39cd11b3dBf978Bf962633d4ca012e374604e',
    privateKey:
      '0x3f7fae67f7947639e2caa885dc320675748238356ca050a30b4b485965456c6e',
  },
  {
    address: '0xb35B82d798261295222dcD7CD026A4498Ba681C3',
    privateKey:
      '0x03e364c044a897d166e0ae10f831a9a9529fd292515305fc34696da2da497483',
  },
].map(account => ({
  ...account,
  privateKeyBuffer: Buffer.from(account.privateKey.slice(2), 'hex'),
}))

const users = [
  {
    address: '0x7E0c6B2bE8010CcaB4F3C93CD34CD60E6582b21f',
    privateKey:
      '0x2b04d43db539e9d42a78be6beae048cb9dd3ce82b8047f93ff5d3e5ba6d13986',
  },
  {
    address: '0x411fcF9AaB9F516cEaD0e6826A57775E23f19f5a',
    privateKey:
      '0x7704dde5b64556612ffaf3cb6d5c454848791859e4fe50918c9bbbf39cc6b5e3',
  },
  {
    address: '0xE3a58b4778E5B171249031c3b4defa6e8f58722c',
    privateKey:
      '0xad88ec1134b9f6f4c4a6d6c579af4bc039e6a857f3544972b8c80afcb4a9db54',
  },
  {
    address: '0x26dd0efBa29886B71bDa2117C205aA6db2501973',
    privateKey:
      '0xed9d5de8d30022187ac4aabe89dacc1f3625b4e91dd41ba24b18fa0e34b98f20',
  },
  {
    address: '0xab7F39f99d7aECc2E1516bd0c20c1204C21a0FfD',
    privateKey:
      '0x18346dcefaad7031ca2dcc6b711232fa7127c33ab48e25869d17e22f2aa5c262',
  },
  {
    address: '0x4eD79fa3348fEE0ffa3B0213B701daC561F364DA',
    privateKey:
      '0xf042fe76ab3d31f88268f87f01c86d4550398a5ccfa8944df0a325a15197550e',
  },
  {
    address: '0x63ab1f8A8b2D620B44d0Dd21fBA0a5366b922EF0',
    privateKey:
      '0xd021ab4428994e4d7325d774365f2809dce40530bca3a9066abe6639fc096398',
  },
  {
    address: '0x2060DBf265a0CaC3fA52ef2a87aa715b09116314',
    privateKey:
      '0x9c97f1b36784692f57bb39c32d500b4ed457707d342a1a8e81c62c6d8f7d6ce9',
  },
  {
    address: '0xd7e7091f5a96799466878dC072e07dea88Faefb3',
    privateKey:
      '0x640b7e08ef0ea1963ff315cd3131c8f4ef1d01deec7737e4fbf2eff5ba99724b',
  },
  {
    address: '0xd3881F5A7a1bfE46Fb0707870b6427694fB5A640',
    privateKey:
      '0x9788d83ac69be7297d233a782ddda989e9c935a9296da737bf182ec2700bf7c3',
  },
  {
    address: '0xFc67FE7e46a237016fA20612548e4aFa746995a2',
    privateKey:
      '0xf5d7a7bef4a55f6efdeca880f0f2fc2d05f2ed30d4329d7b9c2226f58e46cf3e',
  },
  {
    address: '0x21D3BA2b2532Fb1D6A08679da9D2631670ECF5CD',
    privateKey:
      '0x58c1586e112ef31f986b4b617faceca7d2cfd3d427cfee98ee876cd35f68d085',
  },
  {
    address: '0x75A992fc285882b71ec5F4B5B92fC5Fd4C4593d3',
    privateKey:
      '0x062cbda30fe6fe15f5d5581f835ff4c6d2ef1260d07a1a0fca05cc706a719d39',
  },
  {
    address: '0x72169c2181064e0913d579473cc4a7abaa1AdC74',
    privateKey:
      '0x44118cb3447a8b6baceecb4f2a094460f01fbac490cbce313c6a35a3d0967e0c',
  },
  {
    address: '0x33285504A341186C29dC4F21353D7bEF579ab257',
    privateKey:
      '0xe6d0a0f88b8545e60b88b728c2da3b953a6f9beaaa901e1f4df36c0ebe390d31',
  },
  {
    address: '0xbbFAc6EfdF3ABE2283daC89A309c434Df882926e',
    privateKey:
      '0x7edbaa20b20897e1ddd5585b68365bb814e4059b159419cc977654550d0a1fff',
  },
  {
    address: '0xc5DD8dcdc93EbD2bFD05e9f8dab99d201e8Ded15',
    privateKey:
      '0x0bbd89201300f57e11e5c7b2c32133e7841e647bcecd33146b659308e38d617c',
  },
  {
    address: '0x8D089df525110e13467dd3E079Cbc353b626Fc5B',
    privateKey:
      '0x6c91032bbfbc50ae4700493a7a02af0eb222b8baaee10143d2ddad1c475bbfb7',
  },
  {
    address: '0x04be2cc61F2341e32d9373b5A3617F3cF9091A9f',
    privateKey:
      '0x0f38f8d390c6fb399186950e3cae8117c2dcb116091a34359f285981994d5c99',
  },
  {
    address: '0x5d1b9f64307AF9697f03087dafD6C3aE49b52554',
    privateKey:
      '0xbfe452ae7510d1e3910f785abf5da614bb20c13156447010d4b5ffbd66c163f2',
  },
].map(account => ({
  ...account,
  privateKeyBuffer: Buffer.from(account.privateKey.slice(2), 'hex'),
}))

module.exports = { nodes, users }
