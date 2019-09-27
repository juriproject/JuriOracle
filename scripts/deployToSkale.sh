npx truffle migrate --f 3 --to 3 --network rinkeby
npx truffle migrate --f 4 --to 4 --network skaleSide
KEY=$1 node ./scripts/depositErc20FromMain.js
npx truffle migrate --f 5 --to 5 --network skaleSide