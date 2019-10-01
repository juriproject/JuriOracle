pragma solidity 0.5.10;

import './SkaleMessageProxyInterface.sol';

contract SkaleMessageProxySideMock is SkaleMessageProxyInterface {
    event Message(
        string dstChainID, 
        address dstContract, 
        uint amount, 
        address to, 
        bytes data
    );

    function postOutgoingMessage(
        string calldata dstChainID, 
        address dstContract, 
        uint amount, 
        address to, 
        bytes calldata data
    ) external {
        emit Message(
            dstChainID,
            dstContract,
            amount,
            to,
            data
        );
    }
}