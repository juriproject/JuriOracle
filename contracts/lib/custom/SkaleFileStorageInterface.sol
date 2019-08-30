pragma solidity 0.5.10;

interface SkaleFileStorageInterface {
    function getFileStatus(string calldata storagePath) external returns (uint8);
}