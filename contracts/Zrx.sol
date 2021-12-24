// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import '../node_modules/@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract Zrx is ERC20 {
    constructor() ERC20("0x Token", "ZRX") {
        _mint(msg.sender, 1000 * 10**18);
    }
}