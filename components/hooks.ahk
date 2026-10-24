
;		=========================================================================
;		|||||						KeyBird - Hooks							|||||
;		=========================================================================

;## Register hooks ##############################################################
;== Initialize arrays ===========================================================
InitializeHooks(*) { ; Initialize arrays.
	;== Launch ==================================================================
	global Main_OnStartUp					:= []
	global Main_LoadSettings				:= []
	;== Main Gui=================================================================
	;-- Events ------------------------------------------------------------------
	global Main_LeftClick					:= []
	global Main_RightClick					:= []
	global Main_OnLock						:= []
	global Main_OnUnlock					:= []
	global Main_OnExit						:= []
	;-- Gui ---------------------------------------------------------------------
	global Main_AddTab						:= []
	global Main_ActiveTabs					:= [] ; Subset of Main_AddTab with only successfully built tabs.
	global ArrMainMenuItems					:= []
	global MenuItemLabels					:= Map() ; MenuObj -> Map(itemKey -> current label). See menus.ahk.
	;== Settings ================================================================
	;-- Events ------------------------------------------------------------------
	global Settings_SaveSettings			:= []
	;-- Gui ---------------------------------------------------------------------
	global Settings_AddTab					:= []
	global Settings_ActiveTabs				:= [] ; Subset of Settings_AddTab with only successfully built tabs. See Main_ActiveTabs.
}

;## Hook dispatch ###############################################################
; Everything that runs registered callbacks goes through these functions
; Error handling, logging and throttling are managed here now.
; Usage:
;   Hooks_Add(hooks, fn, entryName, label)    Validate and register a callback in a hook array.
;   Hooks_Run(hooks, label, opts)             Call every callback in a hook array. Returns true if all succeeded.
;   Hooks_Call(fn, label, source, opts)       Call a single callback (e.g. a tab's OnSelect).
;	opts is an optional object, and every field is optional:
	;   level        "WARN" (default), "INFO" or "ERROR". Level used when logging a failure. WARN shows a message
	;                box for the first warning of the session; INFO is log-only (used by exit hooks).
	;   throttle     true = an identical failure of the same hook is logged once per session. For hooks that fire
	;                constantly (clicks, tab switches).
	;   failOnFalse  true = an explicit `return false` counts as a failure, not only an exception. For save-style hooks.

Hooks_Add(hooks, fn, entryName, label) { ; Register a callback in a hook array. Returns false (and logs) if it can't be called.
	if !HasMethod(fn, "Call") {
		Log(label " was not registered: the callback isn't callable. Pass the function itself (MyFunc), not its result (MyFunc()).", "WARN", entryName)
		return false
	}
	hooks.Push({ Callback: fn, Name: entryName })
	return true
}

Hooks_Run(hooks, label, opts := "") { ; Call every callback in a hook array. Returns true only if all of them succeeded.
	ok := true
	for _, entry in hooks {
		if !Hooks_Call(entry.Callback, label, entry.Name, opts)
			ok := false
	}
	return ok
}

Hooks_Call(fn, label, source := "", opts := "") { ; Call one hook callback safely. Returns true if it succeeded (or if there was nothing to call).
	static lastFailure := Map() ; "label|source" -> last message logged, used by the throttle option.
	level := "WARN", throttle := false, failOnFalse := false
	if IsObject(opts) {
		level       := opts.HasProp("level")       ? opts.level       : level
		throttle    := opts.HasProp("throttle")    ? opts.throttle    : throttle
		failOnFalse := opts.HasProp("failOnFalse") ? opts.failOnFalse : failOnFalse
	}
	if (fn = "") ; Empty optional slot, e.g. a tab registered without an OnSelect function.
		return true
	msg := ""
	try {
		result := fn.Call()
		if (failOnFalse && result == false) ; Only an explicit false counts. Returning nothing (empty string) is success.
			msg := label " reported a failure."
	} catch as Err {
		msg := label " failed: " Hooks_ErrorText(Err)
	}
	if (msg = "")
		return true
	key := label "|" source
	if (!throttle || !lastFailure.Has(key) || lastFailure[key] != msg) {
		lastFailure[key] := msg
		Log(msg, level, source)
	}
	return false
}

Hooks_ErrorText(Err) { ; Readable text for whatever was thrown, including non-Error values (throw "text").
	if !IsObject(Err)
		return String(Err)
	text := Err.HasProp("Message") ? Err.Message : "unknown error"
	if (Err.HasProp("Extra") && Err.Extra != "")
		text .= " (" Err.Extra ")"
	where := (Err.HasProp("What") && Err.What != "") ? Err.What : ""
	if (Err.HasProp("File") && Err.HasProp("Line")) {
		SplitPath(Err.File, &fileName)
		where .= (where != "" ? ", " : "") fileName ":" Err.Line
	}
	return text (where != "" ? " [" where "]" : "")
}

;## Hook functions ##############################################################
;== Launch ======================================================================
;-- Script startup --------------------------------------------------------------
Plugin_Main_OnStartUp(fn, entryName) { ; Register callbacks that trigger on startup.
	Hooks_Add(Main_OnStartUp, fn, entryName, "Startup hook")
}

OnStartUp(*) { ; Registered functions will trigger before most of the script.
	Hooks_Run(Main_OnStartUp, "Startup hook")
}

;-- Load settings ---------------------------------------------------------------
Plugin_Main_LoadSettings(fn, entryName) { ; Read settings on startup.
	Hooks_Add(Main_LoadSettings, fn, entryName, "Addon settings load")
}

ReadAddonSettings(*) { ; Read settings on startup.
    Hooks_Run(Main_LoadSettings, "Addon settings load")
}

;== Main Gui ====================================================================
;-- Main menu -------------------------------------------------------------------
Plugin_AddMainMenuItem(fn, entryName := "", pluginKey := "") { ; Group new entries in objects, then add to an array.
	; fn			- The function to call when the entry is selected.
	; entryName		- Display text. Works as a fallback.
	; pluginKey		- Internal identifier. Should match both your addon's PluginKey class
	;				  property and your translation ini file's section name.
    ArrMainMenuItems.Push({ Callback: fn, Name: entryName, PluginKey: pluginKey })
}

_ResolveMenuItemName(pluginObject) {
; Return the best available display name for a main-menu-item registration object.
; Lookup order (mirrors _ResolveTabName):
;   1. "<PluginKey>.menu_item_name" in the loaded string map — translated name
;   2. pluginObject.Name                                     — registered fallback string
;   3. pluginObject.PluginKey                                — last resort, always non-empty if set
	if pluginObject.PluginKey != "" {
		key := pluginObject.PluginKey ".menu_item_name"
		if PluginBase.Strings.Has(key)
			return PluginBase.Strings[key]
	}
	if pluginObject.Name != ""
		return pluginObject.Name
	if pluginObject.PluginKey != ""
		return pluginObject.PluginKey
	return "?"
}

BuildMainMenuItems(*) { ; Add entries to the main menu.
	; Plugin_AddMainMenuItem runs from __New(), which fires before .LoadLanguage() has loaded strings.
	; BuildMainMenuItems() runs during BuildMainGuiMenus() (after LoadLanguage) so menu translations can be done.
	for index, pluginObject in ArrMainMenuItems {
		try {
			itemKey := (pluginObject.PluginKey != "") ? pluginObject.PluginKey : "menuitem_" index
			MenuAdd(AddonsMenu, itemKey, _ResolveMenuItemName(pluginObject), pluginObject.Callback)
		} catch as Err {
			Log("Could not add menu item: " Err.Message, "WARN", pluginObject.Name)
		}
	}
}

;-- Tabs ------------------------------------------------------------------------
Plugin_Main_AddTab(fn, tabName := "", tabIcon := "\res\ico\mimetypes\text-x-generic.ico", onSelectFn := "", onRightClickFn := "", pluginKey := "") {
	; Register a tab for the main GUI.
	; fn						- The actual function that builds the gui contents.
	; tabName					- Display name. There's two ways to use this:
	; tabIcon (optional)		- Add an icon for your tab. Needs to be a string with the relative path to the icon.
	; pluginKey					- Internal identifier. Should match PluginKey class and translation ini section name.
	; onSelectFn (optional)		- Add a function that gets called every time the user switches to this tab (e.g. for refreshing).
	; onRightClickFn (optional)	- Add a function that gets called when the user right-clicks this tab's row in the sidebar ListView.
	Main_AddTab.Push({ Callback: fn, Name: tabName, Icon: tabIcon, OnSelect: onSelectFn, OnRightClick: onRightClickFn, PluginKey: pluginKey })
}

_ResolveTabName(pluginObject) {
; Return the best available display name for a tab registration object.
; Lookup order:
;   1. "<PluginKey>.tab_name" in the loaded string map  — translated name
;   2. pluginObject.Name                                 — registered fallback string
;   3. pluginObject.PluginKey                            — last resort, always non-empty if set
	if pluginObject.PluginKey != "" {
		key := pluginObject.PluginKey ".tab_name"
		if PluginBase.Strings.Has(key)
			return PluginBase.Strings[key]
	}
	if pluginObject.Name != ""
		return pluginObject.Name
	if pluginObject.PluginKey != ""
		return pluginObject.PluginKey
	return "?"
}

_ResolveAddonDisplayName(pluginKey) {
; Return the best available human-readable name for an addon, given its bare
; PluginKey - unlike _ResolveMenuItemName/_ResolveTabName, this doesn't need a
; registration object, since not every addon registers a menu item or tab
; (e.g. a docs-only contribution).
; Lookup order:
;   1. "<PluginKey>.display_name"   in the loaded string map — purpose-built
;   2. "<PluginKey>.menu_item_name" in the loaded string map — reuses the
;      addon's existing menu label, if it has one, before giving up
;   3. pluginKey                    — last resort, the raw folder name
	if pluginKey != "" {
		key := pluginKey ".display_name"
		if PluginBase.Strings.Has(key)
			return PluginBase.Strings[key]
		key := pluginKey ".menu_item_name"
		if PluginBase.Strings.Has(key)
			return PluginBase.Strings[key]
	}
	return pluginKey
}

BuildAddonTabs(*) {
	; Builds the tab icon list and the tab pages together, so both agree which addons succeeded.
	; Main_ActiveTabs ends up holding only the tabs that built cleanly, in the order they were added.
	; Each entry pushed into Main_ActiveTabs is a copy of the registration object with .Name
	; replaced by the resolved translated display name, so all sites (window title, tooltip,
	; log messages) can use .Name directly without knowing about the translation system.
	global mainGui, mainTabsLV, mainTabs, Main_AddTab, Main_ActiveTabs, iconsDir
	Main_ActiveTabs := []

	tabIcons := IL_Create(10, 10, true)

	for index, pluginObject in Main_AddTab {
		; Snapshot the Gui's controls before running the addon's callback, so we know exactly
		; which controls it added, and remove them if something fails partway through.
		controlsBefore := []
		for hwnd, ctrl in mainGui ; mainGui is enumerable over its controls.
			controlsBefore.Push(ctrl)

		tabPageIndex := Main_ActiveTabs.Length + 1 ; The tab page number this addon WOULD occupy if it succeeds.

		try {
			mainTabs.Add([tabPageIndex]) ; Tentatively add a tab page.
			mainTabs.UseTab(tabPageIndex) ; Use the tab.
			pluginObject.Callback.Call() ; Call the function for building tab contents.
			; Attempt the icon load once we know the tab's built successfully,
			; so a missing/bad icon alone doesn't waste a tab slot, but a build failure still
			; rolls back below even if the icon would have loaded fine.
			newIconIndex := Main_ActiveTabs.Length + 1 ; Position this tab will occupy in tabIcons/mainTabsLV.
			; Check if icon file actually exists, otherwise add a default icon to the tab.
			if (!FileExist(A_WorkingDir . pluginObject.Icon)) {
				Log("Could not load tab icon, using default.", "WARN", pluginObject.Name)
				IL_Add(tabIcons, iconsDir "\mimetypes\text-x-generic.ico") ; Safe fallback icon.
			}
			else
			; Check if the icon file is valid, otherwise add a default icon instead.
			try {
				IL_Add(tabIcons, A_WorkingDir . pluginObject.Icon)
			} catch as IconErr {
				Log("Could not load tab icon, using default: " IconErr.Message, "WARN", pluginObject.Name)
				IL_Add(tabIcons, iconsDir "\mimetypes\text-x-generic.ico") ; Safe fallback icon.
			}

			mainTabsLV.Add("Icon" . newIconIndex, "") ; Add this tab's row to the switcher.
			; Resolve the translated display name. LoadLanguage() has already run by the
			; time BuildAddonTabs() is called, so the string map is fully populated.
			; We store a shallow copy of the registration object with .Name replaced so that
			; every downstream read site (title bar, tooltip, log) just uses .Name directly.
			activeEntry := { Callback: pluginObject.Callback, Name: _ResolveTabName(pluginObject),
				Icon: pluginObject.Icon, OnSelect: pluginObject.OnSelect,
				OnRightClick: pluginObject.OnRightClick, PluginKey: pluginObject.PluginKey }
			Main_ActiveTabs.Push(activeEntry)

		} catch as Err {
			; Tab build failed. Remove any controls this addon managed to add before failing,
			; then delete the empty tab page so it never appears.
			Log("Tab failed to build and was skipped: " Err.Message, "WARN", pluginObject.Name)

			for hwnd, ctrl in mainGui {
				if !HasControl(controlsBefore, ctrl) {
					try ctrl.Destroy()
				}
			}
			try mainTabs.Delete(tabPageIndex)
			try mainTabs.UseTab() ; Don't leave tab selection pointed at the page we just deleted.
		}
	}

	mainTabsLV.SetImageList(tabIcons)
}

HasControl(snapshot, ctrl) { ; Helper: checks whether a control reference is present in a "snapshot" array.
	; (Controls are objects, so plain ArrayContains' "=" comparison works fine for reference equality here.)
	for _, c in snapshot
		if (c = ctrl)
			return true
	return false
}

TabLVRightClick(ctrl, item, *) { ; Called when the user right-clicks a row in the sidebar tab ListView.
	; item is the 1-based row index of the right-clicked item (0 if clicking empty space).
	global Main_ActiveTabs
	if !item ; Right-click on empty space — no tab to act on.
		return
	if !Main_ActiveTabs.Has(item)
		return
	tabObj := Main_ActiveTabs[item]
	Hooks_Call(tabObj.OnRightClick, "Tab right-click hook", tabObj.Name, {throttle: true})
}

;-- Events ----------------------------------------------------------------------
Plugin_Main_LeftClick(fn, entryName) { ; Trigger actions when the gui is left-clicked.
	Hooks_Add(Main_LeftClick, fn, entryName, "Left-click hook")
}

OnGuiLeftClick(*) {
	Hooks_Run(Main_LeftClick, "Left-click hook", {throttle: true})
}

Plugin_Main_RightClick(fn, entryName) { ; Trigger actions when the gui is left-clicked.
	Hooks_Add(Main_RightClick, fn, entryName, "Right-click hook")
}

OnGuiRightClick(*) {
	Hooks_Run(Main_RightClick, "Right-click hook", {throttle: true})
}

Plugin_Main_OnExit(fn, entryName) { ; Trigger when the program exits or reloads.
	Hooks_Add(Main_OnExit, fn, entryName, "Exit hook")
}

OnMainGuiExit(*) {
	; INFO = log only, no MsgBox: the user is already exiting and shouldn't be blocked by a dialog here.
	Hooks_Run(Main_OnExit, "Exit hook", {level: "INFO"})
}

Plugin_Main_OnLock(fn, entryName) { ; Trigger when the app gets locked. Pause anything that could interfere with whoever uses this computer next: timers, clipboard/window monitors, open popups.
	Hooks_Add(Main_OnLock, fn, entryName, "Lock hook")
}

OnMainGuiLock(*) {
	Hooks_Run(Main_OnLock, "Lock hook")
}

Plugin_Main_OnUnlock(fn, entryName) { ; Trigger after a successful unlock. Undo whatever the lock hook paused.
	Hooks_Add(Main_OnUnlock, fn, entryName, "Unlock hook")
}

OnMainGuiUnlock(*) {
	Hooks_Run(Main_OnUnlock, "Unlock hook")
}

;== Settings Gui ================================================================
;-- Gui -------------------------------------------------------------------------
Plugin_Settings_AddTab(fn, entryName := "", pluginKey := "") { ; Add tabs in the settings gui.
	; pluginKey — stable identifier used by LaunchSettings() to open this tab by name.
	;             Defaults to entryName if not supplied, but should be a stable snake_case key
	;             (e.g. "clipboard") rather than a translated display string.
	; Check for duplicate keys/names to catch accidental double-registration.
	resolvedKey := (pluginKey != "") ? pluginKey : entryName
	for _, existing in Settings_AddTab {
		existingKey := existing.HasProp("PluginKey") ? existing.PluginKey : existing.Name
		if existingKey = resolvedKey && resolvedKey != "" {
			Log("A settings tab with key '" resolvedKey "' is already registered and was not added again.", "WARN", entryName)
			return
		}
	}
	Settings_AddTab.Push({ Callback: fn, Name: entryName, PluginKey: resolvedKey })
}

BuildAddonSettingsTabs(*) {
	; Builds the settings tab pages and the sidebar ListView rows together, like BuildAddonTabs()
	; for the main GUI, and for the same reason.
	; Addons don't need to call settingsGuiTabs.Add()/.UseTab(). This function handles that,
	; then calls the callback to fill in controls on the active page.
	global SettingsGui, settingsGuiTabs, settingsTabsLV, Settings_AddTab, Settings_ActiveTabs
	Settings_ActiveTabs := []

	for index, pluginObject in Settings_AddTab {
		; Snapshot the Gui's controls before running the addon's callback, so we know exactly
		; which controls (if any) it added, and can remove them if it fails partway through.
		controlsBefore := []
		for hwnd, ctrl in SettingsGui
			controlsBefore.Push(ctrl)

		tabPageIndex := Settings_ActiveTabs.Length + 3 ; +3: the two built-in tabs occupy slots 1 and 2.

		try {
			tabName := _ResolveTabName(pluginObject) ; Shared with the main GUI's tab system -- same lookup order.
			settingsGuiTabs.Add([tabName]) ; Tentatively add a tab page.
			settingsGuiTabs.UseTab(tabPageIndex) ; Use the tab.
			pluginObject.Callback.Call() ; Call the function for building tab contents.

			settingsTabsLV.Add(, tabName) ; Add this tab's row to the sidebar switcher.

			Settings_ActiveTabs.Push({ Callback: pluginObject.Callback, Name: tabName, PluginKey: pluginObject.PluginKey })

		} catch as Err {
			; The build failed. Remove any controls this addon managed to add before failing,
			; then delete the empty tab page so it never appears and no slot is wasted on it.
			Log("Settings tab failed to build and was skipped: " Hooks_ErrorText(Err), "WARN", pluginObject.Name)

			for hwnd, ctrl in SettingsGui {
				if !HasControl(controlsBefore, ctrl) {
					try ctrl.Destroy()
				}
			}
			try settingsGuiTabs.Delete(tabPageIndex)
			try settingsGuiTabs.UseTab() ; Don't leave tab selection pointed at the page we just deleted.
		}
	}

	settingsTabsLV.ModifyCol(1, "AutoHdr") ; Widen the column to fit the longest tab name added, built-ins included.
}

SettingsTabSwitcher(*) { ; Maps settingsTabsLV row selection to the settingsGuiTabs page.
; Built-in tabs are always added to settingsGuiTabs and settingsTabsLV in the same order
; (see BuildSettingsGuiTabs and BuildAddonSettingsTabs).
	global settingsTabsLV, settingsGuiTabs
	row := settingsTabsLV.GetNext()
	if !row ; No row selected.
		return
	settingsGuiTabs.Choose(row)
	settingsTabsLV.Redraw()
}

SettingsTabNameTooltip(*) { ; Shows a tab's full name on focus (used in case a tab's name is too wide for the sidebar column).
	global settingsTabsLV
	row := settingsTabsLV.GetNext()
	if !row
		return
	ToolTip settingsTabsLV.GetText(row)
	SetTimer () => ToolTip(), -500
}

;-- Events ----------------------------------------------------------------------
LaunchSettings(tab := 1, *) {
; Open the settings GUI and navigate to a specific tab.
;
; tab can be:
;   1 (integer)    — open to the first (main) tab; the default.
;   "main"         — built-in main settings tab (index 1).
;   "addons"       — built-in addons tab (index 2).
;   "clipboard"    — any PluginKey registered via Plugin_Settings_AddTab;
;                    resolved to its actual tab index at open time.
;   2, 3, … (int)  — direct tab index; accepted but fragile if addons change.
;
; The two built-in tabs are always at indices 1 and 2. Addon tabs start at 3
; in the order they were registered via Plugin_Settings_AddTab.
	BuildSettingsGui()

	; Resolve tab identifier to a numeric index for settingsGuiTabs.Choose().
	tabIndex := _ResolveSettingsTab(tab)
	if tabIndex > 1 {
		try {
			settingsGuiTabs.Choose(tabIndex)
			settingsTabsLV.Modify(tabIndex, "Select Focus") ; Keep the visible sidebar in sync with the jump.
			settingsTabsLV.Redraw()
		} catch as Err
			Log("LaunchSettings: could not navigate to tab '" tab "': " Err.Message, "WARN", "LaunchSettings")
	}
}

_ResolveSettingsTab(tab) {
; Returns the 1-based tab index for a given tab identifier.
; Built-in tabs: "main"=1, "addons"=2. Addon tabs: searched by PluginKey starting at index 3.
	if IsInteger(tab)
		return tab  ; Caller passed a numeric index directly.
	if tab = "main"
		return 1
	if tab = "addons"
		return 2
	; Search successfully-built addon settings tabs by PluginKey (Settings_ActiveTabs, not the raw
	; Settings_AddTab registration list -- a tab that failed to build and was skipped by
	; BuildAddonSettingsTabs() doesn't occupy a page, so it must not occupy an index here either).
	; Built-in tabs occupy slots 1 and 2, so addon tabs start at index 3.
	for i, pluginObject in Settings_ActiveTabs {
		key := pluginObject.HasProp("PluginKey") ? pluginObject.PluginKey : pluginObject.Name
		if key = tab
			return i + 2 ; +2 because the two built-in tabs come first.
	}
	Log("LaunchSettings: no settings tab found for key '" tab "', opening to main tab.", "WARN", "LaunchSettings")
	return 1
}

;-- Functions -------------------------------------------------------------------
Plugin_Settings_SaveSettings(fn, entryName := "") { ; Trigger when the save button in the settings gui is pressed.
	Hooks_Add(Settings_SaveSettings, fn, entryName, "Addon settings save")
}

SaveAddonSettings(*) { ; Run each addon's settings save routine (if any).
	return Hooks_Run(Settings_SaveSettings, "Addon settings save", {failOnFalse: true})
}

;## Error messages ##############################################################
Hooks_Error_DuplicateFunction(fn) {
	Log("A function named " fn " is already registered and was not added again. Please rename it.", "WARN")
	return
}

