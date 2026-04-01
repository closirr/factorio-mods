local data_util = {}

data_util.mod_prefix = "aai-" -- update strings.cfg

function data_util.technology_icon_constant_equipment(technology_icon, icon_size)
  local scale = 128 / icon_size
  local icons =
  {
    {
      icon = technology_icon,
      icon_size = icon_size, icon_mipmaps = 4
    },
    {
      icon = "__core__/graphics/icons/technology/constants/constant-equipment.png",
      icon_size = 128,
      scale = scale,
      icon_mipmaps = 3,
      shift = {100 * scale, 100 * scale},
      floating = true,
    }
  }
  return icons
end

return data_util
