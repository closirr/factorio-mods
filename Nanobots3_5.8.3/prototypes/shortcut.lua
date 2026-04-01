-- prototypes/shortcut.lua
-- v5.2: Shortcut for toggling radius visualization

data:extend({
    {
        type = "shortcut",
        name = "nanobots-toggle-radius",
        order = "a[nanobots]-b[toggle-radius]",
        action = "lua",
        toggleable = true,
        icon = "__Nanobots3__/graphics/icons/nano-gun.png",
        icon_size = 64,
        small_icon = "__Nanobots3__/graphics/icons/nano-gun.png",
        small_icon_size = 64
    }
})
