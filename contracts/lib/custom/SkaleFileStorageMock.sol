pragma solidity 0.5.10;

import "./SkaleFileStorageInterface.sol";

contract SkaleFileStorageMock is SkaleFileStorageInterface {
    function getFileStatus(string calldata storagePath) external returns (uint8) {
        return 2;
    }
}