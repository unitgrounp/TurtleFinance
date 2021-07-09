// SPDX-License-Identifier: MIT

pragma solidity ^0.8.5;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract ERC1155Contract is ERC1155, Ownable {
    constructor (string memory uri_) ERC1155(uri_)  {
    }
}