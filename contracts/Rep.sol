// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import '../node_modules/@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract Rep is ERC20 {
    constructor() ERC20("Augur token", "REP") {
        _mint(msg.sender, 1000 * 10**18);
    }

    function faucet(address to, uint amount) external {
    _mint(to, amount);
  }
}