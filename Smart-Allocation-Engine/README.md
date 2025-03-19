# Multi-Token Index Fund Smart Contract

## Overview

This smart contract implements a decentralized multi-token index fund on the Stacks blockchain. It allows users to contribute various supported tokens to gain exposure to a diversified portfolio managed according to predefined allocation targets. The contract includes functionality for token contribution, redemption, portfolio rebalancing, and fund administration.

## Features

- Support for up to 10 different tokens in the index
- Automated management fee collection (0.3% annual fee)
- Portfolio rebalancing when allocation deviations exceed 5%
- Emergency pause functionality for security
- Transparent token allocation targets and portfolio composition

## Contract Functions

### Administrative Functions

#### `register-index-token`
Registers a new token to be included in the index fund.
- Parameters:
  - `token-symbol`: The symbol of the token to add
  - `allocation-percentage`: Target percentage allocation for this token
  - `token-contract`: The fungible token contract reference

#### `set-token-price`
Sets the market price for a supported token.
- Parameters:
  - `token-symbol`: The symbol of the token
  - `market-price`: Current market price of the token

#### `activate-emergency-pause` / `deactivate-emergency-pause`
Toggles the emergency pause state, which prevents token contributions and redemptions.

#### `rebalance-index`
Initiates a portfolio rebalancing if the deviation from target allocations exceeds the threshold.

### User Functions

#### `contribute-tokens`
Allows users to contribute tokens to the index fund.
- Parameters:
  - `token-symbol`: The symbol of the token being contributed
  - `token-contract`: The fungible token contract reference
  - `deposit-amount`: Amount of tokens to contribute

#### `redeem-tokens`
Allows users to redeem their share of tokens from the index fund.
- Parameters:
  - `token-symbol`: The symbol of the token to redeem
  - `token-contract`: The fungible token contract reference
  - `redemption-amount`: Amount of tokens to redeem

### Read-Only Functions

#### `get-user-balance`
Returns the balance of a specified user.

#### `get-token-allocation`
Returns the target allocation percentage for a specified token.

#### `get-supported-tokens`
Returns the list of tokens supported by the index fund.

#### `get-fund-total-supply`
Returns the total supply of tokens in the fund.

## Error Codes

- `ERR-NO-PERMISSION (u100)`: Caller doesn't have permission for this operation
- `ERR-ZERO-DEPOSIT (u101)`: Attempted to deposit zero tokens
- `ERR-BALANCE-TOO-LOW (u102)`: Insufficient balance for withdrawal
- `ERR-TOKEN-NOT-SUPPORTED (u103)`: Token is not supported by the index
- `ERR-REBALANCE-NOT-NEEDED (u104)`: Rebalancing not needed at this time
- `ERR-REBALANCE-FAILED (u105)`: Rebalancing operation failed
- `ERR-TOKEN-ALREADY-EXISTS (u106)`: Token is already registered in the index
- `ERR-INVALID-WEIGHT (u107)`: Invalid allocation weight specified
- `ERR-ZERO-PRICE (u108)`: Zero price specified for a token
- `ERR-SELF-CONTRACT (u109)`: Attempted to register the contract's own token

## Configuration Constants

- `fund-owner`: The owner/administrator of the fund
- `yearly-fee-basis-points`: Annual management fee in basis points (30 = 0.3%)
- `portfolio-deviation-threshold-basis-points`: Threshold for rebalancing (500 = 5%)
- `max-index-tokens`: Maximum number of tokens allowed in the index (10)

## Security Features

- Permission checks for administrative functions
- Emergency pause mechanism
- Token validation before transactions
- Management fee calculation based on block height

## Usage Example

1. Fund administrator registers supported tokens with their target allocations
2. Users contribute tokens to the fund
3. Administrator updates token prices periodically
4. Administrator rebalances the portfolio when necessary
5. Users can redeem their tokens at any time, minus a management fee

## Implementation Notes

- The contract follows the SIP-010 fungible token standard
- Rebalancing logic is implemented but the actual execution function is currently a placeholder
- Management fees are calculated based on the time elapsed since the last rebalance