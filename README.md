# Bit (BIT)

Bit is a fixed-supply ERC-20 implemented in `src/Bit.sol` using the vendored
OpenZeppelin Contracts v5.1.0 ERC-20 implementation.

| Property | Value |
| --- | --- |
| Solidity contract | `Bit` |
| Name / symbol | `Bit` / `BIT` |
| Decimals | 18 |
| Total supply | 100,000,000 BIT |
| Total supply in base units | `100000000000000000000000000` |
| Constructor arguments | None (`[]`) |
| Constructor payment | 0 ETH |
| Initial recipient | Immediate deployer (`msg.sender`) |
| Target chain | Ethereum, chain ID 1 |

The constructor mints the entire supply once and emits the standard `Transfer`
event from the zero address. In the IdentityMD launch the factory is the immediate
deployer and receives all tokens. There are no constructor calls to outside
contracts, initialization calls, linked libraries, application contracts, or
external service settings.

## Behavior and assumptions

The brief specifies a plain token, so transfers have no fees, burns, rebases,
restrictions, or callbacks. There is no owner, privileged role, additional mint,
public burn, pause, blacklist, seizure, or upgrade function. The supply stays
fixed for the lifetime of this deployment. Sending tokens to an inaccessible
nonzero address does not reduce `totalSupply`.

`transfer`, `approve`, and `transferFrom` return `true` on success and revert with
OpenZeppelin's ERC-6093 custom errors on failure. Zero-value transfers are valid
and emit `Transfer`; self-transfers preserve balances. Transfers to the zero
address and approvals to the zero spender revert. Delegated transfers require
allowance, even when the caller is also the holder or original deployer. A
finite allowance decreases as it is spent; `type(uint256).max` is an unlimited
allowance and is not decremented. `approve` replaces the allowance and emits
`Approval`; OpenZeppelin v5 does not emit `Approval` when spending allowance.

## Build and test

Foundry and Solidity 0.8.26 must be installed. All Solidity dependencies are
vendored under `lib/`, with licenses and release digests in `lib/PROVENANCE.md`.
No package installation, network connection, environment configuration, FFI,
filesystem cheatcode permission, or fork is needed to build or test once the
pinned compiler is available.

```sh
forge build
FOUNDRY_FUZZ_SEED=0xdcc915b64b7105090e8e142ba36a3c8e74172b04244af4f6cb3c8ac0936f9979 forge test
forge fmt --check
```

`foundry.toml` pins Solidity 0.8.26, Cancun EVM, optimizer with 200 runs, and
`bytecode_hash = "none"`. These are deployment build parameters. The deployable
artifact is `out/Bit.sol/Bit.json`; constructor arguments append no bytes.

Tests cover metadata, constructor allocation and events, CREATE2 factory
deployment, transfers, approval replacement/revocation, infinite allowances,
failed-operation atomicity, zero addresses, zero amounts, self-transfers,
unsupported admin calls, and native-currency rejection. Fuzz tests exercise
transfer conservation, delegated spending, overdraw, and insufficient allowance.
A stateful invariant executes mixed transfer/approval/delegated-transfer
sequences among four holders and checks exact deltas, allowance consumption,
and conservation of the full supply (128 runs, 64 calls each).

The launch-flow unit test models the factory's 10% distributor, 80% pool, and
10% remainder transfers, followed by claims and token movements in both trading
directions. It does not instantiate Uniswap or replace the independent launch
harness. The supplied protected checks depend on launch infrastructure and
manifest values supplied later by the network; they are not standalone tests
in this project.

## Deployment and operational responsibilities

The network's deployer builds `Bit`, creates its manifest after acceptance, and
deploys the creation bytecode through the launch factory. This project does not
send transactions or include a launch manifest. The factory, rather than this
token, distributes supply and initializes liquidity according to the launch's
economics. The token requires no special exemptions for factory, distributor,
pool, or trader transfers: each transfer delivers exactly the requested amount.

After launch, the deployer is responsible for verifying published source and
runtime bytecode against the pinned build, checking name/symbol/decimals/supply,
and confirming factory distributions and liquidity operations. No owner
handover, configuration setters, maintenance calls, or keeper is required.

Holders are responsible for recipient addresses and spending approvals. Prefer
bounded allowances; revoke existing allowance and confirm that transaction
before granting a replacement to reduce the standard ERC-20 approval race.
Unlimited approval grants the spender continuing access to the holder's tokens.
There is no recovery function for tokens mistakenly sent to this contract or
other inaccessible addresses. Ordinary ETH transfers revert; forced ETH cannot
be recovered. No administrator can correct transfers or change deployed logic.

The local review applies the supplied security reference to access control,
accounting, allowance checks, and external interactions. The token makes no
external calls and uses no oracle, signature, proxy, or reentrancy callback.
Foundry testing is not an independent security audit. Independent adversarial
review and launch integration checks remain the network's pre-release steps;
Slither and Mythril are not run as part of this deliverable.
