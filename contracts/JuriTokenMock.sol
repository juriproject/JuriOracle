pragma solidity 0.5.10;

import "./JuriToken.sol";
import "./lib/ERC20Mintable.sol";

contract JuriTokenMock is JuriToken, ERC20Mintable  {
    function setJuriBonding(JuriBonding _bonding) public {
        bonding = _bonding;
    }

    function setJuriNetworkProxy(JuriNetworkProxy _proxy) public {
        proxy = _proxy;
    }
}