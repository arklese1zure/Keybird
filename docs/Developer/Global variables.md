# Global variables
> Keybird provides some standard variables for a variety of situations.
---
# System-wide changes
`screenSizeChanged`
- Returns `TRUE` if the screen size is different from the last saved one.
- Useful if you want, for example, to reset window positions.
---
# Program-wide changes
`GuiLocker.isLocked`
- Returns `TRUE` if the main GUI is currently in a locked state.
---
# Gui interactions
`leftclickguihwnd`
- Returns the HWND of the last gui that was left-clicked.
- Only works on guis belonging to the script.
- See also: `Hooks > Plugin_Main_LeftClick`
---
# Settings gui
`settings.ahk` defines a handful of globals that describe the settings GUI's tab geometry (the sidebar ListView and the safe area inside a tab where your controls can go).
You can use these instead of hardcoded x/y/w/h numbers when building a settings tab.
> **Rationale**
> Inside your own `BuildSettingsTab()`, relative positioning (`xp`, `yp`, `x+`, `y+`) works exactly like anywhere else in AHK *after* your first control. You can chain off your own elements, and it behaves as expected.
> The problem is your *first* control. The settings tabs are built after the sidebar, so whatever control was last added is what `xp`/`yp` would inherit from if you started with relative positioning.
> to fix this, anchor your first control with an absolute position built from the constants below, then you can build relatively from there as normal.
## Constants
- `settings_tab_x0` / `settings_tab_y0`: Where your tab's content should start. Use these for your **first** control's `x`/`y`; chain everything after it with `xp`/`yp`/`x+`/`y+` as usual.
- `settings_sidebar_w`: Width of the tab-switcher ListView on the left.
- `settings_tab_gap`: Gap between the sidebar and the tab control.
- `settings_tab3_x` / `settings_tab3_y`: The tab control's own top-left corner.
- `settings_tab3_w` / `settings_tab3_h`: The tab control's own size.
- `settings_tab_w` / `settings_tab_h`: Space that spans the entirety of the tab. Use for a full-width or full-height control.
## Examples
Example of a basic settings panel with some elements:

```ahk
static BuildSettingsTab(*) {
	; First control (using the shared constants).
	SettingsGui.Add("GroupBox", "x" settings_tab_x0 " y" settings_tab_y0 " w219 h224", "Example settings")

	; Everything after: normal relative positioning, chained off the control above.
	this.ExampleCheckbox := SettingsGui.Add("CheckBox", "xp+8 yp+20 w200", "Enable example behavior")
	this.ExampleDropdown := SettingsGui.Add("DropDownList", "xp y+8 w200", ["Option A", "Option B"])
}
```

A tab that's just one control filling the whole space:

```ahk
static BuildSettingsTab(*) {
	this.LogView := SettingsGui.Add("Edit", "x" settings_tab_x0 " y" settings_tab_y0 " w" settings_tab_w " h" settings_tab_h " ReadOnly")
}
```