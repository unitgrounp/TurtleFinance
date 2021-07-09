// SPDX-License-Identifier: MIT

pragma solidity ^0.8.5;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";


contract ERC20Contract is ERC20 {
    constructor(string memory name, string memory symbol, uint256 initialBalance) ERC20(name, symbol) {
        _mint(msg.sender, initialBalance);
    }
}