data:extend{
{
    type = "bool-setting",
    name = "nanobots-nanobots-auto",
    setting_type = "runtime-global",
    default_value = true,
    order = "nanobots-aa[auto-bots-roll-out]"
},
{
    type = "bool-setting",
    name = "nanobots-active-emitter-mode",
    setting_type = "runtime-per-user",
    default_value = true,
    order = "nanobots-aa[mode]"
},
{
    type = "bool-setting",
    name = "nanobots-equipment-auto",
    setting_type = "runtime-global",
    default_value = true,
    order = "nanobots-ab[poll-rate]"
},
{
    type = "bool-setting",
    name = "nanobots-nano-build-tiles",
    setting_type = "runtime-global",
    default_value = true,
    order = "nanobots-ba[build-tiles]"
},
{
    type = "bool-setting",
    name = "nanobots-nano-fullfill-requests",
    setting_type = "runtime-global",
    default_value = true,
    order = "nanobots-bb"
},
{
    type = "bool-setting",
    name = "nanobots-network-limits",
    setting_type = "runtime-global",
    default_value = true,
    order = "nanobots-ca[check-networks]"
},
{
    name = "nanobots-afk-time",
    type = "int-setting",
    setting_type = "runtime-global",
    default_value = 4,
    maximum_value = 6060,
    minimum_value = 0,
    order = "nanobots-da",
},
{
    type = "int-setting",
    name = "nanobots-nano-poll-rate",
    setting_type = "runtime-global",
    default_value = 60,
    maximum_value = 6060,
    minimum_value = 1,
    order = "nanobots-ea[nano-poll-rate]"
},
{
    type = "int-setting",
    name = "nanobots-nano-queue-per-cycle",
    setting_type = "runtime-global",
    default_value = 100,
    maximum_value = 800,
    minimum_value = 1,
    order = "nanobots-eb[nano-queue-rate]"
},
{
    type = "int-setting",
    name = "nanobots-nano-queue-rate",
    setting_type = "runtime-global",
    default_value = 12,
    maximum_value = 6060,
    minimum_value = 4,
    order = "nanobots-ec[nano-queue-rate]"
},
{
    type = "int-setting",
    name = "nanobots-cell-queue-rate",
    setting_type = "runtime-global",
    default_value = 5,
    maximum_value = 6060,
    minimum_value = 1,
    order = "nanobots-fa[cell-queue-rate]"
},
{
    type = "int-setting",
    name = "nanobots-free-bots-per",
    setting_type = "runtime-global",
    default_value = 50,
    maximum_value = 100,
    minimum_value = 0,
    order = "nanobots-fb[free-bots-per]"
},
{
    type = "string-setting",
    name = "nanobots-log-level",
    setting_type = "runtime-global",
    default_value = "off",
    allowed_values = {"off", "standard", "debug"},
    order = "nanobots-za[log-level]"
},
{
    type = "bool-setting",
    name = "nanobots-nano-repair",
    setting_type = "runtime-global",
    default_value = true,
    order = "a[nanobots]-r[repair]"
},

-- ──────────────────────────────────────────────────────────────────────────
-- 4.7.0: Repair improvements settings
-- ──────────────────────────────────────────────────────────────────────────

{
    type = "string-setting",
    name = "nanobots-repair-start-threshold",
    setting_type = "runtime-global",
    default_value = "1.00",
    allowed_values = {"1.00","0.95","0.90","0.85","0.80","0.75","0.70","0.65","0.60","0.55","0.50"},
    order = "a[nanobots]-r[repair]-a[threshold]"
},
{
    type = "int-setting",
    name = "nanobots-repair-max-sessions",
    setting_type = "runtime-global",
    default_value = 15,
    minimum_value = 1,
    maximum_value = 200,
    order = "a[nanobots]-r[repair]-b[max-sessions]"
},
{
    type = "int-setting",
    name = "nanobots-repair-hp-per-action",
    setting_type = "runtime-global",
    default_value = 20,
    minimum_value = 1,
    maximum_value = 300,
    order = "a[nanobots]-r[repair]-c[hp-per-action]"
},
{
    type = "int-setting",
    name = "nanobots-repair-requeue-delay",
    setting_type = "runtime-global",
    default_value = 20,
    minimum_value = 1,
    maximum_value = 180,
    order = "a[nanobots]-r[repair]-d[requeue-delay]"
},
{
    type = "int-setting",
    name = "nanobots-repair-throttle-ticks",
    setting_type = "runtime-global",
    default_value = 60,
    minimum_value = 0,
    maximum_value = 3600,
    order = "a[nanobots]-r[repair]-e[throttle]"
},
{
    type = "bool-setting",
    name = "nanobots-repair-combat-important-only",
    setting_type = "runtime-global",
    default_value = true,
    order = "a[nanobots]-r[repair]-f[combat-important-only]"
},
{
    type = "int-setting",
    name = "nanobots-repair-combat-enemy-radius",
    setting_type = "runtime-global",
    default_value = 32,
    minimum_value = 0,
    maximum_value = 256,
    order = "a[nanobots]-r[repair]-g[combat-enemy-radius]"
},
{
    type = "int-setting",
    name = "nanobots-repair-combat-recent-damage-seconds",
    setting_type = "runtime-global",
    default_value = 10,
    minimum_value = 0,
    maximum_value = 600,
    order = "a[nanobots]-r[repair]-h[combat-recent-damage]"
},

-- Категории ремонта (галочки)
{
    type = "bool-setting",
    name = "nanobots-repair-cat-defense",
    setting_type = "runtime-global",
    default_value = true,
    order = "a[nanobots]-r[repair]-i[cat]-a[defense]"
},
{
    type = "bool-setting",
    name = "nanobots-repair-cat-transport",
    setting_type = "runtime-global",
    default_value = true,
    order = "a[nanobots]-r[repair]-i[cat]-b[transport]"
},
{
    type = "bool-setting",
    name = "nanobots-repair-cat-power",
    setting_type = "runtime-global",
    default_value = true,
    order = "a[nanobots]-r[repair]-i[cat]-c[power]"
},
{
    type = "bool-setting",
    name = "nanobots-repair-cat-production",
    setting_type = "runtime-global",
    default_value = true,
    order = "a[nanobots]-r[repair]-i[cat]-d[production]"
},
{
    type = "bool-setting",
    name = "nanobots-repair-cat-other",
    setting_type = "runtime-global",
    default_value = false,
    order = "a[nanobots]-r[repair]-i[cat]-e[other]"
},

-- ═══════════════════════════════════════════════════════════════════════════
-- AUTO-DEFENSE SYSTEM (v5.5.0 - Simplified)
-- ═══════════════════════════════════════════════════════════════════════════
{
    type = "string-setting",
    name = "nanobots-auto-defense-threshold",
    setting_type = "runtime-per-user",
    default_value = "5",
    allowed_values = {"1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "25%", "50%", "75%", "100%"},
    order = "nanobots-defense-ba[threshold]"
},

{
    type = "string-setting",
    name = "nanobots-auto-defense-delivery",
    setting_type = "runtime-per-user",
    default_value = "50%",
    allowed_values = {"1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "25%", "50%", "75%", "100%"},
    order = "nanobots-defense-bb[delivery]"
},

{
    type = "string-setting",
    name = "nanobots-auto-defense-artillery-threshold",
    setting_type = "runtime-per-user",
    default_value = "1",
    allowed_values = {"1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "25%", "50%", "75%", "100%"},
    order = "nanobots-defense-ca[artillery-threshold]"
},

{
    type = "string-setting",
    name = "nanobots-auto-defense-artillery-delivery",
    setting_type = "runtime-per-user",
    default_value = "5",
    allowed_values = {"1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "25%", "50%", "75%", "100%"},
    order = "nanobots-defense-cb[artillery-delivery]"
},

{
    type = "bool-setting",
    name = "nanobots-auto-defense-gun-turrets",
    setting_type = "runtime-per-user",
    default_value = true,
    order = "nanobots-defense-da[gun-turrets]"
},

{
    type = "bool-setting",
    name = "nanobots-auto-defense-artillery-turrets",
    setting_type = "runtime-per-user",
    default_value = true,
    order = "nanobots-defense-dd[artillery-turrets]"
},

{
    type = "bool-setting",
    name = "nanobots-auto-defense-modded-turrets",
    setting_type = "runtime-per-user",
    default_value = true,
    order = "nanobots-defense-de[modded-turrets]"
},

-- Ammo Priority Settings
{
    type = "string-setting",
    name = "nanobots-auto-defense-ammo-type-priority",
    setting_type = "runtime-per-user",
    default_value = "best-damage",
    allowed_values = {"best-damage", "worst-damage"},
    order = "nanobots-defense-ea[ammo-type-priority]"
},

{
    type = "string-setting",
    name = "nanobots-auto-defense-ammo-quality-priority",
    setting_type = "runtime-per-user",
    default_value = "best-quality",
    allowed_values = {"best-quality", "worst-quality"},
    order = "nanobots-defense-eb[ammo-quality-priority]"
},

-- Warning Settings
{
    type = "int-setting",
    name = "nanobots-auto-defense-warning-interval",
    setting_type = "runtime-per-user",
    default_value = 300,
    minimum_value = 30,
    maximum_value = 300,
    order = "nanobots-defense-ec[warning-interval]"
},

-- v5.7.0: Auto-enable delivery system when enemies detected
{
    type = "bool-setting",
    name = "nanobots-auto-defense-auto-enable-combat",
    setting_type = "runtime-per-user",
    default_value = false,
    order = "nanobots-defense-f0[auto-enable-combat]"
},

-- v5.7.0: Combat Mode (auto-switch ammo priority)
{
    type = "bool-setting",
    name = "nanobots-auto-defense-combat-mode",
    setting_type = "runtime-per-user",
    default_value = false,
    order = "nanobots-defense-fa[combat-mode]"
},

-- v5.7.0: Adaptive Scan Interval
{
    type = "bool-setting",
    name = "nanobots-auto-defense-adaptive-scan",
    setting_type = "runtime-per-user",
    default_value = true,
    order = "nanobots-defense-fb[adaptive-scan]"
},

-- v5.7.0: Delivery Projectile Visual
{
    type = "bool-setting",
    name = "nanobots-auto-defense-show-projectile",
    setting_type = "runtime-per-user",
    default_value = true,
    order = "nanobots-defense-fc[show-projectile]"
},

-- v5.7.0: Low Nano Ammo Warning
{
    type = "int-setting",
    name = "nanobots-auto-defense-low-nano-threshold",
    setting_type = "runtime-per-user",
    default_value = 10,
    minimum_value = 0,
    maximum_value = 50,
    order = "nanobots-defense-fd[low-nano-threshold]"
},

-- v5.7.0: Warning interval (how often to show low ammo warning)
{
    type = "string-setting",
    name = "nanobots-low-nano-warning-interval",
    setting_type = "runtime-per-user",
    default_value = "30",
    allowed_values = {"30", "60", "90", "120", "150", "180", "210", "240", "270", "300"},
    order = "nanobots-defense-fe[warning-interval]"
},

-- v5.8.0: Wrong ammo type warning interval
{
    type = "string-setting",
    name = "nanobots-wrong-ammo-warning-interval",
    setting_type = "runtime-per-user",
    default_value = "30",
    allowed_values = {"10", "30", "60", "120", "300", "0"},
    order = "nanobots-defense-ff[wrong-ammo-interval]"
},

-- Global Settings
{
    type = "int-setting",
    name = "nanobots-auto-defense-scan-interval",
    setting_type = "runtime-global",
    default_value = 60,
    minimum_value = 15,
    maximum_value = 300,
    order = "nanobots-defense-ia[scan-interval]"
},

{
    type = "int-setting",
    name = "nanobots-auto-defense-max-per-tick",
    setting_type = "runtime-global",
    default_value = 5,
    minimum_value = 1,
    maximum_value = 20,
    order = "nanobots-defense-ib[max-per-tick]"
},

-- Debug Settings - separate controls for each system
{
    type = "bool-setting",
    name = "nanobots-debug-repair-system",
    setting_type = "runtime-global",
    default_value = true,
    order = "nanobots-zb[debug-repair]"
},

{
    type = "bool-setting",
    name = "nanobots-debug-defense-system",
    setting_type = "runtime-global",
    default_value = true,
    order = "nanobots-zc[debug-defense]"
}
}
