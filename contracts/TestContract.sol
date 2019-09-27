pragma solidity 0.5.10;

import "./SkaleMessageProxyInterface.sol";

contract TestContract {
    address public skaleMessageProxyAddressMain;
    SkaleMessageProxyInterface public skaleMessageProxySide;

    constructor(
        address _skaleMessageProxyAddressMain,
        address _skaleMessageProxyAddressSide
    ) public {
        skaleMessageProxyAddressMain = _skaleMessageProxyAddressMain;
        skaleMessageProxySide = SkaleMessageProxyInterface(_skaleMessageProxyAddressSide);
    }

    function sendMessageToSkale() external {
        bytes memory data = new bytes(0);

        skaleMessageProxySide.postOutgoingMessage(
            'Mainnet', 
            skaleMessageProxyAddressMain, // dstContract
            0, // amount
            0x15ae150d7dC03d3B635EE90b85219dBFe071ED35, // to
            data
        );
    }
}