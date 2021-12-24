// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import '../node_modules/@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract Bat is ERC20 {
    constructor() ERC20("Brave browser token", "Bat") {
        _mint(msg.sender, 1000 * 10**18);
    }
}