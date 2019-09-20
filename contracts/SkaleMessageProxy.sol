pragma solidity 0.5.10;

import "./JuriToken.sol";
import "./SkaleMessageProxyInterface.sol";

contract SkaleMessageProxy is SkaleMessageProxyInterface {
    JuriToken public juriToken;

    constructor(address _juriTokenAddress) public {
        juriToken = JuriToken(_juriTokenAddress);
    }

    function postOutgoingMessage(
        string calldata dstChainID, 
        address dstContract, 
        uint256 amount, 
        address to, 
        bytes calldata data
        // bytes calldata bls
    ) external {
        require(
            dstContract == address(juriToken),
            'You may only send messages to the JuriToken!'
        );
        require(
            data.length >= 30, // 30 = min possible data
            'You must pass data for this call!'
        );

        // TODO verify BLS

        bool isFirstActivityAddition = uint8(data[0]) > 0;

        uint256 nodesDataLength = isFirstActivityAddition
            ? data.length - 37
            : data.length - 1;

        uint256 nodesCount = nodesDataLength / 24;
        uint256 initialNodesAddressIndex = 37;
        uint256 initialNodesActivityIndex = initialNodesAddressIndex + nodesCount * 20;
        address[] memory nodeAddressList = new address[](nodesCount);
        uint32[] memory nodeActivityList = new uint32[](nodesCount);

        for (uint256 i = 0; i < nodesCount; i++) {
            uint256 nodesAddressIndex = initialNodesAddressIndex + i * 20;
            uint256 nodesActivityIndex = initialNodesActivityIndex + i * 4;

            nodeAddressList[i] = _bytesToAddr([
                data[nodesAddressIndex],
                data[nodesAddressIndex + 1],
                data[nodesAddressIndex + 2],
                data[nodesAddressIndex + 3],
                data[nodesAddressIndex + 4],
                data[nodesAddressIndex + 5],
                data[nodesAddressIndex + 6],
                data[nodesAddressIndex + 7],
                data[nodesAddressIndex + 8],
                data[nodesAddressIndex + 9],
                data[nodesAddressIndex + 10],
                data[nodesAddressIndex + 11],
                data[nodesAddressIndex + 12],
                data[nodesAddressIndex + 13],
                data[nodesAddressIndex + 14],
                data[nodesAddressIndex + 15],
                data[nodesAddressIndex + 16],
                data[nodesAddressIndex + 17],
                data[nodesAddressIndex + 18],
                data[nodesAddressIndex + 19]
            ]);
            nodeActivityList[i] = _bytesToUint32(
                data[nodesActivityIndex],
                data[nodesActivityIndex + 1],
                data[nodesActivityIndex + 2],
                data[nodesActivityIndex + 3]
            );
        }

        if (isFirstActivityAddition) {
            uint32 totalActivity = _bytesToUint32(
                data[1],
                data[2],
                data[3],
                data[4]
            );
            uint256 totalBonded = _bytesToUint256([
                data[5],
                data[6],
                data[7],
                data[8],
                data[9],
                data[10],
                data[11],
                data[12],
                data[13],
                data[14],
                data[15],
                data[16],
                data[17],
                data[18],
                data[19],
                data[20],
                data[21],
                data[22],
                data[23],
                data[24],
                data[25],
                data[26],
                data[27],
                data[28],
                data[29],
                data[30],
                data[31],
                data[32],
                data[33],
                data[34],
                data[35],
                data[36]
            ]);

            juriToken.updateActivityList(
                totalActivity,
                totalBonded,
                nodeAddressList,
                nodeActivityList
            );
        } else {
            juriToken.updateActivityList(
                nodeAddressList,
                nodeActivityList
            );
        }
    }

    function _bytesToUint32(
        bytes1 _byte0,
        bytes1 _byte1,
        bytes1 _byte2,
        bytes1 _byte3
    ) private pure returns (uint32) {
        uint32 result = 0;

        result += uint32(bytes4(_byte3)) / (2 ** 24);
        result += uint32(bytes4(_byte2)) / (2 ** 16);
        result += uint32(bytes4(_byte1)) / (2 ** 8);
        result += uint32(bytes4(_byte0));

        return result;
    }
    
    function _bytesToUint256(
        bytes1[32] memory _bytes
    ) private pure returns (uint256) {
        uint256 result = 0;

        for (uint256 i = 32; i > 0; i--) {
            uint256 valueAtIndex = uint256(bytes32(_bytes[i - 1]));
            result += valueAtIndex / (2 ** (8 * (i - 1)));
        }

        return result;
    }

    function _bytesToAddr(
        bytes1[20] memory _bytes
    ) private pure returns (address) {
        uint256 result = 0;

        for (uint256 i = 20; i > 0; i--) {
            uint256 valueAtIndex = uint256(bytes32(_bytes[i - 1]));
            result += valueAtIndex / (2 ** (8 * (i - 1 + 12)));
        }

        return address(result);
    }
}