// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

pragma solidity 0.8.17;

contract Token is ERC20, Ownable {
    constructor() ERC20("THE_TOKEN", "TOKEN") {
        _mint(msg.sender, 10_000 * 10 ** 18);
    }
}