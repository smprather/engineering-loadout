-- Pull in the wezterm API
local wezterm = require 'wezterm'
-- This will hold the configuration.
local config = wezterm.config_builder()

-- or, changing the font size and color scheme.
config.font_size = 16
--config.color_scheme = 'AdventureTime'

-- local font_family = 'Maple Mono NF'
-- local font_family = 'JetBrainsMono Nerd Font'
-- local font_family = 'CartographCF Nerd Font'
-- local font_family = "Hack Nerd Font Mono"
-- local font_family = "Myna"

config.font_size = 11
config.font = wezterm.font_with_fallback({
    --{ family = "Myna",                weight = 'Medium', },
    { family = "Iosevka Nerd Font Mono",             weight = 'Medium', },
    --{ family = "Iosevka Term",        weight = 'Medium', },
    { family = "Hack Nerd Font Mono", weight = 'Medium', } })
config.line_height = 0.9
--ref: https://wezfurlong.org/wezterm/config/lua/config/freetype_pcf_long_family_names.html#why-doesnt-wezterm-use-the-distro-freetype-or-match-its-configuration
--config.freetype_load_target = 'Normal', ---@type 'Normal'|'Light'|'Mono'|'HorizontalLcd'
--config.freetype_render_target = 'Normal', ---@type 'Normal'|'Light'|'Mono'|'HorizontalLcd'

config.exit_behavior = "Close"

config.swallow_mouse_click_on_window_focus = true
config.adjust_window_size_when_changing_font_size = false
config.hide_tab_bar_if_only_one_tab = true
config.window_close_confirmation = 'NeverPrompt'
config.bypass_mouse_reporting_modifiers = 'ALT'
local act = wezterm.action
config.keys = {
    {
        key = 'Enter',
        mods = 'ALT',
        action = act.DisableDefaultAssignment,
    },
    {
        key = 'LeftArrow',
        mods = 'CTRL|SHIFT',
        action = act.DisableDefaultAssignment,
    },
    {
        key = 'RightArrow',
        mods = 'CTRL|SHIFT',
        action = act.DisableDefaultAssignment,
    },
}

-- mouse_reporting - an optional boolean that defaults to false. This mouse binding entry
-- will only be considered if the current pane's mouse reporting state matches. In general,
-- you should avoid defining assignments that have mouse_reporting=true as it will prevent
-- the application running in the pane from receiving that mouse event. You can, of course,
-- define these and still send your mouse event to the pane by holding down the configured
-- mouse reporting bypass modifier key.
config.mouse_bindings = {
    {
        event = { Down = { streak = 1, button = 'Left' } },
        mods = 'SHIFT',
        --action = act.SelectTextAtMouseCursor("Block"),
        action = act.Nop,
    },
    {
        event = { Up = { streak = 1, button = 'Left' } },
        mods = 'SHIFT',
        --action = act.SelectTextAtMouseCursor("Block"),
        action = act.Nop,
    },
    {
        event = { Down = { streak = 1, button = 'Right' } },
        mods = 'NONE',
        action = act.PasteFrom("Clipboard"),
    },




    {
        event = { Down = { streak = 1, button = 'Left' } },
        mods = 'SHIFT',
        action = act.SelectTextAtMouseCursor("Block"),
        mouse_reporting = true,
    },
    {
        event = { Up = { streak = 1, button = 'Left' } },
        mods = 'SHIFT',
        --action = act.CompleteSelection("ClipboardAndPrimarySelection"),
        action = act.CompleteSelection("Clipboard"),
        mouse_reporting = true,
    },
    {
       event = { Down = { streak = 2, button = 'Left' } },
       mods = 'SHIFT',
       action = act.SelectTextAtMouseCursor("Block"),
       mouse_reporting=true,
    },
    {
        event = { Down = { streak = 1, button = 'Right' } },
        mods = 'SHIFT',
        action = act.PasteFrom("Clipboard"),
        mouse_reporting = true,
    },
    {
        event = { Down = { streak = 1, button = 'Middle' } },
        mods = 'SHIFT',
        action = act.PasteFrom("Clipboard"),
        mouse_reporting = true,
    },
    {
        event = { Drag = { streak = 1, button = 'Left' } },
        mods = 'SHIFT',
        action = act.ExtendSelectionToMouseCursor("Cell"),
        mouse_reporting = true,
    },
    {
        event = { Down = { streak = 1, button = 'Left' } },
        mods = 'SHIFT',
        action = act.SelectTextAtMouseCursor("Block"),
        mouse_reporting = true,
    },

}

return config
