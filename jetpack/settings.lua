data:extend{
  {
    type = "int-setting",
    name = "jetpack-speed-reduces-shields",
    setting_type = "runtime-global",
    minimum_value = 0,
    default_value = 50,
    maximum_value = 100,
  },
  {
    type = "int-setting",
    name = "jetpack-fuel-consumption",
    setting_type = "runtime-global",
    minimum_value = 1,
    default_value = 100,
    maximum_value = 10000
  },
  {
    type = "bool-setting",
    name = "jetpack-fall-on-damage",
    setting_type = "runtime-global",
    default_value = true,
  },
  {
    type = "bool-setting",
    name = "jetpack-thrust-stacks",
    setting_type = "runtime-global",
    default_value = true,
  },
  {
    type = "bool-setting",
    name = "jetpack-print-thrust",
    setting_type = "runtime-per-user",
    default_value = true,
  },
  {
    type = "int-setting",
    name = "jetpack-volume",
    setting_type = "startup",
    minimum_value = 0,
    default_value = 30,
    maximum_value = 100,
  },
}
