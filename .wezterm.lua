local wezterm = require 'wezterm'
local config = {}
local act = wezterm.action

-- ============================================================================
-- WINDOW SIZE & POSITION PERSISTENCE
-- ============================================================================
local state_file = wezterm.home_dir .. '/.wezterm_window_state.json'
local pending_save_by_window = {}
local last_saved_state_json = nil

-- Function to save window state
local function save_window_state(window)
  local window_dims = window:get_dimensions()

  local state = {
    pixel_width = window_dims.pixel_width,
    pixel_height = window_dims.pixel_height,
    x = window_dims.x,
    y = window_dims.y,
  }

  local encoded_state = wezterm.json_encode(state)
  if encoded_state == last_saved_state_json then
    return
  end

  local success, err = pcall(function()
    local f = io.open(state_file, 'w')
    if f then
      f:write(encoded_state)
      f:close()
      last_saved_state_json = encoded_state
    end
  end)

  if not success then
    wezterm.log_error('Failed to save window state: ' .. tostring(err))
  end
end

-- Debounce state persistence to avoid heavy disk writes during drag/resize
local function schedule_save_window_state(window, delay_seconds)
  if not window then
    return
  end

  local window_id = 'default'
  pcall(function()
    window_id = tostring(window:window_id())
  end)

  if pending_save_by_window[window_id] then
    return
  end

  pending_save_by_window[window_id] = true
  wezterm.time.call_after(delay_seconds or 0.3, function()
    pending_save_by_window[window_id] = nil
    save_window_state(window)
  end)
end

-- Load and restore window state on startup
wezterm.on('gui-startup', function(cmd)
  local state_data = nil

  -- Try to load saved state
  pcall(function()
    local f = io.open(state_file, 'r')
    if f then
      local content = f:read('*all')
      f:close()
      if content and content ~= '' then
        state_data = wezterm.json_parse(content)
      end
    end
  end)

  local args = {}
  if cmd then
    args = cmd.args
  end

  local tab, pane, window = wezterm.mux.spawn_window(cmd or {})

  -- Restore window size and position if saved state exists
  if state_data and state_data.pixel_width and state_data.pixel_height then
    -- Get the GUI window from the mux window
    local gui_window = window:gui_window()
    if gui_window then
      gui_window:set_inner_size(state_data.pixel_width, state_data.pixel_height)

      -- Restore position if available
      if state_data.x and state_data.y then
        gui_window:set_position(state_data.x, state_data.y)
      end
    end
  end
end)

-- Save on window resize
wezterm.on('window-resized', function(window, pane)
  schedule_save_window_state(window, 1.2)
end)

-- Save on focus change (catches Cmd+Q and window switches)
wezterm.on('window-focus-changed', function(window, pane)
  if window then
    schedule_save_window_state(window, 0.15)
  end
end)

-- Save immediately when closing a window
wezterm.on('window-close-requested', function(window, pane)
  save_window_state(window)
end)

-- ============================================================================
-- KEYBINDINGS (Command + Arrow Keys and Backspace)
-- ============================================================================
config.keys = {
  -- Command + Left Arrow: Move to beginning of line
  {
    key = 'LeftArrow',
    mods = 'CMD',
    action = act.SendString '\x01',  -- Ctrl-A (beginning of line)
  },
  -- Command + Right Arrow: Move to end of line
  {
    key = 'RightArrow',
    mods = 'CMD',
    action = act.SendString '\x05',  -- Ctrl-E (end of line)
  },
  -- Command + Backspace: Delete to beginning of line
  {
    key = 'Backspace',
    mods = 'CMD',
    action = act.SendString '\x15',  -- Ctrl-U (delete to beginning)
  },
  -- Option + Left Arrow: Move backward one word
  {
    key = 'LeftArrow',
    mods = 'OPT',
    action = act.SendString '\x1bb',  -- ESC + b (backward word)
  },
  -- Option + Right Arrow: Move forward one word
  {
    key = 'RightArrow',
    mods = 'OPT',
    action = act.SendString '\x1bf',  -- ESC + f (forward word)
  },
  -- Option + Backspace: Delete backward one word
  {
    key = 'Backspace',
    mods = 'OPT',
    action = act.SendString '\x17',  -- Ctrl-W (delete word)
  },
}

-- ============================================================================
-- FONT SETTINGS
-- ============================================================================
config.font = wezterm.font('MesloLGS Nerd Font Mono')
config.font_size = 14.0

-- ============================================================================
-- CURSOR SETTINGS
-- ============================================================================
config.default_cursor_style = 'BlinkingBar'
config.cursor_blink_rate = 800
config.cursor_blink_ease_in = 'Constant'
config.cursor_blink_ease_out = 'Constant'

-- ============================================================================
-- COLOR SCHEME (Tokyo Night)
-- ============================================================================
config.color_scheme = 'tokyonight'

-- Translucent blur effect (glass look)
config.window_background_opacity = 0.86
config.macos_window_background_blur = 22

-- Blend title/tab area into the same glass effect
config.window_frame = {
  active_titlebar_bg = 'rgba(20, 24, 38, 0.72)',
  inactive_titlebar_bg = 'rgba(20, 24, 38, 0.58)',
}

config.colors = {
  tab_bar = {
    background = 'rgba(20, 24, 38, 0.64)',
    active_tab = {
      bg_color = 'rgba(50, 62, 92, 0.92)',
      fg_color = '#c0caf5',
      intensity = 'Bold',
    },
    inactive_tab = {
      bg_color = 'rgba(20, 24, 38, 0.56)',
      fg_color = '#7aa2f7',
    },
    inactive_tab_hover = {
      bg_color = 'rgba(50, 62, 92, 0.82)',
      fg_color = '#c0caf5',
      italic = true,
    },
    new_tab = {
      bg_color = 'rgba(20, 24, 38, 0.56)',
      fg_color = '#7dcfff',
    },
    new_tab_hover = {
      bg_color = 'rgba(50, 62, 92, 0.82)',
      fg_color = '#c0caf5',
      italic = true,
    },
  },
}

-- ============================================================================
-- WINDOW APPEARANCE
-- ============================================================================
config.window_padding = {
  left = 20,
  right = 20,
  top = 10,
  bottom = 10,
}

-- Keep traffic lights visible while preserving a native title/tab toolbar
config.window_decorations = 'RESIZE | INTEGRATED_BUTTONS'

-- ============================================================================
-- MOUSE BEHAVIOR
-- ============================================================================
config.hide_mouse_cursor_when_typing = true

-- ============================================================================
-- TAB BAR APPEARANCE (Always visible with blur effect)
-- ============================================================================
config.enable_tab_bar = true
config.hide_tab_bar_if_only_one_tab = false  -- Always show tab bar
config.use_fancy_tab_bar = true  -- Keep native toolbar tabs with traffic lights
config.tab_bar_at_bottom = false

-- ============================================================================
-- PERFORMANCE & MISC
-- ============================================================================
config.front_end = 'OpenGL'
config.animation_fps = 45
config.max_fps = 45

-- Enable ligatures if your font supports them
config.harfbuzz_features = { 'calt=1', 'clig=1', 'liga=1' }

-- Scrollback
config.scrollback_lines = 10000

-- ============================================================================
-- TERMINAL ENVIRONMENT (For Oh My Posh compatibility)
-- ============================================================================
config.term = 'xterm-256color'

-- ============================================================================
-- QUIT BEHAVIOR
-- ============================================================================
-- Disable quit confirmation prompt (helps with proper state saving on Cmd+Q)
config.window_close_confirmation = 'NeverPrompt'

return config
