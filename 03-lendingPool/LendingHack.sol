// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {USDC} from "./USDC.sol";

/**
 * @title LendingPool
 */
contract LendingHack is Ownable {
    /*//////////////////////////////
    //    Add your hack below!    //
    //////////////////////////////*/
    USDC public usdc;
    string public constant name = "LendingPool hack";

    /**
     * @dev Constructor that sets the owner of the contract
     * @param _usdc The address of the USDC contract to use
     * @param _owner The address of the owner of the contract
     */
    constructor(address _owner, address _usdc) {
        _transferOwnership(_owner);
        usdc = USDC(_usdc);
    }

    // Function to steal all USDC from this contract
    function stealFunds(address _hacker) public onlyOwner {
        uint256 balance = usdc.balanceOf(address(this));
        usdc.transfer(_hacker, balance);
    }

    //============================//
}
