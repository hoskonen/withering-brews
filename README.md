# Withering Brews

Withering Brews is a Lua mod for Kingdom Come: Deliverance II that gives potions a hidden age and gradually reduces their quality over time.

Potions do not display a visible freshness meter. When an aging threshold is crossed, the mod replaces the potion with its next-lower vanilla quality version.

## Development status

Withering Brews is currently an experimental development project.

Current version:

```text
0.0.1-dev
```

Current safety defaults:

```text
DryRun=true
Automatic aging disabled
Manual transaction execution only
```

The aging planner and guarded transaction executor are implemented and extensively tested, but aging is not yet connected to automatic gameplay lifecycle events.

Do not treat the current development build as a finished gameplay release.

## Gameplay design

The intended mechanic is:

- Every tracked potion receives a hidden creation timestamp.
- Potions age according to their liquid base:
  - water
  - wine
  - oil
  - spirit
- Aging progresses through the vanilla potion qualities IV, III, II and I.
- Crossing a threshold replaces the potion with its next-lower quality item.
- Excess age carries across multiple quality tiers.
- Quality I is terminal and remains in the inventory in the current design.
- Potion age and condition remain hidden from the player.

The game already defines different item templates and effects for each potion quality. Withering Brews therefore replaces items instead of attempting to modify potion effects directly.

## Requirements

Core requirements:

- Kingdom Come: Deliverance II
- KCDUtils 0.4.17
- LuaDB
- Lua 5.2-compatible runtime

Optional:

- [Mod Configuration Menu](https://www.nexusmods.com/kingdomcomedeliverance2/mods/3363)
- KCSE, as required by Mod Configuration Menu

The current MCM integration is experimental. Its `Enable Mod` toggle proves that menu values can modify Withering Brews Lua configuration, but the toggle is not connected to gameplay behavior yet.

## Current implementation

### Potion data

The current configuration contains:

- 16 potion families
- 58 potion class IDs
- Four aging bands
- Two supported one-tier potion families
- Whitelist-based tracking

Current validation:

```text
Families: 16
Class IDs: 58
Rule boundary tests: 116
Validation failures: 0
```

### Hidden age cohorts

Potions of the same class may have different ages. Withering Brews therefore stores hidden age cohorts containing:

- quantity
- creation timestamp
- source metadata

Cohorts are persisted through LuaDB and restored with the corresponding game save.

The system validates that recorded cohort quantities match the player’s actual inventory before aging is allowed.

### Aging planner

The read-only aging planner supports:

- Exact threshold boundaries
- Multi-tier overflow
- One-tier potion families
- Terminal Quality I behavior
- Timestamp preservation
- Source metadata preservation
- Configured aging rules per liquid band

Planner self-tests currently report:

```text
Passed: 13
Failed: 0
Writes: 0
```

### Guarded aging transaction

Aging execution is separated into two commands:

```text
wb_age_tx_preview
wb_age_tx_apply APPLY
```

Preview constructs the complete transaction without writing anything.

Apply requires both:

- `DryRun=false`
- Explicit `APPLY` confirmation

The executor:

1. Captures world time.
2. Snapshots the complete tracked inventory.
3. Copies all authoritative cohort lists.
4. Rejects invalid or unreconciled state.
5. Rechecks all 58 configured potion IDs.
6. Removes source quantities.
7. Adds target quantities.
8. Verifies the complete inventory.
9. Writes complete expected cohort lists.
10. Reads back and verifies every cohort list.
11. Runs the existing cohort validator.
12. Rebuilds the transaction and requires no remaining affected state.

Inventory removals and additions remain separate even when a potion class has a net quantity change of zero.

### Compensation

Inventory and LuaDB are separate systems, so the transaction cannot be truly atomic.

If execution fails after mutations begin, Withering Brews attempts compensation in this order:

1. Restore modified cohort lists.
2. Restore the complete inventory state.
3. Verify both restored systems.

Controlled failures have been tested after:

- Source removals
- Target additions
- The first cohort write
- All cohort writes

All controlled compensation tests restored the original state successfully.

## Safety model

Withering Brews follows several fail-closed rules:

- Aging never runs against unreconciled quantities.
- Invalid, sparse or future-dated cohort rows block execution.
- Missing world time blocks gameplay timestamps.
- Preview commands perform no writes.
- `DryRun=false` alone is insufficient to apply aging.
- Explicit confirmation is required for transaction writes.
- A post-apply transaction must contain zero affected classes.
- Failed compensation produces a critical error instead of silently continuing.

Patch testing includes both:

1. Full quit, restart and save loading.
2. Loading another save during the same game process.

## Development aging durations

The current durations are deliberately short development values. They exist to make testing practical and are not final gameplay balance.

| Band | Quality IV | Quality III | Quality II | Quality I |
|---|---:|---:|---:|---:|
| Water | 4 days | 3 days | 2 days | 1 day |
| Wine | 8 days | 6 days | 4 days | 2 days |
| Oil | 12 days | 9 days | 6 days | 3 days |
| Spirit | 16 days | 12 days | 8 days | 4 days |

Final durations and difficulty presets will be designed after normal gameplay soak testing.

## Known limitations

### Consumption may not be observed immediately

Withering Brews tracks potion quantities and hidden age cohorts rather than individual engine item identities.

Some forms of consumption may not be observed immediately. This includes Saviour Schnapps consumed as part of manual saving.

If the recorded quantity differs from the player’s inventory, aging stops instead of guessing. The state must be observed and reconciled before degradation can continue.

### Net-zero turnover is ambiguous

Consuming a potion and acquiring another potion of the same class and quality between inventory observations may leave the total quantity unchanged.

With count-only tracking, this turnover cannot be distinguished reliably. The newly acquired potion and consumed potion may have different hidden ages even though the visible quantity remains identical.

This limitation will be evaluated during normal gameplay testing before introducing a more invasive tracking mechanism.

### Automatic aging is not connected

The planner and executor are complete, but no gameplay event currently triggers automatic reconciliation or aging.

Current execution is manual and development-only.

### Saviour Schnapps saving

Manual saving consumes Saviour Schnapps without necessarily producing an immediate inventory observation. This can leave a stale cohort and correctly block aging.

Save & Quit behaves differently, but the game maintains only one ExitSave and may overwrite valuable test fixtures.

### Mod Configuration Menu

The experimental MCM `Enable Mod` toggle changes an in-memory Lua variable, but it does not disable Withering Brews behavior yet.

MCM values are currently session-only and are not persisted by Withering Brews.

## Useful development commands

Read-only diagnostics:

```text
wb_status
wb_validate
wb_time
wb_coh_validate
wb_age_selftest
wb_age_validate_rules
wb_age_preview
wb_age_tx_preview
wb_scan_potions
wb_util_snap
```

Guarded aging execution:

```text
wb_age_tx_apply APPLY
```

Development helpers:

```text
wb_spawn
wb_spawn_testset
wb_bootstrap_preview
wb_bootstrap_apply
wb_bootstrap_reset
```

Lua console functions require the `#` prefix:

```lua
# WB_CohList("<classId>")
```

KCD console commands such as `wb_age_tx_preview` do not use the prefix.

## Project structure

```text
Data/
└── Scripts/
    ├── Systems/
    │   └── witheringbrews_init.lua
    └── WitheringBrews/
        ├── Aging.lua
        ├── AgingExecution.lua
        ├── Clock.lua
        ├── Cohorts.lua
        ├── Commands.lua
        ├── Config.lua
        ├── Core.lua
        ├── Debug.lua
        ├── Dev.lua
        ├── Events.lua
        ├── ModMenu.lua
        ├── Potions.lua
        └── Util.lua
```

The initializer is the sole owner of module loading.

## Development roadmap

### Completed

- Centralized tracked-potion policy
- Strict game-world clock
- Idempotent event binding
- Inventory snapshots
- Cohort persistence
- Read-only cohort validation
- Quantity reconciliation with rollback
- Read-only aging planner
- Aging rule validation
- Guarded aging transaction
- Verified inventory and LuaDB writes
- Compensation and restoration testing
- Cold-restart persistence testing
- In-process save-switch testing
- Experimental Lua MCM integration

### Next

1. Progress to a stable free-roam gameplay save.
2. Perform normal gameplay soak testing.
3. Investigate more immediate consumption synchronization.
4. Test sleeping and time advancement.
5. Add lifecycle orchestration:
   - snapshot
   - reconcile
   - validate
   - plan
   - apply
6. Add re-entrancy protection.
7. Evaluate lightweight lifecycle events without polling.
8. Design final degradation durations.
9. Design difficulty presets and real MCM settings.
10. Perform release hardening and documentation review.

Automatic execution will use a dedicated setting such as:

```text
AutomaticAgingEnabled
```

It will not rely solely on `DryRun`.

## Repository

[github.com/hoskonen/withering-brews](https://github.com/hoskonen/withering-brews)