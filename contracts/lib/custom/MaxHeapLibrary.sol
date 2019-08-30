pragma solidity 0.5.10;

import "../../lib/SafeMath.sol";

library MaxHeapLibrary {
    using SafeMath for uint256;

    /*
    // The main operations of a priority queue are insert, delMax, & isEmpty.
    constructor() public {
        // Start at 0
        heap = [MaxHeapEntry(address(0), 0)];
    }
    */

    event BubbleStart(uint256 counter, uint256 currentIndex, uint256 heapLength);
    event Bubble(uint256 counter, uint256 currentIndex);

    struct MaxHeapEntry {
        address node;
        uint256 value;
    }

    struct heapStruct {
        MaxHeapEntry[] elements;
    }

    // Inserts adds in a value to our heap.
    function insert(heapStruct storage heap, address _node, uint256 _value) public {
        if (heap.elements.length == 0) {
            MaxHeapEntry memory emptyEntry = MaxHeapEntry(address(0), 0);
            heap.elements.push(emptyEntry);
        }

        MaxHeapEntry memory newEntry = MaxHeapEntry(_node, _value);

        // Add the value to the end of our array
        heap.elements.push(newEntry);
        // Start at the end of the array
        uint256 currentIndex = heap.elements.length.sub(1);

        // Bubble up the value until it reaches it's correct place (i.e. it is smaller than it's parent)
        while (currentIndex > 1 && heap.elements[currentIndex.div(2)].value < heap.elements[currentIndex].value) {
            // If the parent value is lower than our current value, we swap them
            MaxHeapEntry memory heapEntry = _clone(heap.elements[currentIndex.div(2)]);

            heap.elements[currentIndex.div(2)] = newEntry;
            heap.elements[currentIndex] = heapEntry;

            // change our current Index to go up to the parent
            currentIndex = currentIndex.div(2);
        }
    }

    // RemoveMax pops off the root element of the heap (the highest value here) and rebalances the heap
    function removeMax(heapStruct storage heap) public returns (address) {
        // Ensure the heap exists
        require(
            heap.elements.length > 1,
            "There are no elements in the heap to remove!"
        );
        // take the root value of the heap
        address removedNode = heap.elements[1].node;

        // Takes the last element of the array and put it at the root
        heap.elements[1] = heap.elements[heap.elements.length.sub(1)];
        // Delete the last element from the array
        heap.elements.length = heap.elements.length.sub(1);
    
        // Start at the top
        uint256 currentIndex = 1;

        uint256 counter = 0;

        emit BubbleStart(counter, currentIndex, heap.elements.length);

        // Bubble down
        while (currentIndex.mul(2) < heap.elements.length.sub(1)) {
            counter++;

            emit Bubble(counter, currentIndex);

            // get the current index of the children
            uint256 j = currentIndex.mul(2);

            // left child value
            uint256 leftChild = heap.elements[j].value;
            // right child value
            uint256 rightChild = heap.elements[j.add(1)].value;

            // Compare the left and right child. if the rightChild is greater, then point j to it's index
            if (leftChild < rightChild) {
                j = j.add(1);
            }

            // compare the current parent value with the highest child, if the parent is greater, we're done
            if (heap.elements[currentIndex].value > heap.elements[j].value) {
                break;
            }

            // else swap the value
            MaxHeapEntry memory entry1 = _clone(heap.elements[currentIndex]);
            heap.elements[currentIndex] = _clone(heap.elements[j]);
            heap.elements[j] = entry1;

            // and let's keep going down the heap
            currentIndex = j;
        }

        if (currentIndex == 1 && heap.elements.length == 3) {
            if (heap.elements[1].value < heap.elements[2].value) {
                MaxHeapEntry memory entry1 = _clone(heap.elements[1]);
                heap.elements[1] = _clone(heap.elements[2]);
                heap.elements[2] = entry1;
            }
        }

        // finally, return the top of the heap
        return removedNode;
    }


    function getHeap(heapStruct storage heap) public view returns (MaxHeapEntry[] storage) {
        return heap.elements;
    }

    function getLowestHashes(heapStruct storage heap) public view returns (uint256[] memory) {
        if (heap.elements.length == 0) return new uint256[](0);

        uint256[] memory lowestHashes = new uint256[](heap.elements.length - 1);

        for (uint256 i = 0; i < heap.elements.length - 1; i++) {
            lowestHashes[i] = heap.elements[i + 1].value;
        }

        return lowestHashes;
    }

    function getMax(heapStruct storage heap) public view returns (MaxHeapEntry storage) {
        if (heap.elements.length == 1) {
            return heap.elements[0];
        }

        return heap.elements[1];
    }

    function getLength(heapStruct storage heap) public view returns (uint256) {
        if (heap.elements.length == 0) {
            return 0;
        }

        return heap.elements.length - 1;
    }

    function _clone(MaxHeapEntry memory from) internal pure returns (MaxHeapEntry memory) {
        return MaxHeapEntry(from.node, from.value);
    }
}