# kosm_hyprland

Hyprland for kosm: every `hl.config` option of upstream Hyprland's Lua config (407 options,
from `src/config/values/ConfigValues.cpp` at commit `ab61418`), grouped and named exactly like
Hyprland's own (`hyprland.general.col.active_border`, `hyprland.decoration.blur.size`). Hyprland's
`input-capture` and `tap-to-click` are spelled with underscores, as its Lua config spells them.
Everything left `null` is not written, so Hyprland's own default applies.

The app writes Lua through the `lua` adapter of `kosm_lua`, which the config needs too.

## Who owns the values

`target` decides (D91):

- **`.generate`** (the default, `default_target`): kosm writes every set option to
  `~/.config/hypr/kosm.lua`, a module shaped like `hl.config`'s argument. kosm is the source of
  truth, so any option can be set. kosm makes `hyprland.lua` read it by keeping this block at
  the end of the file, after your own `hl.config` calls so its values win (D97):

  ```lua
  -- kosm:begin hyprland
  hl.config(require("kosm"))
  -- kosm:end
  ```

  Everything outside the block stays yours. If `hyprland.lua` doesn't exist yet, kosm leaves it
  for Hyprland to create its default config on first start and warns; apply again afterwards.
  `require("kosm")` only finds `~/.config/hypr/kosm.lua`, so generating elsewhere needs
  `include = null` and a `require` of your own.
  Or read single values from it (`require("kosm").decoration.blur.size`).
- **`.edit`**: kosm sets each option where your own Lua files already hold it (D25, D30), so
  they stay the source of truth. Every set option must exist exactly once in the selected files,
  however they nest it (`col = { active_border = ... }` inside `hl.config({ general = ... })`).
  kosm never inserts a key (D28), so leave the options your files lack `null`, including the
  colors `from` fills.

  ```zig
  hyprland.target = .{ .edit = .{ .files = "~/.config/hypr/**/*.lua", .exclude = &.{"~/.config/hypr/plugins/**"} } };
  ```

Values your files keep elsewhere (a `defs.lua` table that `hl.config` reads) belong to a local
app instead (D25).

After every apply the app runs `hyprctl reload` (D74). If Hyprland isn't running, kosm prints a
warning and carries on.

## Colors

`from(theme)` sets (D27): `general.col.active_border` and `decoration.glow.color` from cyan,
`general.col.nogroup_border_active` from magenta, group borders and the groupbar from yellow
(locked: orange), groupbar text and `misc.col.splash` from the foreground, `misc.background_color`
from the background (white and black, swapped in light mode), and `decoration.shadow.color` from
the background through `surface.shadow`. The blur effects' own colors (`aurora`, `fluid_jar`,
`acrylic`) stay Hyprland's.

Each inactive color left `null` derives from its active one through `inactive` (D23):
`general.col.inactive_border`, `general.col.nogroup_border`, `decoration.shadow.color_inactive`,
`decoration.glow.color_inactive`, `group.col.border_inactive`, `group.col.border_locked_inactive`,
`group.groupbar.col.inactive`, `group.groupbar.col.locked_inactive`,
`group.groupbar.text_color_inactive` and `group.groupbar.text_color_locked_inactive`.

## Values

The types live in `kosm_hyprland.values`:

- `Gradient`: up to 10 colors and an `angle` in degrees. `.solid(color)` is one color (written as
  a plain color), `.from(&.{ a, b })` several (written `{ colors = { ... }, angle = ... }`). An
  empty gradient, or one given more than 10 colors, fails the apply naming the option (D93).
- `CssGap`: `top`, `right`, `bottom`, `left` in layout pixels; `.all(5)` is the same everywhere.
- `Vec2`: `x` and `y`, written `{ x, y }`.
- `FontWeight`: `.{ .name = .bold }` or `.{ .weight = 450 }`.
- `Layout`: `.dwindle`, `.master`, `.scrolling`, `.monocle`, or `.{ .lua = "name" }` for a layout
  your Lua config registers.
- `AccelProfile`: `.adaptive`, `.flat`, or `.{ .custom = .{ .step = 0.5, .points = &.{ 0, 0.5, 1.5 } } }`;
  `scroll_points` takes the same `AccelCurve`.
- `Transform`: `.normal`, `.rotate_90`, ..., `.flipped_180`.
- Every choice is an enum, so no option needs the wiki's numbers. Choices Hyprland names are
  written by name (`.frost` -> `"frost"`); choices it only reads as numbers
  (`scrolling.follow_focus`, `cursor.no_hardware_cursors`, ...) declare `numbered` and are written
  as the number (`.soft` -> `2`).

## App fields

| Field | Default |
|---|---|
| `target` | `default_target`: `.{ .generate = "~/.config/hypr/kosm.lua" }` |
| `include` | `"~/.config/hypr/hyprland.lua"`: the file that gets the block reading the generated module, `.generate` target only; `null` for no block |
| `format` | `.{ .color = .hex8 }`: `#rrggbbaa`, so alpha is kept; the rest from the Lua adapter, then kosm (D70) |
| `inactive` | the theme's `state.inactive`; derives the inactive colors listed above |

## Options

| Option | Type | Meaning |
|---|---|---|
| `general.border_size` | `?i64` | Size of the border around windows. 0..20. null: Hyprland's default, `1`. |
| `general.gaps_in` | `?values.CssGap` | Gaps between windows. null: Hyprland's default, `5`. |
| `general.gaps_out` | `?values.CssGap` | Gaps between windows and monitor edges. null: Hyprland's default, `20`. |
| `general.float_gaps` | `?values.CssGap` | Gaps between windows and monitor edges for floating windows. null: Hyprland's default, `0`. |
| `general.gaps_workspaces` | `?i64` | Gaps between workspaces. Stacks with gaps_out. 0..100. null: Hyprland's default, `0`. |
| `general.col.inactive_border` | `?values.Gradient` | Border color for inactive windows. null: `active_border` through the app's `inactive` when that is set, else Hyprland's default (D23). |
| `general.col.active_border` | `?values.Gradient` | Border color for the active window. null: Hyprland's default, `#ffffffff`. |
| `general.col.nogroup_border` | `?values.Gradient` | Inactive border color for window that cannot be added to a group. null: `nogroup_border_active` through the app's `inactive` when that is set, else Hyprland's default (D23). |
| `general.col.nogroup_border_active` | `?values.Gradient` | Active border color for window that cannot be added to a group. null: Hyprland's default, `#ff00ffff`. |
| `general.layout` | `?values.Layout` | Which layout to use: a built-in one, or one written in Lua (`.{ .lua = "name" }`). null: Hyprland's default, `dwindle`. |
| `general.no_focus_fallback` | `?bool` | If true, will not fall back to the next available window when moving focus in a direction where no window was found. null: Hyprland's default, `false`. |
| `general.resize_on_border` | `?bool` | Enables resizing windows by clicking and dragging on borders and gaps. null: Hyprland's default, `false`. |
| `general.extend_border_grab_area` | `?i64` | Extends the area around the border where you can click and drag on, only used when general:resize_on_border is on. 0..100. null: Hyprland's default, `15`. |
| `general.hover_icon_on_border` | `?bool` | Show a cursor icon when hovering over borders, only used when general:resize_on_border is on. null: Hyprland's default, `true`. |
| `general.allow_tearing` | `?bool` | Master switch for allowing tearing to occur. null: Hyprland's default, `false`. |
| `general.resize_corner` | enum: `.disable`, `.top_left`, `.top_right`, `.bottom_right`, `.bottom_left` | Force floating windows to use a specific corner when being resized (1-4 going clockwise from top left, 0 to disable). null: Hyprland's default, `disable`. |
| `general.snap.enabled` | `?bool` | Enable snapping for floating windows. null: Hyprland's default, `false`. |
| `general.snap.window_gap` | `?i64` | Minimum gap in pixels between windows before snapping. 0..100. null: Hyprland's default, `10`. |
| `general.snap.monitor_gap` | `?i64` | Minimum gap in pixels between window and monitor edges before snapping. 0..100. null: Hyprland's default, `10`. |
| `general.snap.border_overlap` | `?bool` | If true, windows snap such that only one border's worth of space is between them. null: Hyprland's default, `false`. |
| `general.snap.respect_gaps` | `?bool` | If true, snapping will respect gaps between windows. null: Hyprland's default, `false`. |
| `general.modal_parent_blocking` | `?bool` | If true, parent windows of modals will not be interactive. null: Hyprland's default, `true`. |
| `general.locale` | `?[]const u8` | Overrides the system locale. null: Hyprland's default, empty. |
| `decoration.rounding` | `?i64` | Rounded corners' radius (in layout px). 0..100. null: Hyprland's default, `0`. |
| `decoration.rounding_power` | `?f64` | Rounding power of corners (2 is a circle). null: Hyprland's default, `2`. |
| `decoration.active_opacity` | `?f64` | Opacity of active windows. null: Hyprland's default, `1`. |
| `decoration.inactive_opacity` | `?f64` | Opacity of inactive windows. null: Hyprland's default, `1`. |
| `decoration.fullscreen_opacity` | `?f64` | Opacity of fullscreen windows. null: Hyprland's default, `1`. |
| `decoration.shadow.enabled` | `?bool` | Enable drop shadows on windows. null: Hyprland's default, `true`. |
| `decoration.shadow.range` | `?i64` | Shadow range (size) in layout px. 0..100. null: Hyprland's default, `4`. |
| `decoration.shadow.render_power` | `?i64` | In what power to render the falloff (more power, the faster the falloff). 1..4. null: Hyprland's default, `3`. |
| `decoration.shadow.sharp` | `?bool` | Whether the shadow should be sharp or not. null: Hyprland's default, `false`. |
| `decoration.shadow.color` | `?values.Gradient` | Shadow's color. Alpha dictates shadow's opacity. null: Hyprland's default, `#1a1a1aee`. |
| `decoration.shadow.color_inactive` | `?values.Gradient` | Inactive shadow color. null: `color` through the app's `inactive` when that is set, else Hyprland's default (D23). |
| `decoration.shadow.offset` | `?values.Vec2` | Shadow's rendering offset. null: Hyprland's default, `2`. |
| `decoration.shadow.scale` | `?f64` | Shadow's scale. null: Hyprland's default, `1`. |
| `decoration.glow.enabled` | `?bool` | Enable inner glow on windows. null: Hyprland's default, `false`. |
| `decoration.glow.range` | `?i64` | Glow range (size) in layout px. 0..100. null: Hyprland's default, `10`. |
| `decoration.glow.render_power` | `?i64` | In what power to render the falloff (more power, the faster the falloff). 1..4. null: Hyprland's default, `3`. |
| `decoration.glow.color` | `?values.Gradient` | Glow's color. Alpha dictates glow's opacity. null: Hyprland's default, `#33ccffee`. |
| `decoration.glow.color_inactive` | `?values.Gradient` | Inactive glow color. null: `color` through the app's `inactive` when that is set, else Hyprland's default (D23). |
| `decoration.dim_modal` | `?bool` | Enables dimming of parents of modal windows. null: Hyprland's default, `true`. |
| `decoration.dim_inactive` | `?bool` | Enables dimming of inactive windows. null: Hyprland's default, `false`. |
| `decoration.dim_strength` | `?f64` | How much inactive windows should be dimmed. null: Hyprland's default, `0.5`. |
| `decoration.dim_special` | `?f64` | How much to dim the rest of the screen by when a special workspace is open. null: Hyprland's default, `0.2`. |
| `decoration.dim_around` | `?f64` | How much the dimaround window rule should dim by. null: Hyprland's default, `0.4`. |
| `decoration.screen_shader` | `?[]const u8` | A path to a custom shader to be applied at the end of rendering. null: Hyprland's default, empty. |
| `decoration.border_part_of_window` | `?bool` | Whether the border should be treated as a part of the window. null: Hyprland's default, `true`. |
| `decoration.blur.enabled` | `?bool` | Enable window background blur. null: Hyprland's default, `true`. |
| `decoration.blur.variant` | enum: `.kawase`, `.frost`, `.ripple`, `.drops`, `.water`, `.fluid_jar`, `.prism`, `.heat_shimmer`, `.acrylic`, `.aurora`, `.haze` | Set the blur variant. Blur variants enhance regular blur, but may increase GPU and CPU usage, significantly so if they are animated. null: Hyprland's default, `kawase`. |
| `decoration.blur.size` | `?i64` | Blur size (distance). 0..100. null: Hyprland's default, `8`. |
| `decoration.blur.passes` | `?i64` | The amount of passes to perform. 0..10. null: Hyprland's default, `1`. |
| `decoration.blur.ignore_opacity` | `?bool` | Make the blur layer ignore the opacity of the window. null: Hyprland's default, `true`. |
| `decoration.blur.new_optimizations` | `?bool` | Whether to enable further optimizations to the blur. null: Hyprland's default, `true`. |
| `decoration.blur.xray` | `?bool` | If enabled, floating windows will ignore tiled windows in their blur. null: Hyprland's default, `false`. |
| `decoration.blur.proportional` | `?bool` | If enabled, blur strength will be proportional to pixel opacity. null: Hyprland's default, `false`. |
| `decoration.blur.noise` | `?f64` | How much noise to apply. null: Hyprland's default, `0.0117`. |
| `decoration.blur.contrast` | `?f64` | Contrast modulation for blur. null: Hyprland's default, `0.8916`. |
| `decoration.blur.brightness` | `?f64` | Brightness modulation for blur. null: Hyprland's default, `1`. |
| `decoration.blur.vibrancy` | `?f64` | Increase saturation of blurred colors. null: Hyprland's default, `0.1696`. |
| `decoration.blur.vibrancy_darkness` | `?f64` | How strong the effect of vibrancy is on dark areas. null: Hyprland's default, `0`. |
| `decoration.blur.special` | `?bool` | Whether to blur behind the special workspace (note: expensive). null: Hyprland's default, `false`. |
| `decoration.blur.popups` | `?bool` | Whether to blur popups (e.g. right-click menus). null: Hyprland's default, `false`. |
| `decoration.blur.popups_ignorealpha` | `?f64` | Works like ignorealpha in layer rules. If pixel opacity is below set value, will not blur. null: Hyprland's default, `0.2`. |
| `decoration.blur.input_methods` | `?bool` | Whether to blur input methods (e.g. fcitx5). null: Hyprland's default, `false`. |
| `decoration.blur.input_methods_ignorealpha` | `?f64` | Works like ignorealpha in layer rules. If pixel opacity is below set value, will not blur. null: Hyprland's default, `0.2`. |
| `decoration.blur.glass.refraction` | `?f64` | Maximum refraction displacement for glass blur types in pixels. null: Hyprland's default, `20`. |
| `decoration.blur.glass.size` | `?f64` | Pattern size for glass blur types in pixels. null: Hyprland's default, `40`. |
| `decoration.blur.glass.roughness` | `?f64` | Strength of the glass relief shading. null: Hyprland's default, `1`. |
| `decoration.blur.acrylic.refraction` | `?f64` | Maximum acrylic lens displacement in pixels. null: Hyprland's default, `24`. |
| `decoration.blur.acrylic.bulb` | `?f64` | Width of the curved acrylic edge in pixels. null: Hyprland's default, `48`. |
| `decoration.blur.acrylic.clarity` | `?f64` | Amount of sharp backdrop transmitted through the acrylic surface. null: Hyprland's default, `0.82`. |
| `decoration.blur.acrylic.aberration` | `?f64` | Relative chromatic separation in the acrylic lens. null: Hyprland's default, `0.025`. |
| `decoration.blur.acrylic.tint` | `?kosm.Color` | Acrylic tint color. Alpha controls optical absorption. null: Hyprland's default, `#eef5ff14`. |
| `decoration.blur.drops.speed` | `?f64` | Animation speed for drops blur. 0 disables the animation. Enabling will significantly increase GPU usage. null: Hyprland's default, `3`. |
| `decoration.blur.heat_shimmer.speed` | `?f64` | Animation speed for heat shimmer blur. 0 disables the animation. Enabling will increase GPU usage. null: Hyprland's default, `1`. |
| `decoration.blur.aurora.speed` | `?f64` | Animation speed for aurora blur. 0 freezes the animation. Enabling will increase GPU usage. null: Hyprland's default, `1`. |
| `decoration.blur.aurora.intensity` | `?f64` | Strength of the aurora color contribution. null: Hyprland's default, `0.35`. |
| `decoration.blur.aurora.color1` | `?kosm.Color` | First aurora curtain color. Alpha controls its contribution. null: Hyprland's default, `#f0a0ff29`. |
| `decoration.blur.aurora.color2` | `?kosm.Color` | Second aurora curtain color. Alpha controls its contribution. null: Hyprland's default, `#4dffff7a`. |
| `decoration.blur.haze.intensity` | `?f64` | Strength of the haze pearlescent sheen. null: Hyprland's default, `0.35`. |
| `decoration.blur.haze.iridescence` | `?f64` | Strength of the haze pearlescent color shift. null: Hyprland's default, `0.7`. |
| `decoration.blur.ripple.strength` | `?f64` | Maximum refraction displacement of click ripples in pixels. null: Hyprland's default, `30`. |
| `decoration.blur.ripple.radius` | `?f64` | Maximum radius of click ripples in pixels. null: Hyprland's default, `400`. |
| `decoration.blur.ripple.width` | `?f64` | Width of click ripple waves in pixels. null: Hyprland's default, `32`. |
| `decoration.blur.ripple.duration` | `?f64` | Duration of click ripples in seconds. null: Hyprland's default, `0.45`. |
| `decoration.blur.water.strength` | `?f64` | Maximum refraction displacement and injection strength for water blur in pixels. null: Hyprland's default, `32`. |
| `decoration.blur.water.radius` | `?f64` | Pointer radius for water blur in pixels. null: Hyprland's default, `20`. |
| `decoration.blur.water.speed` | `?f64` | Propagation speed for water blur. null: Hyprland's default, `0.76`. |
| `decoration.blur.water.damping` | `?f64` | Decay damping for water blur. null: Hyprland's default, `0.95`. |
| `decoration.blur.water.duration` | `?f64` | Maximum water blur animation duration in seconds. null: Hyprland's default, `12`. |
| `decoration.blur.fluid_jar.color` | `?kosm.Color` | Fluid color for fluid jar blur. null: Hyprland's default, `#3399ffcc`. |
| `decoration.blur.fluid_jar.speed` | `?f64` | Animation speed for fluid jar blur. null: Hyprland's default, `3.7`. |
| `decoration.blur.fluid_jar.fill_amount` | `?f64` | Fill amount for fluid jar blur. null: Hyprland's default, `0.5`. |
| `decoration.blur.fluid_jar.mass` | `?f64` | Inertial mass for fluid jar blur. null: Hyprland's default, `1.4`. |
| `decoration.blur.fluid_jar.precision` | `?f64` | Fluid simulation precision multiplier. 2x is a good compromise. 4x is expensive. 8x is extreme and unnecessary. null: Hyprland's default, `2`. |
| `decoration.blur.fluid_jar.turbulence` | `?f64` | Interior fluid turbulence multiplier. null: Hyprland's default, `1.2`. |
| `decoration.blur.fluid_jar.distortion` | `?f64` | Fluid refraction distortion multiplier. null: Hyprland's default, `8`. |
| `decoration.motion_blur.enabled` | `?bool` | Enable motion blur for moving and resizing windows. null: Hyprland's default, `false`. |
| `decoration.motion_blur.samples` | `?i64` | Amount of samples used for motion blur. 1..64. null: Hyprland's default, `7`. |
| `decoration.wobble.enabled` | `?bool` | Enable wobble deformation for moving and resizing windows. null: Hyprland's default, `false`. |
| `decoration.wobble.mesh` | `?i64` | Amount of wobble mesh vertices per edge. 2..32. null: Hyprland's default, `12`. |
| `decoration.wobble.stiffness` | `?f64` | Spring stiffness for wobble deformation. null: Hyprland's default, `200`. |
| `decoration.wobble.damping` | `?f64` | Spring damping for wobble deformation. null: Hyprland's default, `12`. |
| `decoration.wobble.mass` | `?f64` | Spring mass for wobble deformation. null: Hyprland's default, `1`. |
| `decoration.wobble.intensity` | `?f64` | Wobble deformation impulse multiplier. null: Hyprland's default, `0.2`. |
| `decoration.wobble.value_epsilon` | `?f64` | Position epsilon below which wobble is considered stable. null: Hyprland's default, `0.25`. |
| `decoration.wobble.velocity_epsilon` | `?f64` | Velocity epsilon below which wobble is considered stable. null: Hyprland's default, `2`. |
| `animations.enabled` | `?bool` | Enable animations. null: Hyprland's default, `true`. |
| `animations.workspace_wraparound` | `?bool` | Changes the direction of slide animations between the first and last workspaces. null: Hyprland's default, `false`. |
| `input.kb_model` | `?[]const u8` | Appropriate XKB keymap parameter. null: Hyprland's default, empty. |
| `input.kb_layout` | `?[]const u8` | Appropriate XKB keymap parameter. null: Hyprland's default, `us`. |
| `input.kb_variant` | `?[]const u8` | Appropriate XKB keymap parameter. null: Hyprland's default, empty. |
| `input.kb_options` | `?[]const u8` | Appropriate XKB keymap parameter. null: Hyprland's default, empty. |
| `input.kb_rules` | `?[]const u8` | Appropriate XKB keymap parameter. null: Hyprland's default, empty. |
| `input.kb_file` | `?[]const u8` | Appropriate XKB keymap file. null: Hyprland's default, empty. |
| `input.numlock_by_default` | `?bool` | Engage numlock by default. null: Hyprland's default, `false`. |
| `input.resolve_binds_by_sym` | `?bool` | Determines how keybinds act when multiple layouts are used. null: Hyprland's default, `false`. |
| `input.repeat_rate` | `?i64` | The repeat rate for held-down keys, in repeats per second. 0..200. null: Hyprland's default, `25`. |
| `input.repeat_delay` | `?i64` | Delay before a held-down key is repeated, in milliseconds. 0..2000. null: Hyprland's default, `600`. |
| `input.sensitivity` | `?f64` | Sets the mouse input sensitivity. Value is clamped to the range -1.0 to 1.0. null: Hyprland's default, `0`. |
| `input.accel_profile` | `?values.AccelProfile` | Sets the cursor acceleration profile; `.{ .custom = ... }` is a curve of points. null: Hyprland's default, the device's own. |
| `input.force_no_accel` | `?bool` | Force no cursor acceleration. null: Hyprland's default, `false`. |
| `input.rotation` | `?i64` | Sets the rotation of a device in degrees clockwise. Value is clamped to the range 0 to 359. 0..359. null: Hyprland's default, `0`. |
| `input.left_handed` | `?bool` | Switches RMB and LMB. null: Hyprland's default, `false`. |
| `input.scroll_points` | `?values.AccelCurve` | Sets the scroll acceleration curve, when `accel_profile` is `.custom`. null: Hyprland's default, none. |
| `input.scroll_method` | enum: `.@"2fg"`, `.edge`, `.on_button_down`, `.no_scroll` | Sets the scroll method. [2fg/edge/on_button_down/no_scroll]. null: Hyprland's default, empty. |
| `input.scroll_button` | `?i64` | Sets the scroll button. 0 means default. 0..300. null: Hyprland's default, `0`. |
| `input.scroll_button_lock` | `?bool` | If the scroll button lock is enabled, the button does not need to be held down. null: Hyprland's default, `false`. |
| `input.scroll_factor` | `?f64` | Multiplier added to scroll movement for external mice. null: Hyprland's default, `1`. |
| `input.natural_scroll` | `?bool` | Inverts scrolling direction. null: Hyprland's default, `false`. |
| `input.follow_mouse` | enum: `.disabled`, `.follow`, `.detached`, `.separate` | Specify if and how cursor movement should affect window focus. null: Hyprland's default, `follow`. |
| `input.follow_mouse_threshold` | `?f64` | The smallest distance in logical pixels the mouse needs to travel for the window under it to get focused. null: Hyprland's default, `0`. |
| `input.swallow_focus_click` | `?bool` | If enabled, the click that changes window focus is not forwarded to the window. null: Hyprland's default, `false`. |
| `input.focus_on_close` | enum: `.next`, `.cursor`, `.mru` | Controls the window focus behavior when a window is closed. null: Hyprland's default, `next`. |
| `input.mouse_refocus` | `?bool` | If disabled, mouse focus won't switch to the hovered window unless the mouse crosses a window boundary when follow_mouse=1. null: Hyprland's default, `true`. |
| `input.float_switch_override_focus` | enum: `.disabled`, `.enabled`, `.floating_too` | Focus changes to the window under the cursor when switching from tiled to floating and back, and with `floating_too` also from floating to floating. null: Hyprland's default, `enabled`. |
| `input.special_fallthrough` | `?bool` | If enabled, having only floating windows in the special workspace will not block focusing windows in the regular workspace. null: Hyprland's default, `false`. |
| `input.off_window_axis_events` | enum: `.ignore`, `.send`, `.clamp`, `.warp` | How to handle axis events around a focused window. null: Hyprland's default, `send`. |
| `input.emulate_discrete_scroll` | enum: `.disable`, `.non_standard`, `.force_all` | Emulates discrete scrolling from high resolution scrolling events. null: Hyprland's default, `non_standard`. |
| `input.follow_mouse_shrink` | `?i64` | Shrinks the inactive window hitboxes used for focus detection by the specified number of pixels. This creates a dead zone in gaps between windows where moving the cursor will not change focus. Works only with follow_mouse = 1. 0..300. null: Hyprland's default, `0`. |
| `input.touchpad.disable_while_typing` | `?bool` | Disable the touchpad while typing. null: Hyprland's default, `true`. |
| `input.touchpad.natural_scroll` | `?bool` | Inverts scrolling direction. null: Hyprland's default, `false`. |
| `input.touchpad.scroll_factor` | `?f64` | Multiplier applied to the amount of scroll movement. null: Hyprland's default, `1`. |
| `input.touchpad.middle_button_emulation` | `?bool` | Sending LMB and RMB simultaneously will be interpreted as a middle click. null: Hyprland's default, `false`. |
| `input.touchpad.tap_button_map` | enum: `.lrm`, `.lmr` | Sets the tap button mapping for touchpad button emulation. [lrm/lmr]. null: Hyprland's default, empty. |
| `input.touchpad.clickfinger_behavior` | `?bool` | Button presses with 1, 2, or 3 fingers will be mapped to LMB, RMB, and MMB respectively. null: Hyprland's default, `false`. |
| `input.touchpad.tap_to_click` | `?bool` | Tapping on the touchpad with 1, 2, or 3 fingers will send LMB, RMB, and MMB respectively. null: Hyprland's default, `true`. |
| `input.touchpad.drag_lock` | enum: `.disabled`, `.timeout`, `.sticky` | Lifting the finger off while dragging does not drop the dragged item: until a timeout, or until the next tap (`sticky`). null: Hyprland's default, `disabled`. |
| `input.touchpad.tap_and_drag` | `?bool` | Sets the tap and drag mode for the touchpad. null: Hyprland's default, `true`. |
| `input.touchpad.flip_x` | `?bool` | Inverts the horizontal movement of the touchpad. null: Hyprland's default, `false`. |
| `input.touchpad.flip_y` | `?bool` | Inverts the vertical movement of the touchpad. null: Hyprland's default, `false`. |
| `input.touchpad.drag_3fg` | enum: `.disable`, `.@"3_finger"`, `.@"4_finger"` | Whether to use 3 or 4 finger drag. null: Hyprland's default, `disable`. |
| `input.touchdevice.transform` | `?values.Transform` | Transform the input from touchdevices. null: Hyprland's default, `normal`. |
| `input.touchdevice.output` | `?[]const u8` | The monitor to bind touch devices. null: Hyprland's default, `[[Auto]]`. |
| `input.touchdevice.enabled` | `?bool` | Whether input is enabled for touch devices. null: Hyprland's default, `true`. |
| `input.virtualkeyboard.share_states` | enum: `.disable`, `.enable`, `.only_non_ime` | Unify key down states and modifier states with other keyboards. null: Hyprland's default, `only_non_ime`. |
| `input.virtualkeyboard.release_pressed_on_close` | `?bool` | Release all pressed keys by virtual keyboard on close. null: Hyprland's default, `false`. |
| `input.tablet.enabled` | `?bool` | Whether input is enabled for tablets. null: Hyprland's default, `true`. |
| `input.tablet.transform` | `?values.Transform` | Transform the input from tablets. null: Hyprland's default, `normal`. |
| `input.tablet.output` | `?[]const u8` | The monitor to bind tablets. null: Hyprland's default, empty. |
| `input.tablet.region_position` | `?values.Vec2` | Position of the mapped region in monitor layout. null: Hyprland's default, `2`. |
| `input.tablet.absolute_region_position` | `?bool` | Whether to treat the region_position as an absolute position in monitor layout. null: Hyprland's default, `false`. |
| `input.tablet.region_size` | `?values.Vec2` | Size of the mapped region. null: Hyprland's default, `2`. |
| `input.tablet.relative_input` | `?bool` | Whether the input should be relative. null: Hyprland's default, `false`. |
| `input.tablet.left_handed` | `?bool` | If enabled, the tablet will be rotated 180 degrees. null: Hyprland's default, `false`. |
| `input.tablet.active_area_size` | `?values.Vec2` | Size of tablet's active area in mm. null: Hyprland's default, `2`. |
| `input.tablet.active_area_position` | `?values.Vec2` | Position of the active area in mm. null: Hyprland's default, `2`. |
| `input.tablettool.eraser_button_mode` | enum: `.default`, `.button` | The eraser button on the tool: the hardware's own behavior, or a button event (see `eraser_button_override`). null: Hyprland's default, `default`. |
| `input.tablettool.eraser_button_override` | `?i64` | Set a button to be button event when eraser_button_mode is set to 1. Has to be an int, cannot be a string. Must be a valid button (e.g. BTN_STYLUS) excluding fake buttons (e.g. BTN_TOOL_*) and keys (KEY_*). Check wev if you have any doubts regarding the ID. 0 means default. null: Hyprland's default, `0`. |
| `input.tablettool.pressure_range_min` | `?f64` | Set the minimum pressure range for the tool, a negative number will set the default minimum pressure value. This is usually 0.0. null: Hyprland's default, `-1.0`. |
| `input.tablettool.pressure_range_max` | `?f64` | Set the maximum pressure range for the tool, a negative number will set the default maximum pressure value. This is usually 1.0. null: Hyprland's default, `-1.0`. |
| `gestures.workspace_swipe_distance` | `?i64` | In px, the distance of the touchpad gesture. 0..2000. null: Hyprland's default, `300`. |
| `gestures.workspace_swipe_touch` | `?bool` | Enable workspace swiping from the edge of a touchscreen. null: Hyprland's default, `false`. |
| `gestures.workspace_swipe_invert` | `?bool` | Invert the direction (touchpad only). null: Hyprland's default, `true`. |
| `gestures.workspace_swipe_touch_invert` | `?bool` | Invert the direction (touchscreen only). null: Hyprland's default, `false`. |
| `gestures.workspace_swipe_min_speed_to_force` | `?i64` | Minimum speed in px per timepoint to force the change ignoring cancel_ratio. 0..200. null: Hyprland's default, `30`. |
| `gestures.workspace_swipe_cancel_ratio` | `?f64` | How much the swipe has to proceed in order to commence it. null: Hyprland's default, `0.5`. |
| `gestures.workspace_swipe_create_new` | `?bool` | Whether a swipe right on the last workspace should create a new one. null: Hyprland's default, `true`. |
| `gestures.workspace_swipe_direction_lock` | `?bool` | If enabled, switching direction will be locked when you swipe past the direction_lock_threshold. null: Hyprland's default, `true`. |
| `gestures.workspace_swipe_direction_lock_threshold` | `?i64` | In px, the distance to swipe before direction lock activates. 0..200. null: Hyprland's default, `10`. |
| `gestures.workspace_swipe_forever` | `?bool` | If enabled, swiping will not clamp at the neighboring workspaces but continue to the further ones. null: Hyprland's default, `false`. |
| `gestures.workspace_swipe_use_r` | `?bool` | If enabled, swiping will use the r prefix instead of the m prefix for finding workspaces. null: Hyprland's default, `false`. |
| `gestures.close_max_timeout` | `?i64` | Timeout for closing windows with the close gesture, in ms. 10..2000. null: Hyprland's default, `1000`. |
| `gestures.scrolling.move_snap_to_grid` | `?bool` | When releasing the scroll move gesture, whether it shoud try to snap to the grid. null: Hyprland's default, `true`. |
| `gestures.scrolling.move_snap_cursor` | `?bool` | When releasing the scroll move gesture, whether it shoud snap the cursor to the newly focused window. null: Hyprland's default, `true`. |
| `group.insert_after_current` | `?bool` | Whether new windows in a group spawn after current or at group tail. null: Hyprland's default, `true`. |
| `group.focus_removed_window` | `?bool` | Whether Hyprland should focus on the window that has just been moved out of the group. null: Hyprland's default, `true`. |
| `group.merge_groups_on_drag` | `?bool` | Whether window groups can be dragged into other groups. null: Hyprland's default, `true`. |
| `group.merge_groups_on_groupbar` | `?bool` | Whether one group will be merged with another when dragged into its groupbar. null: Hyprland's default, `true`. |
| `group.col.border_active` | `?values.Gradient` | Active group border color. null: Hyprland's default, `#ffff0066`. |
| `group.col.border_inactive` | `?values.Gradient` | Inactive group border color. null: `border_active` through the app's `inactive` when that is set, else Hyprland's default (D23). |
| `group.col.border_locked_inactive` | `?values.Gradient` | Inactive locked group border color. null: `border_locked_active` through the app's `inactive` when that is set, else Hyprland's default (D23). |
| `group.col.border_locked_active` | `?values.Gradient` | Active locked group border color. null: Hyprland's default, `#77550066`. |
| `group.auto_group` | `?bool` | Automatically group new windows. null: Hyprland's default, `true`. |
| `group.drag_into_group` | enum: `.disabled`, `.enabled`, `.only_into_groupbar` | Whether dragging a window into a unlocked group will merge them. null: Hyprland's default, `enabled`. |
| `group.merge_floated_into_tiled_on_groupbar` | `?bool` | Whether dragging a floating window into a tiled window groupbar will merge them. null: Hyprland's default, `false`. |
| `group.group_on_movetoworkspace` | `?bool` | Whether using movetoworkspace[silent] will merge the window into the workspace's solitary unlocked group. null: Hyprland's default, `false`. |
| `group.groupbar.enabled` | `?bool` | Enables groupbars. null: Hyprland's default, `true`. |
| `group.groupbar.disable_when_only` | `?bool` | Disable if contains single window. Considered only if enabled == true. null: Hyprland's default, `false`. |
| `group.groupbar.font_family` | `?[]const u8` | Font used to display groupbar titles. null: Hyprland's default, empty. |
| `group.groupbar.font_weight_active` | `?values.FontWeight` | Weight of the font used to display active groupbar titles. null: Hyprland's default. |
| `group.groupbar.font_weight_inactive` | `?values.FontWeight` | Weight of the font used to display inactive groupbar titles. null: Hyprland's default. |
| `group.groupbar.font_size` | `?i64` | Font size of groupbar title. 2..64. null: Hyprland's default, `8`. |
| `group.groupbar.gradients` | `?bool` | Enables gradients. null: Hyprland's default, `false`. |
| `group.groupbar.height` | `?i64` | Height of the groupbar. 1..64. null: Hyprland's default, `14`. |
| `group.groupbar.indicator_gap` | `?i64` | Height of the gap between the groupbar indicator and title. 0..64. null: Hyprland's default, `0`. |
| `group.groupbar.indicator_height` | `?i64` | Height of the groupbar indicator. 0..64. null: Hyprland's default, `3`. |
| `group.groupbar.stacked` | `?bool` | Render the groupbar as a vertical stack. null: Hyprland's default, `false`. |
| `group.groupbar.priority` | `?i64` | Sets the decoration priority for groupbars. 0..6. null: Hyprland's default, `3`. |
| `group.groupbar.render_titles` | `?bool` | Whether to render titles in the group bar decoration. null: Hyprland's default, `true`. |
| `group.groupbar.scrolling` | `?bool` | Whether scrolling in the groupbar changes group active window. null: Hyprland's default, `true`. |
| `group.groupbar.middle_click_close` | `?bool` | Whether middle clicking the groupbar closes the clicked window. null: Hyprland's default, `true`. |
| `group.groupbar.rounding` | `?i64` | How much to round the groupbar. 0..40. null: Hyprland's default, `1`. |
| `group.groupbar.rounding_power` | `?f64` | Rounding power of groupbar corners (2 is a circle). null: Hyprland's default, `2`. |
| `group.groupbar.gradient_rounding` | `?i64` | How much to round the groupbar gradient. 0..40. null: Hyprland's default, `2`. |
| `group.groupbar.gradient_rounding_power` | `?f64` | Rounding power of groupbar gradient corners (2 is a circle). null: Hyprland's default, `2`. |
| `group.groupbar.round_only_edges` | `?bool` | If yes, will only round at the groupbar edges. null: Hyprland's default, `true`. |
| `group.groupbar.gradient_round_only_edges` | `?bool` | If yes, will only round at the groupbar gradient edges. null: Hyprland's default, `true`. |
| `group.groupbar.text_color` | `?kosm.Color` | Color for window titles in the groupbar. null: Hyprland's default, `#ffffffff`. |
| `group.groupbar.text_color_inactive` | `?kosm.Color` | Color for inactive windows' titles in the groupbar. null: `text_color` through the app's `inactive` when that is set, else Hyprland's default (D23). |
| `group.groupbar.text_color_locked_active` | `?kosm.Color` | Color for the active window's title in a locked group. null: Hyprland's default. |
| `group.groupbar.text_color_locked_inactive` | `?kosm.Color` | Color for inactive windows' titles in locked groups. null: `text_color_locked_active` through the app's `inactive` when that is set, else Hyprland's default (D23). |
| `group.groupbar.col.active` | `?values.Gradient` | Active group border color. null: Hyprland's default, `#ffff0066`. |
| `group.groupbar.col.inactive` | `?values.Gradient` | Inactive (out of focus) group border color. null: `active` through the app's `inactive` when that is set, else Hyprland's default (D23). |
| `group.groupbar.col.locked_active` | `?values.Gradient` | Active locked group border color. null: Hyprland's default, `#ff550066`. |
| `group.groupbar.col.locked_inactive` | `?values.Gradient` | Inactive locked group border color. null: `locked_active` through the app's `inactive` when that is set, else Hyprland's default (D23). |
| `group.groupbar.gaps_out` | `?i64` | Gap between gradients and window. 0..20. null: Hyprland's default, `2`. |
| `group.groupbar.gaps_in` | `?i64` | Gap between gradients. 0..20. null: Hyprland's default, `2`. |
| `group.groupbar.keep_upper_gap` | `?bool` | Keep an upper gap above gradient. null: Hyprland's default, `true`. |
| `group.groupbar.text_offset` | `?i64` | Set an offset for a text. -20..20. null: Hyprland's default, `0`. |
| `group.groupbar.text_padding` | `?i64` | Set horizontal padding for a text. 0..22. null: Hyprland's default, `0`. |
| `group.groupbar.blur` | `?bool` | Enable background blur for groupbars. null: Hyprland's default, `false`. |
| `misc.disable_hyprland_logo` | `?bool` | Disables the random Hyprland logo / anime girl background. :(. null: Hyprland's default, `false`. |
| `misc.disable_splash_rendering` | `?bool` | Disables the Hyprland splash rendering. null: Hyprland's default, `false`. |
| `misc.col.splash` | `?kosm.Color` | Changes the color of the splash text. null: Hyprland's default, `#ffffff55`. |
| `misc.font_family` | `?[]const u8` | Set the global default font to render the text. null: Hyprland's default, `Sans`. |
| `misc.splash_font_family` | `?[]const u8` | Changes the font used to render the splash text. null: Hyprland's default, empty. |
| `misc.force_default_wallpaper` | enum: `.random`, `.wall0`, `.wall1`, `.wall2` | Forces one of Hyprland's 3 default wallpapers, or a random one. null: Hyprland's default, `random`. |
| `misc.vrr` | enum: `.off`, `.on`, `.fullscreen`, `.fullscreen_game` | Controls the VRR (Adaptive Sync) of your monitors. null: Hyprland's default, `off`. |
| `misc.mouse_move_enables_dpms` | `?bool` | If DPMS is set to off, wake up the monitors if the mouse moves. null: Hyprland's default, `false`. |
| `misc.key_press_enables_dpms` | `?bool` | If DPMS is set to off, wake up the monitors if a key is pressed. null: Hyprland's default, `false`. |
| `misc.name_vk_after_proc` | `?bool` | Name virtual keyboards after the processes that create them. null: Hyprland's default, `true`. |
| `misc.always_follow_on_dnd` | `?bool` | Will make mouse focus follow the mouse when drag and dropping. null: Hyprland's default, `true`. |
| `misc.layers_hog_keyboard_focus` | `?bool` | If true, will make keyboard-interactive layers keep their focus on mouse move. null: Hyprland's default, `true`. |
| `misc.animate_manual_resizes` | `?bool` | If true, will animate manual window resizes/moves. null: Hyprland's default, `false`. |
| `misc.animate_mouse_windowdragging` | `?bool` | If true, will animate windows being dragged by mouse. null: Hyprland's default, `false`. |
| `misc.disable_autoreload` | `?bool` | If true, the config will not reload automatically on save. null: Hyprland's default, `false`. |
| `misc.enable_swallow` | `?bool` | Enable window swallowing. null: Hyprland's default, `false`. |
| `misc.swallow_regex` | `?[]const u8` | The class regex to be used for windows that should be swallowed. null: Hyprland's default, empty. |
| `misc.swallow_exception_regex` | `?[]const u8` | The title regex to be used for windows that should not be swallowed. null: Hyprland's default, empty. |
| `misc.focus_on_activate` | `?bool` | Whether Hyprland should focus an app that requests to be focused. null: Hyprland's default, `false`. |
| `misc.mouse_move_focuses_monitor` | `?bool` | Whether mouse moving into a different monitor should focus it. null: Hyprland's default, `true`. |
| `misc.allow_session_lock_restore` | `?bool` | If true, will allow you to restart a lockscreen app in case it crashes. null: Hyprland's default, `false`. |
| `misc.session_lock_xray` | `?bool` | Keep rendering workspaces below your lockscreen. null: Hyprland's default, `false`. |
| `misc.session_lock_blur` | `?bool` | Enable blur for lockscreen. You probably want to enable `session_lock_xray`. null: Hyprland's default, `false`. |
| `misc.background_color` | `?kosm.Color` | Change the background color. null: Hyprland's default, `#111111ff`. |
| `misc.close_special_on_empty` | `?bool` | Close the special workspace if the last window is removed. null: Hyprland's default, `true`. |
| `misc.on_focus_under_fullscreen` | enum: `.ignore`, `.take_over`, `.exit_fullscreen` | If there is a fullscreen or maximized window, decide whether a tiled window requested to focus should replace it. null: Hyprland's default, `exit_fullscreen`. |
| `misc.exit_window_retains_fullscreen` | enum: `.disable`, `.enable`, `.only_when_grouped`, `.only_when_nongrouped` | Whether closing a fullscreen window makes the next focused window to be fullscreened. null: Hyprland's default, `disable`. |
| `misc.initial_workspace_tracking` | enum: `.disabled`, `.single_shot`, `.persistent` | Windows open on the workspace they were launched on: for the first window only (`single_shot`), or for every window of the process (`persistent`). null: Hyprland's default, `single_shot`. |
| `misc.initial_workspace_token_timeout` | `?i64` | The time in seconds a window has to open on its invoked workspace before the tracking token expires. 1..3600. null: Hyprland's default, `10`. |
| `misc.middle_click_paste` | `?bool` | Whether to enable middle-click-paste (aka primary selection). null: Hyprland's default, `true`. |
| `misc.render_unfocused_fps` | `?i64` | The maximum limit for renderunfocused windows' fps in the background. 1..120. null: Hyprland's default, `15`. |
| `misc.disable_xdg_env_checks` | `?bool` | Disable the warning if XDG environment is externally managed. null: Hyprland's default, `false`. |
| `misc.disable_hyprland_guiutils_check` | `?bool` | Disable the warning if hyprland-guiutils is missing. null: Hyprland's default, `false`. |
| `misc.disable_watchdog_warning` | `?bool` | Whether to disable the warning about not using start-hyprland. null: Hyprland's default, `false`. |
| `misc.lockdead_screen_delay` | `?i64` | The delay in ms after the lockdead screen appears. 0..5000. null: Hyprland's default, `1000`. |
| `misc.enable_anr_dialog` | `?bool` | Whether to enable the ANR (app not responding) dialog when your apps hang. null: Hyprland's default, `true`. |
| `misc.anr_missed_pings` | `?i64` | Number of missed pings before showing the ANR dialog. 1..20. null: Hyprland's default, `5`. |
| `misc.screencopy_force_8b` | `?bool` | Forces 8 bit screencopy. null: Hyprland's default, `true`. |
| `misc.disable_scale_notification` | `?bool` | Disables notification popup when a monitor fails to set a suitable scale. null: Hyprland's default, `false`. |
| `misc.size_limits_tiled` | `?bool` | Whether to apply minsize and maxsize rules to tiled windows. null: Hyprland's default, `false`. |
| `misc.bell_sound` | `?[]const u8` | Path to custom wav/ogg system bell. `none` or an empty string mute it. `default` uses the system's current one. null: Hyprland's default, `default`. |
| `misc.new_float_force_onscreen` | `?i64` | Whether new floating windows must be placed fully/partially on-screen. null: Hyprland's default, `2`. |
| `misc.float_force_onscreen` | `?i64` | Whether existing floating windows must remain fully/partially on-screen. null: Hyprland's default, `0`. |
| `layers.allow_new_top_layers_over_existing_fullscreen` | `?bool` | If false, newly mapped layers are not allowed to render over existing covering fullscreen window. Note that fullscreen hides all pre-existing top layers regardless of this setting. null: Hyprland's default, `true`. |
| `layers.layers_hog_keyboard_focus` | `?bool` | If true, will make keyboard-interactive layers keep their focus on mouse move. null: Hyprland's default, `true`. |
| `binds.pass_mouse_when_bound` | `?bool` | If disabled, will not pass the mouse events to apps / dragging windows around if a keybind has been triggered. null: Hyprland's default, `false`. |
| `binds.scroll_event_delay` | `?i64` | In ms, how many ms to wait after a scroll event to allow passing another one for the binds. 0..2000. null: Hyprland's default, `300`. |
| `binds.workspace_back_and_forth` | enum: `.disabled`, `.all_monitors`, `.per_monitor` | An attempt to switch to the currently focused workspace will instead switch to the previous workspace. null: Hyprland's default, `disabled`. |
| `binds.hide_special_on_workspace_change` | `?bool` | If enabled, changing the active workspace will hide the special workspace on the monitor. null: Hyprland's default, `false`. |
| `binds.allow_workspace_cycles` | `?bool` | If enabled, workspaces don't forget their previous workspace. null: Hyprland's default, `false`. |
| `binds.workspace_center_on` | enum: `.workspace`, `.last_window` | Whether switching workspaces centers the cursor on the workspace or on its last active window. null: Hyprland's default, `last_window`. |
| `binds.focus_preferred_method` | enum: `.history`, `.length` | How focuswindow/movewindow/etc with a direction pick a window: the most recently focused, or the longest shared edge. null: Hyprland's default, `history`. |
| `binds.ignore_group_lock` | `?bool` | If enabled, dispatchers like moveintogroup, moveoutofgroup and movewindoworgroup will ignore lock per group. null: Hyprland's default, `false`. |
| `binds.movefocus_cycles_fullscreen` | `?bool` | If enabled, when on a fullscreen window, movefocus will cycle fullscreen. null: Hyprland's default, `false`. |
| `binds.movefocus_cycles_groupfirst` | `?bool` | If enabled, when in a grouped window, movefocus will cycle windows in the groups first. null: Hyprland's default, `false`. |
| `binds.disable_keybind_grabbing` | `?bool` | If enabled, apps that request keybinds to be disabled will not be able to do so. null: Hyprland's default, `false`. |
| `binds.window_direction_monitor_fallback` | `?bool` | If enabled, moving a window or focus over the edge of a monitor with a direction will move it to the next monitor. null: Hyprland's default, `true`. |
| `binds.allow_pin_fullscreen` | `?bool` | Allows fullscreen to pinned windows, and restore their pinned status afterwards. null: Hyprland's default, `false`. |
| `binds.client_requested_fs_uses_layout_handler` | `?bool` | If false, client requested FS will use default FS handler. null: Hyprland's default, `true`. |
| `binds.drag_threshold` | `?i64` | Movement threshold in pixels for window dragging and c/g bind flags. 0 to disable. null: Hyprland's default, `0`. |
| `binds.drag_center_window` | `?bool` | If enabled, dragging a tiled or fullscreen window will center it on the cursor when it becomes floating. null: Hyprland's default, `true`. |
| `xwayland.enabled` | `?bool` | Allow running applications using X11. null: Hyprland's default, `true`. |
| `xwayland.use_nearest_neighbor` | `?bool` | Uses the nearest neighbor filtering for xwayland apps, making them pixelated rather than blurry. null: Hyprland's default, `true`. |
| `xwayland.force_zero_scaling` | `?bool` | Forces a scale of 1 on xwayland windows on scaled displays. null: Hyprland's default, `false`. |
| `xwayland.create_abstract_socket` | `?bool` | Create the abstract Unix domain socket for XWayland. null: Hyprland's default, `false`. |
| `opengl.nvidia_anti_flicker` | `?bool` | Reduces flickering on nvidia at the cost of possible frame drops on lower-end GPUs. null: Hyprland's default, `true`. |
| `render.direct_scanout` | enum: `.disable`, `.enable`, `.auto` | Enables direct scanout. null: Hyprland's default, `disable`. |
| `render.expand_undersized_textures` | `?bool` | Whether to expand textures that have not yet resized to be larger. null: Hyprland's default, `true`. |
| `render.xp_mode` | `?bool` | Disable back buffer and bottom layer rendering. null: Hyprland's default, `false`. |
| `render.ctm_animation` | enum: `.disable`, `.enable`, `.auto` | Whether to enable a fade animation for CTM changes. null: Hyprland's default, `auto`. |
| `render.cm_enabled` | `?bool` | Enable Color Management pipelines (requires restart to fully take effect). null: Hyprland's default, `true`. |
| `render.send_content_type` | `?bool` | Report content type to allow monitor profile autoswitch. null: Hyprland's default, `true`. |
| `render.cm_auto_hdr` | enum: `.disable`, `.hdr`, `.hdredid` | Auto-switch to hdr mode when fullscreen app is in hdr. null: Hyprland's default, `hdr`. |
| `render.new_render_scheduling` | `?bool` | Enable new render scheduling, which should improve FPS on underpowered devices. null: Hyprland's default, `false`. |
| `render.async_commit` | `?bool` | Submit eligible output commits asynchronously. null: Hyprland's default, `false`. |
| `render.non_shader_cm` | enum: `.disable`, `.always`, `.ondemand`, `.ignore` | Enable CM without shader. null: Hyprland's default, `ignore`. |
| `render.cm_sdr_eotf` | enum: `.default`, `.auto`, `.srgb`, `.gamma22`, `.gamma22force` | Default transfer function for displaying SDR apps. null: Hyprland's default, `default`. |
| `render.commit_timing_enabled` | `?bool` | Enable commit timing proto. Requires restart. null: Hyprland's default, `true`. |
| `render.icc_vcgt_enabled` | `?bool` | Enable sending VCGT ramps to KMS with ICC profiles. null: Hyprland's default, `true`. |
| `render.use_shader_blur_blend` | `?bool` | Use experimental blurred bg blending. null: Hyprland's default, `false`. |
| `render.use_fp16` | enum: `.disable`, `.enable`, `.auto` | Use experimental internal FP16 buffer. null: Hyprland's default, `auto`. |
| `render.keep_unmodified_copy` | enum: `.disable`, `.enable`, `.auto` | Keep umodified SDR frame copy for sreensharing. null: Hyprland's default, `auto`. |
| `render.non_shader_cm_interop` | enum: `.disable`, `.enable`, `.auto` | Non_shader_cm interaction with ctm proto (hyprsunset and similar). null: Hyprland's default, `auto`. |
| `render.fp16_sdr_tf` | enum: `.monitor`, `.linear` | Internal workbuffer transfer function for fp16 in SDR mode. null: Hyprland's default, `monitor`. |
| `render.not_shown_fifo_lock` | enum: `.always`, `.ignore_unfocused`, `.never` | Control fifo locking for not shown surfaces. always - use fifo lock for any surface, ignore_unfocused - ignore render_unfocused windows, never - skip locking invisible surfaces. null: Hyprland's default, `always`. |
| `cursor.invisible` | `?bool` | Don't render cursors. null: Hyprland's default, `false`. |
| `cursor.no_hardware_cursors` | enum: `.disabled`, `.enabled`, `.auto` | Disables hardware cursors. null: Hyprland's default, `auto`. |
| `cursor.no_break_fs_vrr` | enum: `.disable`, `.enable`, `.auto` | Disables scheduling new frames on cursor movement for fullscreen apps with VRR enabled. null: Hyprland's default, `auto`. |
| `cursor.min_refresh_rate` | `?i64` | Minimum refresh rate for cursor movement when no_break_fs_vrr is active. 10..500. null: Hyprland's default, `24`. |
| `cursor.hotspot_padding` | `?i64` | The padding, in logical px, between screen edges and the cursor. 0..20. null: Hyprland's default, `0`. |
| `cursor.inactive_timeout` | `?f64` | In seconds, after how many seconds of cursor's inactivity to hide it. Set to 0 for never. null: Hyprland's default, `0`. |
| `cursor.no_warps` | `?bool` | If true, will not warp the cursor in many cases. null: Hyprland's default, `false`. |
| `cursor.persistent_warps` | `?bool` | When a window is refocused, the cursor returns to its last position relative to that window. null: Hyprland's default, `false`. |
| `cursor.warp_on_change_workspace` | enum: `.disable`, `.enable`, `.force` | Move the cursor to the last focused window after changing the workspace. null: Hyprland's default, `disable`. |
| `cursor.warp_on_monitor_change` | enum: `.same_as_warp_on_change_workspace`, `.disable`, `.enable`, `.force` | Move the cursor to the last focused window when focusing a different monitor. null: Hyprland's default, `same_as_warp_on_change_workspace`. |
| `cursor.warp_on_toggle_special` | enum: `.disable`, `.enable`, `.force` | Move the cursor to the last focused window when toggling a special workspace. null: Hyprland's default, `disable`. |
| `cursor.default_monitor` | `?[]const u8` | The name of a default monitor for the cursor to be set to on startup. null: Hyprland's default, empty. |
| `cursor.zoom_factor` | `?f64` | The factor to zoom by around the cursor. 1 means no zoom. null: Hyprland's default, `1`. |
| `cursor.zoom_rigid` | `?bool` | Whether the zoom should follow the cursor rigidly or loosely. null: Hyprland's default, `false`. |
| `cursor.zoom_disable_aa` | `?bool` | If enabled, when zooming, no antialiasing will be used. null: Hyprland's default, `false`. |
| `cursor.zoom_detached_camera` | `?bool` | Detaches the camera from the mouse when zoomed in. null: Hyprland's default, `true`. |
| `cursor.enable_hyprcursor` | `?bool` | Whether to enable hyprcursor support. null: Hyprland's default, `true`. |
| `cursor.hide_on_key_press` | `?bool` | Hides the cursor when you press any key until the mouse is moved. null: Hyprland's default, `false`. |
| `cursor.hide_on_touch` | `?bool` | Hides the cursor when the last input was a touch input until a mouse input is done. null: Hyprland's default, `true`. |
| `cursor.hide_on_tablet` | `?bool` | Hides the cursor when the last input was a tablet input until a mouse input is done. null: Hyprland's default, `false`. |
| `cursor.use_cpu_buffer` | enum: `.disable`, `.enable`, `.auto` | Makes HW cursors use a CPU buffer. null: Hyprland's default, `auto`. |
| `cursor.sync_gsettings_theme` | `?bool` | Sync xcursor theme with gsettings. null: Hyprland's default, `true`. |
| `cursor.warp_back_after_non_mouse_input` | `?bool` | Warp the cursor back to where it was after using a non-mouse input to move it. null: Hyprland's default, `false`. |
| `ecosystem.no_update_news` | `?bool` | Disable the popup that shows up when you update hyprland to a new version. null: Hyprland's default, `false`. |
| `ecosystem.no_donation_nag` | `?bool` | Disable the popup that shows up twice a year encouraging to donate. null: Hyprland's default, `false`. |
| `ecosystem.enforce_permissions` | `?bool` | Whether to enable permission control. null: Hyprland's default, `false`. |
| `debug.overlay` | `?bool` | Print the debug performance overlay. null: Hyprland's default, `false`. |
| `debug.damage_blink` | `?bool` | Flash damaged areas. null: Hyprland's default, `false`. |
| `debug.gl_debugging` | `?bool` | Enable OpenGL debugging and error checking. null: Hyprland's default, `false`. |
| `debug.disable_logs` | `?bool` | Disable logging to a file. null: Hyprland's default, `true`. |
| `debug.disable_time` | `?bool` | Disables time logging. null: Hyprland's default, `true`. |
| `debug.damage_tracking` | enum: `.disable`, `.monitor`, `.full` | Redraw only the needed bits of the display. null: Hyprland's default, `full`. |
| `debug.enable_stdout_logs` | `?bool` | Enables logging to stdout. null: Hyprland's default, `false`. |
| `debug.manual_crash` | `?i64` | Set to 1 and then back to 0 to crash Hyprland. 0..1. null: Hyprland's default, `0`. |
| `debug.suppress_errors` | `?bool` | If true, do not display config file parsing errors. null: Hyprland's default, `false`. |
| `debug.disable_scale_checks` | `?bool` | Disables verification of the scale factors. null: Hyprland's default, `false`. |
| `debug.error_limit` | `?i64` | Limits the number of displayed config file parsing errors. 0..20. null: Hyprland's default, `5`. |
| `debug.error_position` | enum: `.top`, `.bottom` | Sets the position of the error bar. null: Hyprland's default, `top`. |
| `debug.colored_stdout_logs` | `?bool` | Enables colors in the stdout logs. null: Hyprland's default, `true`. |
| `debug.log_damage` | `?bool` | Enables logging the damage. null: Hyprland's default, `false`. |
| `debug.pass` | `?bool` | Enables render pass debugging. null: Hyprland's default, `false`. |
| `debug.full_cm_proto` | `?bool` | Claims support for all cm proto features (requires restart). null: Hyprland's default, `false`. |
| `debug.ds_handle_same_buffer` | `?bool` | Special case for DS with unmodified buffer. null: Hyprland's default, `true`. |
| `debug.ds_handle_same_buffer_fifo` | `?bool` | Special case for DS with unmodified buffer unlocks fifo. null: Hyprland's default, `true`. |
| `debug.render_solitary_wo_damage` | `?bool` | Render solitary window with empty damage. null: Hyprland's default, `false`. |
| `debug.vfr` | `?bool` | Controls the VFR status of Hyprland. Do not turn off unless debugging. null: Hyprland's default, `true`. |
| `debug.invalidate_buffers` | enum: `.disable`, `.enable` | Allow buffer invalidation. null: Hyprland's default, `enable`. |
| `debug.invalidate_fp16` | enum: `.disable`, `.enable`, `.auto` | Allow fp16 buffer invalidation. null: Hyprland's default, `enable`. |
| `layout.single_window_aspect_ratio` | `?values.Vec2` | If specified, whenever only a single window is open, it will be coerced into the specified aspect ratio. null: Hyprland's default, `2, 0, 0`. |
| `layout.single_window_aspect_ratio_tolerance` | `?f64` | Minimum distance for single_window_aspect_ratio to take effect. null: Hyprland's default, `0.1`. |
| `dwindle.force_split` | enum: `.follow_mouse`, `.left`, `.right` | Force a split direction for new windows. null: Hyprland's default, `follow_mouse`. |
| `dwindle.preserve_split` | `?bool` | If enabled, the split will not change regardless of what happens to the container. null: Hyprland's default, `false`. |
| `dwindle.smart_split` | `?bool` | If enabled, allows a more precise control over the window split direction based on the cursor's position. null: Hyprland's default, `false`. |
| `dwindle.smart_resizing` | `?bool` | If enabled, resizing direction will be determined by the mouse's position on the window. null: Hyprland's default, `true`. |
| `dwindle.permanent_direction_override` | `?bool` | If enabled, makes the preselect direction persist. null: Hyprland's default, `false`. |
| `dwindle.special_scale_factor` | `?f64` | Specifies the scale factor of windows on the special workspace. null: Hyprland's default, `1`. |
| `dwindle.split_width_multiplier` | `?f64` | Specifies the auto-split width multiplier. null: Hyprland's default, `1`. |
| `dwindle.use_active_for_splits` | `?bool` | Whether to prefer the active window or the mouse position for splits. null: Hyprland's default, `true`. |
| `dwindle.default_split_ratio` | `?f64` | The default split ratio on window open. null: Hyprland's default, `1`. |
| `dwindle.split_bias` | enum: `.directional`, `.current` | Specifies which window will receive the split ratio. null: Hyprland's default, `directional`. |
| `dwindle.precise_mouse_move` | `?bool` | If enabled, bindm movewindow will drop the window more precisely depending on where your mouse is. null: Hyprland's default, `false`. |
| `master.allow_small_split` | `?bool` | Enable adding additional master windows in a horizontal split style. null: Hyprland's default, `false`. |
| `master.special_scale_factor` | `?f64` | The scale of the special workspace windows. null: Hyprland's default, `1`. |
| `master.mfact` | `?f64` | The size as a percentage of the master window. null: Hyprland's default, `0.55`. |
| `master.new_status` | enum: `.master`, `.slave`, `.inherit` | `master`: new window becomes master; `slave`: new windows are added to slave stack; `inherit`: inherit from focused window. null: Hyprland's default, `slave`. |
| `master.new_on_top` | `?bool` | Whether a newly open window should be on the top of the stack. null: Hyprland's default, `false`. |
| `master.new_on_active` | enum: `.before`, `.after`, `.none` | `before`, `after`: place new window relative to the focused window; `none`: place new window according to new_on_top. null: Hyprland's default, `none`. |
| `master.orientation` | enum: `.left`, `.right`, `.top`, `.bottom`, `.center` | Default placement of the master area. null: Hyprland's default, `left`. |
| `master.slave_count_for_center_master` | `?i64` | When using orientation=center, make the master window centered only when at least this many slave windows are open. 0..10. null: Hyprland's default, `2`. |
| `master.center_master_fallback` | enum: `.left`, `.right`, `.top`, `.bottom` | Set fallback for center master when slaves are less than slave_count_for_center_master. null: Hyprland's default, `left`. |
| `master.center_ignores_reserved` | `?bool` | Centers the master window on monitor ignoring reserved areas. null: Hyprland's default, `false`. |
| `master.smart_resizing` | `?bool` | If enabled, resizing direction will be determined by the mouse's position on the window. null: Hyprland's default, `true`. |
| `master.drop_at_cursor` | `?bool` | When enabled, dragging and dropping windows will put them at the cursor position. null: Hyprland's default, `true`. |
| `master.always_keep_position` | `?bool` | Whether to keep the master window in its configured position when there are no slave windows. null: Hyprland's default, `false`. |
| `master.focus_master_on_close` | `?bool` | When enabled, closing a window focuses the master window. null: Hyprland's default, `false`. |
| `scrolling.fullscreen_on_one_column` | `?bool` | When enabled, a single column on a workspace will always span the entire screen. null: Hyprland's default, `true`. |
| `scrolling.column_width` | `?f64` | The default width of a column. null: Hyprland's default, `0.5`. |
| `scrolling.focus_fit_method` | enum: `.center`, `.fit` | When a column is focused, what method should be used to bring it into view. null: Hyprland's default, `fit`. |
| `scrolling.follow_focus` | enum: `.disabled`, `.click`, `.soft` | Whether focusing a window moves the scrolling tape: never, also always on a mouse click (`click`), or only when focus moves (`soft`). null: Hyprland's default, `click`. |
| `scrolling.follow_min_visible` | `?f64` | When a window is focused, require that at least a given fraction of it is visible for focus to follow. null: Hyprland's default, `0.4`. |
| `scrolling.explicit_column_widths` | `?[]const u8` | A comma-separated list of preconfigured widths for colresize +conf/-conf. null: Hyprland's default, `0.333, 0.5, 0.667, 1.0`. |
| `scrolling.direction` | enum: `.left`, `.right`, `.up`, `.down` | Direction in which new windows appear and the layout scrolls. null: Hyprland's default, `right`. |
| `scrolling.wrap_focus` | `?bool` | Determines if column focus wraps around. null: Hyprland's default, `true`. |
| `scrolling.wrap_swapcol` | `?bool` | Determines if column movement wraps around. null: Hyprland's default, `true`. |
| `experimental.wp_cm_1_2` | `?bool` | Allow wp-cm-v1 version 2. null: Hyprland's default, `true`. |
| `input_capture.capture_modifiers` | `?bool` | If enabled, modifiers are also captured and sent to the program. null: Hyprland's default, `false`. |
| `input_capture.enforce_barriers` | `?bool` | If enabled, throw a wayland error when a invalid barrier is received. null: Hyprland's default, `true`. |
| `quirks.prefer_hdr` | enum: `.disable`, `.enable`, `.gamescope_only` | Prefer HDR mode. null: Hyprland's default, `disable`. |
| `quirks.skip_non_kms_dmabuf_formats` | `?bool` | Do not report dmabuf formats which cannot be imported into KMS. null: Hyprland's default, `false`. |
