# ⏳ Time-Limited Access Pass 

Sell **time-bound access** to events, courses, tools, or apps. Buyers receive access that **automatically expires** after a defined duration. No monthly cron jobs, no off-chain databases required — the **block timestamp** is the source of truth.

--- 
 
## 🔍 What
     
A self-contained smart contract that lets an admin:      

- **Create multiple pass types** (e.g., “Day Pass”, “Monthly”, “Annual”, “VIP”) 
- Set **price**, **duration**, **max supply (optional)**, and whether time is **stackable**
- **Sell** passes in exchange for ETH
- **Grant** passes manually (airdrop/comp/support)
- **Revoke** access (if needed)
- **Withdraw** collected payments

Users can:

- **Buy** access for a selected pass type (quantity allowed)
- **Extend** access by buying again (time stacks from current expiration)
- **Check** their access and time remaining on-chain

---

## 🤔 Why

- **Automates expiring memberships**: Duration is enforced on-chain; no manual cleanup.
- **Simple integration**: A single `hasAccess(user, passId)` view call powers your backend, API, or dApp guard.
- **Transparent & trust-minimized**: Pricing, supply, and expirations are public, auditable state.
- **Flexible monetization**: One-day trials, monthly plans, seasonal passes, or capped VIP drops.
- **Vendor-neutral**: No token standards required — lightweight, gas-efficient, and KISS.

---

## ✨ Key Features

- **Multiple Pass Types**: Each with `price`, `duration (seconds)`, `maxSupply` (0 = unlimited), `isActive`, `stackable`, and a human-friendly `name`.
- **Time Stacking**:
  - If a user is active, new purchases **extend** from the current expiration.
  - If expired, the pass **starts** from `block.timestamp`.
  - Quantity > 1 multiplies duration.
- **Admin Tools**: Create/update pass types, grant time, revoke access, withdraw funds.
- **No External Imports**: Minimal `Ownable` + `nonReentrant` built-in.
- **View Helpers**: `hasAccess`, `timeRemaining`, `expiresAt`, `getPassType`.

---

## 🧩 How It Works

- **Create a pass type** (e.g., Monthly = 30 days):
  - `createPassType("Monthly", priceWei, 30 days, 0, true, true)`
- **Sell**: Users call `buy(passId, quantity)` and send `price * quantity` wei.
- **Extend**: Buying again extends from the later of `now` or `currentExpiration`.
- **Check**: Gate your app by reading `hasAccess(msg.sender, passId)`.
- **Grant**: Admin can `grant(user, passId, quantity)` (no payment).
- **Revoke**: Admin can `revoke(user, passId)` (sets expiration to `now`).
- **Withdraw**: Admin can `withdraw(to, amount)`.

> 🔒 **Security**: Purchases are `nonReentrant`. Owner-only admin actions. Funds withdraw via `call`.

---

## 🚀 Quick Start (Remix)

1. Open [Remix IDE](https://remix.ethereum.org/).
2. Create `TimeLimitedAccessPass.sol`, paste the contract code.
3. Compile with **Solidity 0.8.20+**.
4. Deploy.
5. In the deployed contract:
   - `createPassType("Day Pass", 0.01 ether, 1 days, 0, true, true)`
   - `buy(passId=1, quantity=1)` with **Value = 0.01 ether**
   - Call `hasAccess(yourAddress, 1)` → `true`
   - Call `timeRemaining(yourAddress, 1)` → seconds left

---
