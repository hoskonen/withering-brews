# Withering Brews — Patch 2 Handover

## Project

Withering Brews is a Lua mod for Kingdom Come: Deliverance II that gives potions hidden age/condition.

The intended mechanic is:

- Potions internally age from fresh toward degraded.
- The game has separate potion items for qualities I–IV.
- Lua cannot directly scale potion effects.
- When a potion crosses a degradation threshold, the mod will remove the existing item and add the next-lower quality item.
- Quality I is terminal in the initial release and does not degrade further.
- Potion condition is deliberately hidden from the player.

Repository:

`github.com/hoskonen/withering-brews`

## Environment

- Kingdom Come: Deliverance II
- KCDUtils 0.4.17
- LuaDB through the KCDUtils DB wrapper
- Mod registration name: `witheringbrews`
- Current version string: `0.0.1-dev`
- Current mode: `DryRun=true`
- Current tracking mode: `whitelist`

The user manually edits, packs and tests the mod. Provide changes file by file with exact insertion or replacement locations.

## Important workflow rule

Every lifecycle or persistence feature must be tested through both:

1. Full game quit, restart and save load.
2. Loading another save while the game process remains running.

These paths have caused different bugs in previous KCD2 mod projects.

## Main files

- `Data/Scripts/Systems/witheringbrews_init.lua`
- `Data/Scripts/WitheringBrews/Config.lua`
- `Data/Scripts/WitheringBrews/Potions.lua`
- `Data/Scripts/WitheringBrews/Debug.lua`
- `Data/Scripts/WitheringBrews/Util.lua`
- `Data/Scripts/WitheringBrews/Clock.lua`
- `Data/Scripts/WitheringBrews/Core.lua`
- `Data/Scripts/WitheringBrews/Cohorts.lua`
- `Data/Scripts/WitheringBrews/Events.lua`
- `Data/Scripts/WitheringBrews/Commands.lua`
- `Data/Scripts/WitheringBrews/Dev.lua`

The initializer is the sole owner of loading these modules. `Events.lua` and `Cohorts.lua` must not reload `Core.lua`.

## Potion data

- 16 potion families
- 58 potion template UUIDs
- Quality order in each family: I, II, III, IV
- Bands: `water`, `wine`, `oil`, `spirit`
- Known one-tier families:
  - `fevertonic`
  - `lethean_water`

Current validation result:

- families: 16
- ids: 58
- reverse index: 58
- whitelist: 58
- errors: 0
- warnings: 2

The two warnings are the known one-tier families.

## Patch 1 completed

Patch 1 established the lifecycle, tracking and timing foundations.

### Centralized potion policy

`WB.GetTrackedPotion(classId)` is now the authoritative check for whether an item is currently tracked.

It supports:

- `families`
- `whitelist`
- fail-closed behavior for invalid tracking modes

Used by:

- bootstrap
- ItemTransfer acquisition detection
- inventory potion scanning
- utility potion checks

`BuildPotionIndex()` still indexes all configured potion metadata and deliberately does not apply the whitelist.

### Game-world clock

Added `Clock.lua`.

`WB.Clock.Now()` uses:

1. `KCDUtils.Calendar.GetWorldTime`
2. `Calendar.GetWorldTime`

There is intentionally no `os.time()` gameplay fallback.

Runtime example:

- raw world time: `388806`
- formatted: day 4, 12:00:06

Gameplay cohort timestamps now use world time.

`os.time()` remains only in temporary diagnostics such as the DB smoke test.

### Cohort time safety

`CohortsAdd()` refuses to write when world time is unavailable.

Console helpers:

```lua
# WB_CohAdd("TEST_ID", 2, 1)
# WB_CohList("TEST_ID")
# WB_CohClear("TEST_ID")