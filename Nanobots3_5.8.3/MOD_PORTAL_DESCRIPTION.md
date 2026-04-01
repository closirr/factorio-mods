# Mod Portal Description for Nanobots: Early Bots 3.0

---

## SHORT DESCRIPTION (for mod portal summary)

Personal nanobots for construction, repair, and turret ammo delivery - no roboports needed! Features quality support, combat automation, statistics GUI, and megabase optimization. Fully compatible with Factorio 2.0 and Space Age.

---

## LONG DESCRIPTION (for mod portal page)

# Nanobots: Early Bots 3.0

**Personal construction nanobots that work without roboport networks!**

Build, repair, and defend your factory using portable nanobots that follow you everywhere. No logistics network required - just equip and go!

---

## Key Features

### Construction and Repair
- Build ghosts and structures automatically
- Auto-repair damaged entities
- Tile placement automation
- Full Factorio 2.0 quality support

### Vehicle Automation
- Auto-refuel vehicles
- Automatic ammo management
- Module installation

### Auto-Defense System
- Automatic turret ammo delivery - turrets never run out
- Quality-aware prioritization (legendary/epic first OR save good ammo)
- Separate settings for gun turrets vs artillery
- Visual feedback with colored flying text
- Ammo-specific sounds (small/large/artillery)
- Wrong ammo warnings when incompatible ammo is loaded

### Smart Automation
- **Combat Priority Mode** - best ammo in combat, economy mode in peace
- **Auto-Enable on Combat** - system turns on/off based on enemy presence
- **Statistics GUI (Alt+H)** - session and lifetime stats with ammo breakdown
- **Adaptive Scanning** - faster in combat, slower in peacetime (saves UPS)
- **Low/Empty charge warnings** - configurable audio and visual alerts

---

## Quick Start

1. Research and craft **Nano Emitter**
2. Craft **Nano Construction Bots** (or other nano ammo)
3. Equip emitter in gun slot, ammo in ammo slot
4. Press **Alt+N** to see your working area
5. Press **Alt+G** to enable auto-defense

### Hotkeys
- Alt+N - Toggle area visualization (green square)
- Alt+G - Toggle auto-defense
- Alt+H - Toggle statistics GUI

---

## Settings

### Per-Player Settings
- Turret refill thresholds (1-10 rounds or 25%/50%/75%/100%)
- Delivery amount per refill
- Ammo type priority (best/worst damage first)
- Ammo quality priority (legendary first or save good ammo)
- Combat Priority Mode and Auto-Enable toggles
- Warning thresholds and intervals (10s / 30s / 1m / 2m / 5m / off)

### Global Settings
- Scan interval (performance tuning)
- Max turrets per scan
- Disable nanobots in logistic networks
- Debug logging options

---

## Performance (v5.8.0)

Megabase-optimized:
- Unified on_tick handler (3 to 1, ~30% less overhead)
- Removed log() I/O from hot loops
- Type-filtered entity search (up to 90% faster)
- Settings caching with 5-second TTL
- O(1) lookup tables for repair priority and damage tiers
- Adaptive scanning and smart multiplayer distribution

---

## Compatibility

- Factorio 2.0+
- Space Age DLC
- Space Exploration (remote view compatible since v5.8.2)
- Quality system
- Multiplayer
- Most turret mods
- Localization: EN / RU

---

## FAQ

Many common questions and answers are available on the [FAQ page](https://mods.factorio.com/mod/Nanobots3/faq).

---

## Credits

Original mod by **Nexela**. Updated for Factorio 2.0 with new features.

---

## TAGS (for mod portal)

construction, bots, nanobots, personal bots, turrets, ammo, auto-defense, quality, Space Age, 2.0

---

## THUMBNAIL TEXT SUGGESTION

NANOBOTS 3.0 / Personal Bots / Auto-Defense / Quality Support / v5.8.3
