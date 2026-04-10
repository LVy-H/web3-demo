# Privacy Dimensions Framework

## Overview

This system models privacy as **3 independent axes** rather than a linear tier system.
Each voting module selects a position on each axis. No position is inherently "better" --
they solve different problems with different trade-offs.

## Axes

### 1. Identity: Who voted?

| Position | Description | Example |
|----------|-------------|---------|
| `anonymous` | ZK proof of membership. No address link. Observer cannot determine which group member voted. | Semaphore nullifier-based voting |
| `pseudonymous` | Wallet address visible on-chain, but real-world identity unknown. | Standard DAO voting (Snapshot) |
| `identified` | Address visible and tied to a known identity (e.g., via SBT or KYC). | Corporate governance with identity verification |

### 2. Content: What did they vote?

| Position | Description | Example |
|----------|-------------|---------|
| `public-realtime` | Individual votes visible as they are cast. Anyone can see who voted for what. | Snapshot governance |
| `public-aggregate` | Running tally visible, but individual votes cannot be traced to voters. | Module M1 (ZK anonymous + live tally) |
| `sealed` | All votes hidden until a reveal trigger (time or threshold). | Commit-reveal elections |
| `forever-blind` | Individual votes never revealed. Only aggregate result exists. | FHE-based tallying |

### 3. Temporality: When is information revealed?

| Position | Description | Example |
|----------|-------------|---------|
| `immediate` | Information available as soon as the action occurs. | Live tally updates |
| `threshold` | Revealed when N votes or N% participation reached. | "Results after 50 votes" |
| `time-locked` | Revealed after a deadline. | "Results on Friday at 5pm" |
| `never` | Information is permanently sealed. | Forever-blind vote content |

## Impossible Combinations

Some axis positions conflict:

1. **Anonymous identity + public-realtime content in small groups**: If 5 voters exist and 4 voted "Yes," the 5th is deanonymized by elimination.
2. **Sealed content + immediate temporality**: Contradictory by definition.
3. **Anonymous identity + direct participation proof**: The receipt itself must be a ZK proof ("I'm in the voter set"), not a direct identity claim. This is possible but requires careful construction.

## Module Mapping

| Module | Identity | Content | Temporality |
|--------|----------|---------|-------------|
| M1: Anonymous Token Voting | anonymous | public-aggregate | immediate |
| M2a: Blind Voting (live tally) | identified | public-aggregate | immediate |
| M2b: Blind Voting (sealed) | identified | sealed | threshold / time-locked |
| M3: Participation Receipt | (cross-cutting feature) | -- | on-demand |
