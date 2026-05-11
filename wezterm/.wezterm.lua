-- WezTerm Configuration — Catppuccin Mocha + JetBrains Mono
-- Part of linuxploitacious — github.com/Exploitacious/linuxploitacious
local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- Color scheme (matches Oh My Posh catppuccin_mocha theme)
config.color_scheme = 'Catppuccin Mocha'

-- Font — JetBrains Mono Nerd Font with ligatures
config.font = wezterm.font_with_fallback {
  { family = 'JetBrainsMono NF', harfbuzz_features = { 'calt=1', 'clig=1', 'liga=1' } },
  { family = 'JetBrains Mono', harfbuzz_features = { 'calt=1', 'clig=1', 'liga=1' } },
  'Cascadia Code',
}
config.font_size = 11.5

-- Window appearance — acrylic transparency on Win11
config.window_background_opacity = 0.88
config.win32_system_backdrop = 'Acrylic'
config.window_decorations = 'INTEGRATED_BUTTONS|RESIZE'
config.window_padding = { left = 8, right = 8, top = 8, bottom = 8 }
config.initial_cols = 140
config.initial_rows = 38

-- Tab bar — hidden with one tab, fancy with multiple
config.hide_tab_bar_if_only_one_tab = true
config.use_fancy_tab_bar = true
config.tab_bar_at_bottom = false
config.tab_max_width = 28

-- Tab bar colors (Catppuccin Mocha surface tones)
config.colors = {
  tab_bar = {
    background = '#1e1e2e',
    active_tab = {
      bg_color = '#313244',
      fg_color = '#cdd6f4',
    },
    inactive_tab = {
      bg_color = '#1e1e2e',
      fg_color = '#6c7086',
    },
    inactive_tab_hover = {
      bg_color = '#313244',
      fg_color = '#cdd6f4',
    },
    new_tab = {
      bg_color = '#1e1e2e',
      fg_color = '#6c7086',
    },
    new_tab_hover = {
      bg_color = '#313244',
      fg_color = '#cdd6f4',
    },
  },
}

-- Disable audible bell
config.audible_bell = 'Disabled'

-- Scrollback
config.scrollback_lines = 10000

-- GPU rendering
config.front_end = 'WebGpu'

-- Default shell — PowerShell 7 if available, fallback to Windows PowerShell
config.default_prog = (function()
  -- Check common PS7 install paths
  local ps7_paths = {
    'C:/Program Files/PowerShell/7/pwsh.exe',
    'C:/Program Files (x86)/PowerShell/7/pwsh.exe',
  }
  for _, path in ipairs(ps7_paths) do
    local f = io.open(path, 'r')
    if f then
      f:close()
      return { path, '-NoLogo' }
    end
  end
  return { 'powershell.exe', '-NoLogo' }
end)()

-- Keybinds — pane management (Windows Terminal style)
config.keys = {
  -- Pane splits
  { key = '-', mods = 'ALT|SHIFT', action = wezterm.action.SplitVertical { domain = 'CurrentPaneDomain' } },
  { key = '=', mods = 'ALT|SHIFT', action = wezterm.action.SplitHorizontal { domain = 'CurrentPaneDomain' } },
  { key = 'w', mods = 'CTRL|SHIFT', action = wezterm.action.CloseCurrentPane { confirm = true } },

  -- Pane navigation
  { key = 'LeftArrow',  mods = 'ALT', action = wezterm.action.ActivatePaneDirection 'Left' },
  { key = 'RightArrow', mods = 'ALT', action = wezterm.action.ActivatePaneDirection 'Right' },
  { key = 'UpArrow',    mods = 'ALT', action = wezterm.action.ActivatePaneDirection 'Up' },
  { key = 'DownArrow',  mods = 'ALT', action = wezterm.action.ActivatePaneDirection 'Down' },

  -- Quick tab switching (Ctrl+number)
  { key = '1', mods = 'ALT', action = wezterm.action.ActivateTab(0) },
  { key = '2', mods = 'ALT', action = wezterm.action.ActivateTab(1) },
  { key = '3', mods = 'ALT', action = wezterm.action.ActivateTab(2) },
  { key = '4', mods = 'ALT', action = wezterm.action.ActivateTab(3) },
  { key = '5', mods = 'ALT', action = wezterm.action.ActivateTab(4) },
}

-- Mouse binds — right-click paste (Windows Terminal behavior)
config.mouse_bindings = {
  {
    event = { Down = { streak = 1, button = 'Right' } },
    mods = 'NONE',
    action = wezterm.action.PasteFrom 'Clipboard',
  },
}

return config
