// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import '../node_modules/@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract Dai is ERC20 {
    constructor() ERC20("Mock Dai Stable Coin", "DAI") {
        _mint(msg.sender, 1000 * 10**18);
    }
}