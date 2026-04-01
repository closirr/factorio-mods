# Nanobots: Early Bots 3.0 - FAQ

---

## Auto-Defense

**Q: Turrets not refilling automatically?**

Check in order:
1. Press **Alt+G** - system must be ENABLED (or enable "Auto-Enable on Combat")
2. Press **Alt+N** - turrets must be within the green square
3. You must have compatible ammunition in your inventory
4. Laser turrets don't use ammo
5. Settings - Per Player - verify turret type is enabled

**Q: I just placed a turret and it stays empty?**

The system fills empty turrets automatically - the default threshold is 5, meaning any turret with fewer than 5 rounds (including 0) triggers a refill. If it doesn't fill, check the points above. Also note that the system scans a few turrets per cycle (default 5), so with many turrets placed at once it may take a few seconds to reach all of them.

**Q: System delivers wrong quality ammo?**

Settings - Per Player - Ammo Quality Priority:
- "Best Quality First" = uses legendary/epic first
- "Worst Quality First" = uses normal quality first (saves good ammo)

**Q: Why uranium rounds when I have basic magazines?**

Settings - Per Player - Ammo Type Priority:
- "Best Damage First" = strongest ammo first (uranium - piercing - basic)
- "Worst Damage First" = weakest ammo first (saves expensive ammo)

**Q: What's the difference between Combat Priority Mode and Auto-Enable?**

- **Combat Priority Mode** changes WHICH ammo to use (best in combat, your settings in peace)
- **Auto-Enable on Combat** turns the SYSTEM on/off based on enemy presence

You can use both together, one, or neither.

**Q: Artillery turrets empty but not refilling?**

Artillery has separate settings. Check Settings - Per Player - Artillery: Refill Threshold. Default is 1 (refills when completely empty).

**Q: Too many turrets, game lags?**

Settings - Global:
- Increase "Scan Interval" from 60 to 120+ ticks
- Decrease "Max Per Scan" from 5 to 3 or less
- Enable "Adaptive Scan" to auto-adjust based on combat

---

## Ammo and Warnings

**Q: "Auto-Defense paused: Termites loaded" warning?**

Auto-defense only works with **Nano Constructors**. If termites or other ammo is loaded in the nano-emitter, the system pauses. Switch to constructors to resume.

**Q: "No nano charges! Insert ammo" warning?**

The nano-emitter is equipped but the ammo slot is empty. Load nano constructors or termites.

**Q: Warnings are too frequent / annoying?**

Settings - Per Player:
- Set warning threshold to 0 to disable low charge warnings completely
- Adjust warning interval (10 sec / 30 sec / 1 min / 2 min / 5 min / off)
- Set wrong ammo warning interval to 0 to disable

---

## Nanobots and Roboports

**Q: Nanobots don't work when I have regular robots in inventory?**

This is controlled by "Disable nanobots in logistic networks" setting (Settings - Global):
- **Enabled (default)** - nanobots don't work when regular robots are available
- **Disabled** - nanobots always work regardless of regular robots

If the setting is enabled, you can still use nanobots by:
1. Toggling off your personal roboport (Alt+F or shortcut bar button)
2. Removing robots from inventory
3. Disabling the setting

**Q: I toggled off my personal roboport but nanobots still don't work?**

Make sure you're using the in-game toggle (Alt+F or the button in shortcut bar), not removing the roboport from armor. The system checks whether your personal roboport is toggled on/off.

**Q: What about stationary roboports?**

If you're standing in range of a stationary roboport with construction robots, nanobots won't work (with "Disable in networks" enabled). This is intentional - let the stationary robots do the work.

---

## Remote View and Space Exploration

**Q: Nanobots stop when I use satellite/remote view?**

Fixed in v5.8.2. Nanobots now use your character's physical surface and position. They continue working around your character while you view other locations remotely.

**Q: Visualization square disappears during remote view?**

Fixed in v5.8.2. The square now renders on your character's physical surface and stays in place during remote viewing.

**Q: Does this work on Aquilo / Space platforms / Space Exploration?**

Yes. All planets, platforms, and SE surfaces are supported.

---

## Roboport Interface

**Q: What is the Roboport Interface?**

A special combinator (Logistic Network Interface) that lets you automate tasks using signals: chop trees, pick up items from ground, place tiles, deconstruct empty mining drills, catch fish. Connect it to your roboport network and send signals to trigger actions.

**Q: What is "Reserve robots %" setting?**

This setting is for the Roboport Interface feature only. It controls how many regular construction robots (NOT nanobots) to keep free in your logistic network:
- 0% = interface can use all robots
- 50% = keep half free for normal construction/repair
- 100% = don't use any robots (interface disabled)

This has nothing to do with nano-charges or the nano-emitter.

---

## Visualization

**Q: Why is the working area a square, not a circle?**

The nanobot system searches a square area (for performance). The visualization accurately shows this square zone. Entities in all corners are processed.

**Q: How do I see the working area?**

Press Alt+N. A green square will appear around your character showing the nanobot range.

---

## General

**Q: How is this different from regular roboports?**

Nanobots work anywhere without a logistics network, follow the player, support auto-defense, and require ammo. Roboports are stationary, have larger range, and don't need ammo.

**Q: Does quality affect nanobot range?**

Yes. Higher quality ammo = larger range. Normal is the base range (7-15 tiles depending on ammo type), and each quality tier adds +10% range.

**Q: Is this multiplayer compatible?**

Yes. Each player has an independent nanobot system with individual settings.

**Q: Performance impact?**

Minimal. The mod is megabase-optimized since v5.8.0 with unified on_tick handler, type-filtered entity search (up to 90% faster), settings caching, adaptive scanning, and smart multiplayer distribution.

---

## Changelog

### v5.8.2
- Fixed remote view compatibility: all systems now use character's physical surface/position

### v5.8.1
- Fixed Auto-Defense consuming termite ammo
- Added wrong ammo and empty ammo warnings with configurable interval
- Active Emitter Mode support for Nano Monitor
- Factorio 2.0 API audit: fixed get_upgrade_target/quality, revive(), get_contents(), pcall patterns

### v5.8.0
- 15 performance optimizations
- Fixed ghost building (SafeEntity.revive Factorio 2.0 format)
- Fixed config require error in auto_defense

### v5.7.1
- Fixed nanobots not working when personal roboport toggled OFF

### v5.7.0
- Statistics GUI (Alt+H), Combat Priority Mode, Auto-Enable on Combat
- Adaptive Scan Interval, Low Nano Charge Warnings, Square Area Visualization

---

## Credits

Original mod by **Nexela**. Updated for Factorio 2.0.

## License

MIT License
