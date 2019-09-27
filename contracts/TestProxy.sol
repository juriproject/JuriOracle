pragma solidity 0.5.10;

contract TestProxy {
    address public storedSender;
    string public storedFromSchainID;
    address payable public storedTo;
    uint256 public storedAmount;
    bytes public storedData;

    function postMessage(
        address sender, 
        string calldata fromSchainID, 
        address payable to, 
        uint amount, 
        bytes calldata data
    ) external {
        storedSender = sender;
        storedFromSchainID = fromSchainID;
        storedTo = to;
        storedAmount = amount;
        storedData = data;
    }
}