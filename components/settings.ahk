
;		=========================================================================
;		|||||					Keybird	- Settings Gui						|||||
;		=========================================================================

;## Setup #######################################################################
#Include %A_ScriptDir%\lib\JSON.ahk

global loadedAddonsFile		:= A_WorkingDir "\userprofile\LoadedAddons.ahk"

;-- Settings tab layout ----------------------------------------------------------
; Helper variables so developers can add gui elements inside the settings tab easier.
; Future changes to the settings UI layout will respect any addon positioning.
global settings_sidebar_w		:= 130	; Width of the tab-switcher ListView.
global settings_tab_gap			:= 4	; Gap between the sidebar and the tab control.
global settings_tab_x0			:= 2 + settings_sidebar_w + settings_tab_gap + 6	; Left edge for tab content.
global settings_tab_y0			:= 10	; Top edge for tab content, below the hidden tab strip.
global settings_tab3_w			:= 476	; Tab's width.
global settings_tab3_h			:= 328	; Tab's height.
global settings_tab_margin_x	:= 6	; Left/right inset from Tab3's own edges (matches how settings_tab_x0 was derived).
global settings_tab_margin_bot	:= 6	; Bottom inset.
global settings_tab_w 			:= settings_tab3_w - settings_tab_margin_x * 2
global settings_tab_h 			:= settings_tab3_h - (settings_tab_y0 - 2) - settings_tab_margin_bot	; "- 2" is Tab3's own y.

;## Build settings gui ##########################################################
BuildSettingsGui(*) {
	global mainGui, startInSettingsTab
	global SettingsGui := Gui()
	SettingsGui.Opt("+owndialogs -alwaysontop")
	mainGUI.Opt("+Disabled") ; Disable main GUI.
	BuildSettingsGuiTabs()
	BuildAddonSettingsTabs() ; Hook for adding additional panels to the settings Gui.
	SettingsGui.OnEvent("Close", SettingsGuiClose)
	SettingsGui.OnEvent("Escape", SettingsGuiEscape)
	SettingsGui.Title := "Keybird — " T("settings_title")
	SettingsGui.Show("w614 h355")
}

;## Tab contents ################################################################
BuildSettingsGuiTabs(*) { ; Build the panels where settings reside.
	global mainGui, settingsGui
	;-- Tab switcher ------------------------------------------------------------
	; Similar to BuildMainGuiTabs(). The native header is hidden and a plain-text ListView works as a tab switcher.
	global settingsTabsLV := SettingsGui.Add("ListView",	"x2 y2 w130 h328 -Hdr -Multi",	["Tabs"])
		settingsTabsLV.OnEvent("ItemSelect", SettingsTabSwitcher)
		settingsTabsLV.OnEvent("ItemFocus", SettingsTabNameTooltip)
	; Hacky way to hide the tab bar. See autohotkey.com/boards/viewtopic.php?t=140644.
	global settingsGuiTabs := SettingsGui.Add("Tab3", "x132 y-4 h334 w480 -Tabstop -Wrap Buttons", [T("tab_settings_main"), T("tab_settings_addons")])	
		SendMessage(0x1329, 0, (1)|(1<<16), , settingsGuiTabs.hwnd) ; Hide tab headers. Width = 0, height = 1 (cannot be zero)
	; Add first two "tabs" in the listview, along with their translation.
	settingsTabsLV.Add(, T("tab_settings_main"))
	settingsTabsLV.Add(, T("tab_settings_addons"))
	settingsTabsLV.Modify(1, "Select Focus") ; Land on the Main tab's row by default.
	settingsGuiTabs.UseTab(1) ;== Main Tab ======================================
		;-- UI settings ---------------------------------------------------------
		SettingsGui.Add("GroupBox",								"x142 y30 w219 h224",									T("gb_settings_gui"))
		global ChkShowControls := SettingsGui.Add("CheckBox",	"x150 y45 w206 h23 Checked" gui_main_showcontrols,		T("chkShowControls"))
		global ChkTrayIcon := SettingsGui.Add("CheckBox",		"x150 y+1 w206 h23 Checked" tray_iconenabled,			T("chkTrayIcon"))
		global ChkShowInTaskbar := SettingsGui.Add("CheckBox",	"x150 y+1 w206 h23 Checked" gui_main_showintaskbar,		T("chkShowInTaskbar")) ; Show icon in taskbar
		global ChkSaveScreenPos := SettingsGui.Add("CheckBox",	"x150 y+1 w207 h23 Checked" gui_main_rememberscreenpos,	T("chkSaveScreenPos")) ; Remember position on screen
		global ChkDragWindows := SettingsGui.Add("CheckBox",	"x150 y+1 w207 h23 Checked" window_main_draggable,		T("chkDragWindows")) ; Drag window from anywhere
		SettingsGui.Add("Text", "x150 y+10 w206", T("text_settings_inactiveopacity"))
		global SliderInactiveOpacity := SettingsGui.Add("Slider", "x150 y+4 w160 Range20-255 NoTicks", window_main_inactiveopacity)
			SliderInactiveOpacity.OnEvent("Change", UpdateInactiveOpacityLabel)
		global TxtInactiveOpacityPct := SettingsGui.Add("Text", "x+8 yp+6 w40", Round(window_main_inactiveopacity/255*100) "%")
		;-- Startup settings ----------------------------------------------------
		SettingsGui.Add("GroupBox",								"x366 y30 w239 h124",									T("gb_settings_startup")) ; Startup settings
		global ChkDisableSleep := SettingsGui.Add("CheckBox",	"x374 y45 w228 h23 Checked" startup_disablestandby,		T("chkDisableSleep")) ; Disable sleep
		global ChkStartHidden := SettingsGui.Add("CheckBox",	"x374 y+1 w226 h23 Checked" startup_mainguihidden,		T("chkStartHidden")) ; Hidden main window
		global ChkCheckUpdates := SettingsGui.Add("CheckBox",	"x374 y+1 w226 h23 Checked" update_autocheck,			T("chkCheckUpdates")) ; Automatic update checks
		;-- Language settings ---------------------------------------------------
		SettingsGui.Add("GroupBox",								"x366 y160 w239 h94",									T("gb_settings_lang")) ; Language
		global DDLLanguage := SettingsGui.Add("DropDownList",	"x376 y175 w220",										BuildLanguageList())
			DDLLanguage.OnEvent("Change",  ReadLanguageMeta)
		SettingsGui.Add("Text",									"x376 y200",											T("gb_settings_lang") ":")
		global LanguageMetaBox := SettingsGui.Add("Text",		"x+5 y200 w180 cgray")
			DDLLanguage.Choose(active_language)
			ReadLanguageMeta()
		;-- Sidebar background --------------------------------------------------
		SettingsGui.Add("GroupBox", "x" settings_tab_x0 " y258 w" settings_tab_w " h56", T("gb_settings_sidebarbg"))
		global SidebarBgNames := FillSidebarBgList() ; parallel to the dropdown; index 1 = "" (no background).
		ddlBgLabels := []
		for _, fileName in SidebarBgNames
			ddlBgLabels.Push(fileName = "" ? T("none", "(No background)") : fileName)
		global DDLSidebarBg := SettingsGui.Add("DropDownList", "xp+8 yp+20 w" (settings_tab_w - 290) " r8", ddlBgLabels)
			DDLSidebarBg.OnEvent("Change", SidebarBgSelectionChanged)
		global SidebarBgPending := "" ; Full source path of a newly-browsed image staged for copying on Save;
									  ; "" once the current selection is already on disk (or "(none)").
		DDLSidebarBg.Value := 1
		for i, fileName in SidebarBgNames
			if fileName = gui_main_sidebar_bg
				DDLSidebarBg.Value := i
		BtnSidebarBgBrowse := SettingsGui.Add("Button", "x+5 yp w80 h23", T("browse"))
			BtnSidebarBgBrowse.OnEvent("Click", PickSidebarBackground)
		BtnSidebarBgClear := SettingsGui.Add("Button", "x+5 yp w80 h23", T("clear"))
			BtnSidebarBgClear.OnEvent("Click", ClearSidebarBackground)
		global SidebarBgModes := ["fill", "fit", "stretch", "tile", "center"]
		modeLabels := []
		for key in SidebarBgModes
			modeLabels.Push(T("bgmode_" key))
		global DDLSidebarBgMode := SettingsGui.Add("DropDownList", "x+5 yp+1 w95", modeLabels)
		DDLSidebarBgMode.Value := 1
		for i, key in SidebarBgModes
			if key = gui_main_sidebar_bgmode
				DDLSidebarBgMode.Value := i
	settingsGuiTabs.UseTab(2) ;== Addons Tab ====================================
		;-- Available addons ----------------------------------------------------
		SettingsGui.Add("GroupBox",								"x142 y30 w210 h140",			T("gb_settings_availableaddons"))
		global availableAddonsLV := SettingsGui.Add("ListView",	"xp+3 yp+16 h120 w204 -Hdr",	[T("column_availableAddonsLV_1")])
			availableAddonsLV.OnEvent("ItemFocus", GetAddonInfo)
		global LoadedAddonsArray := Array()
		AddonsButtonAdd := SettingsGui.Add("Button",			"w25 h25 x361 y70")
			GuiButtonIcon(AddonsButtonAdd, iconsDir "\actions\go-next.ico", 1, "s16")
			AddonsButtonAdd.OnEvent("Click", LoadAddon)
		AddonsButtonRemove := SettingsGui.Add("Button",			"w25 h25 x361 y+3")
			GuiButtonIcon(AddonsButtonRemove, iconsDir "\actions\go-previous.ico", 1, "s16")
			AddonsButtonRemove.OnEvent("Click", UnLoadAddon)
		;-- Enabled addons ------------------------------------------------------
		SettingsGui.Add("GroupBox",								"x392 y30 w210 h140",			T("gb_settings_enabledaddons"))
		global loadedAddonsLV := SettingsGui.Add("ListView", 	"xp+3 yp+16 h120 w204 -Hdr",	[T("column_loadedAddonsLV_1")])
			loadedAddonsLV.OnEvent("ItemFocus", GetAddonInfo)
		FillLoadedAddonsLV()
		FillAvailableAddonsLV()
		;-- Addon info box ------------------------------------------------------
		SettingsGui.Add("GroupBox",						"x142 y175 h172 w461",					T("gb_settings_addoninfo"))
		global AddonInfoBox := SettingsGui.Add("Edit",	"x145 y188 h150 w455 ReadOnly",			T("text_addonInfoBox"))
	settingsGuiTabs.UseTab() ;== Bottom bar =====================================
		ButtonAyuda := SettingsGui.Add("Button",		"x1 y330 w80 h23",						T("help"))
			ButtonAyuda.OnEvent("Click", (*) => BuildHelpViewer())
		ButtonGuardar := SettingsGui.Add("Button",		"x446 y330 w80 h23",					T("save"))
			ButtonGuardar.OnEvent("Click", SaveAllSettings)
		ButtonCancelar := SettingsGui.Add("Button",		"x+5 y330 w80 h23",						T("cancel"))
			ButtonCancelar.OnEvent("Click", SettingsGuiClose)
}

;## Functions ###################################################################
;== Main tab ====================================================================
;-- UI Settings -----------------------------------------------------------------
UpdateInactiveOpacityLabel(*) {
	global SliderInactiveOpacity, TxtInactiveOpacityPct
	TxtInactiveOpacityPct.Value := Round(SliderInactiveOpacity.Value/255*100) "%"
}
;-- Language picker -------------------------------------------------------------
ReadLanguageMeta(*) { ; Update the display name label whenever the language DDL selection changes.
	; Called both as a Change event handler (ctrl is passed but ignored) and directly after Choose().
	global LanguageMetaBox, langDir, DDLLanguage
	displayName := IniRead(langDir "\" DDLLanguage.Text ".ini", "meta", "display_name", "")
	LanguageMetaBox.Value := (displayName != "") ? displayName : DDLLanguage.Text
}

;-- Background picker -----------------------------------------------------------
FillSidebarBgList(*) { ; Scan userprofile\backgrounds and build the picker's option list.
; Index 1 is always empty and the rest are image files found there.
	global userProfile
	bgDir := userProfile "\backgrounds"
	names := [""]
	if DirExist(bgDir) {
		found := []
		loop Files bgDir "\*.*", "F"
			if RegExMatch(A_LoopFileExt, "i)^(jpe?g|png|bmp|gif)$")
				found.Push(A_LoopFileName)
		for _, fileName in SortedArray(found)
			names.Push(fileName)
	}
	return names
}

UniqueBgFileName(fileName, existingNames) { ; Appends numbers to prevent overwrites in background image files.
	if !ArrayContains(existingNames, fileName)
		return fileName
	SplitPath fileName, , , &ext, &nameNoExt
	n := 2
	loop {
		candidate := nameNoExt " (" n ")" (ext != "" ? "." ext : "")
		if !ArrayContains(existingNames, candidate)
			return candidate
		n++
	}
}

SidebarBgSelectionChanged(*) { ; A manual dropdown pick always refers to "(none)" or a file already on disk.
	global SidebarBgPending
	SidebarBgPending := "" ; Only PickSidebarBackground() stages a file that still needs copying.
}

ClearSidebarBackground(*) {
	global DDLSidebarBg, SidebarBgPending
	DDLSidebarBg.Value := 1 ; "(none)" is always the first entry.
	SidebarBgPending := ""
}

PickSidebarBackground(*) {
	global DDLSidebarBg, SidebarBgNames, SidebarBgPending, userProfile
	file := FileSelect(1, , T("filedialog_sidebarbg"), "Images (*.jpg; *.jpeg; *.png; *.bmp; *.gif)")
	if file = ""
		return
	SplitPath file, &fileName, &fileDir
	bgDir := userProfile "\backgrounds"
	alreadySaved := (StrLower(RTrim(fileDir, "\")) = StrLower(RTrim(bgDir, "\")))
	if !alreadySaved
		fileName := UniqueBgFileName(fileName, SidebarBgNames)
	if !ArrayContains(SidebarBgNames, fileName) {
		SidebarBgNames.Push(fileName)
		DDLSidebarBg.Add([fileName])
	}
	DDLSidebarBg.Choose(fileName)
	SidebarBgPending := alreadySaved ? "" : file
}

;== Addons tab ==================================================================
FillLoadedAddonsLV(*) { ; Fill the "enabled addons" listview from the loadedaddons file.
	global LoadedAddonsLV, settingsGui, LoadedAddonsArray, loadedAddonsFile
	LoadedAddonsLV.Opt("-Redraw") ; Improve performance by disabling redrawing during load.
	Loop read, loadedAddonsFile {
		line := Trim(A_LoopReadLine) ; Remove leading and trailing blank spaces.
		if (line = "" || SubStr(line, 1, 1) = ";") ; If line is blank or (||) the first character is ";", skip those.
			continue
		; The regex "\\addons\\([^\\]+)\\" looks for the literal segment \addons\, then gets everything up to the next backslash (The addon's name).
		; It doesn't care about A_ScriptDir's actual value, how many path segments come before addons, or whether the filename matches the folder name.
		if RegExMatch(line, "\\addons\\([^\\]+)\\", &match) {
			LoadedAddonsLV.Add(, match[1]) ; Add only the addon's folder name.
			LoadedAddonsArray.Push(match[1])
		}
	}
	LoadedAddonsLV.ModifyCol(1, "AutoHdr")
	LoadedAddonsLV.Opt("+Redraw") ; Re-enable redrawing (it was disabled above).
}

FillAvailableAddonsLV(*) { ; Fill available addons listview
	global availableAddonsLV, settingsGui, LoadedAddonsArray, addonsFolder
	if not addonsFolder ; Selected directory in settings is not a folder.
		DirCreate addonsFolder
    if SubStr(addonsFolder, -1, 1) = "\" ; Check if the last character of the folder name is a backslash.
        addonsFolder := SubStr(addonsFolder, 1, -1) ; If it is, remove it to prevent a double-backslash later on.
    availableAddonsLV.Opt("-Redraw") ; Improve performance by disabling redrawing during load.
	loop Files addonsFolder "\*", "D" { ; Gather list of addon folders and append them to the ListView.
	if ArrayContains(LoadedAddonsArray, A_LoopFileName)
			continue
		availableAddonsLV.Add(, A_LoopFileName) ; Create the new row in the ListView and assign it the icon number determined above:
    }
    availableAddonsLV.ModifyCol(1, "AutoHdr")
	availableAddonsLV.Opt("+Redraw") ; Re-enable redrawing (it was disabled above).
}

GetAddonInfo(GuiCtrlObj, Item, *) { ; ItemFocus handler for both the available and enabled addons ListViews.
	global AddonInfoBox, addonsFolder
	if !Item
		return
	addonName := GuiCtrlObj.GetText(Item)
	AddonInfoBox.Value := FormatAddonInfo(addonsFolder "\" addonName)
}

FormatAddonInfo(addonFolder) { ; Parse addon's manifest object and output as the description shown in AddonInfoBox.
	manifest := LoadManifest(addonFolder)
	if !manifest.name && !manifest.description
		return T("text_addonInfoBox_error")
	header := manifest.name
	if manifest.version
		header .= "  v" manifest.version
	if manifest.author
		header .= "  `nAuthor:  " manifest.author
	info := header "`n`n" manifest.description
	if manifest.minKeybirdVersion
		info .= "`n`nRequires Keybird >= " manifest.minKeybirdVersion
	if manifest.features.Length
		info .= "`n`nFeatures: " StrJoin(", ", manifest.features*)
	return info
}

LoadManifest(addonFolder) { ; Parse an addon's manifest.json into an object.
	manifestFile := addonFolder "\manifest.json"
	empty := { name: "", version: "", author: "", site: "", description: "", features: [], minKeybirdVersion: "" }
	if !FileExist(manifestFile)
		return empty
	try {
		manifest := JSON.parse(FileRead(manifestFile, "UTF-8"), , false) ; as_map:=false -> plain Object, dot-notation.
		if !IsObject(manifest)
			throw Error("Manifest is not a JSON object.")
		; Fill in any missing or wrong-typed field with its default, using `empty` as the schema.
		for key, default in empty.OwnProps()
			if !manifest.HasProp(key) || Type(manifest.%key%) != Type(default)
				manifest.%key% := default
		return manifest
	} catch as Err { ; In case of error, return an empty object that doesn't crash the script.
		Log("Could not read manifest for addon '" addonFolder "': " Err.Message, "ERROR", "Settings")
		return empty
	}
}

;-- Buttons ---------------------------------------------------------------------
LoadAddon(*) { ; Load addon (button).
    global availableAddonsLV, LoadedAddonsLV
	selectedAddonRow := availableAddonsLV.GetNext() ; Get the text of the first field.
    if selectedAddonRow = 0
		return
	selectedAddon := availableAddonsLV.GetText(selectedAddonRow, 1) ; Get the text of the first field.
	availableAddonsLV.Delete(selectedAddonRow)
	LoadedAddonsLV.Add(,selectedAddon)
}

UnLoadAddon(*) { ; Unload addon (button).
    global availableAddonsLV, LoadedAddonsLV
	selectedAddonRow := LoadedAddonsLV.GetNext() ; Get the text of the first field.
    if selectedAddonRow = 0
		return
	selectedAddon := LoadedAddonsLV.GetText(selectedAddonRow, 1) ; Get the text of the first field.
	LoadedAddonsLV.Delete(selectedAddonRow)
	availableAddonsLV.Add(,selectedAddon)
}

;-- Event handlers --------------------------------------------------------------
SettingsGuiClose(*) { ; Things to do when GUI is closed.
	result := MsgBox(T("msgbox_settings_exit"), programinfo.name, "OKCancel")
	if Result = "OK" { ; Confirm closing. Doesn't check for changes.
		SettingsGui.Destroy
		mainGUI.Opt("-Disabled") ; Reenable main GUI (owner).
	}
	else
		return
}

SettingsGuiEscape(*) {
	return
}

;-- Main save button ------------------------------------------------------------
SaveAllSettings(*) { ; Save settings from both the main script and any addons.
	; Check that all save routines return TRUE before reloading the script, to prevent save corruption.
	ok := true
	ok := SaveMainSettings() && ok
	ok := SaveEnabledAddons() && ok
	ok := SaveAddonSettings() && ok
	if !ok { ; If any of the save functions return FALSE, return.
		Log("One or more settings failed to save. The script will not reload to avoid losing your previous configuration.", "ERROR")
		return
	}
	Reload
}

SaveMainSettings(*) { ; Submit all selections and write to the settings file.
	global settingsFile, ChkShowControls, ChkTrayIcon, ChkShowInTaskbar, ChkSaveScreenPos, ChkDragWindows, ChkDisableSleep, ChkStartHidden, ChkCheckUpdates, DDLLanguage
	
	; Check if folders are accessible, otherwise refuse to save.
	if !IsWorkingDirAccessible() {
		Log("Cannot save settings: the drive containing this script is not accessible. Reconnect it and try again.", "ERROR")
		return false
	}
		
	tempFile := settingsFile ".tmp" ; Set up a temporary file to save settings to. It will replace the actual file when successful.
	backupFile := settingsFile ".bak" ; Save a copy of the last-known-good settings in case something goes wrong.

	try {
		if FileExist(settingsFile)
			FileCopy settingsFile, tempFile, 1 ; Start from a copy of the current file so unrelated sections survive.

		newSettings := settingsGui.Submit([false])
		;--Main Tab------------------------------------------------------------------
		;-- UI settings -------------------------------------------------------------
		IniWrite ChkShowControls.Value,			tempFile, "WindowSettings",		"gui_main_showcontrols"
		IniWrite ChkTrayIcon.Value,				tempFile, "WindowSettings",		"tray_iconenabled"
		IniWrite ChkShowInTaskbar.Value,		tempFile, "WindowSettings",		"gui_main_showintaskbar"
		IniWrite ChkSaveScreenPos.Value,		tempFile, "WindowSettings",		"gui_main_rememberscreenpos"
		IniWrite ChkDragWindows.Value,			tempFile, "WindowSettings",		"window_main_draggable"
		IniWrite SliderInactiveOpacity.Value,	tempFile, "WindowSettings", "window_main_inactiveopacity"
		;-- Startup -----------------------------------------------------------------
		IniWrite ChkDisableSleep.Value,			tempFile, "StartupSettings",	"startup_disablestandby"
		IniWrite ChkStartHidden.Value,			tempFile, "StartupSettings",	"startup_mainguihidden"
		IniWrite ChkCheckUpdates.Value,			tempFile, "UpdateSettings",		"update_autocheck"
		;-- Language ----------------------------------------------------------------
		IniWrite DDLLanguage.Text,				tempFile, "AppSettings",		"language"
		;-- Sidebar background ------------------------------------------------------
		selectedBgName := SidebarBgNames[DDLSidebarBg.Value]
		if SidebarBgPending != "" { ; New image was picked, copy it into userprofile.
			bgDir := userProfile "\backgrounds"
			if !DirExist(bgDir)
				DirCreate bgDir
			FileCopy SidebarBgPending, bgDir "\" selectedBgName, 1
		}
		IniWrite selectedBgName,	tempFile, "WindowSettings",	"gui_main_sidebar_bg"
		IniWrite SidebarBgModes[DDLSidebarBgMode.Value],	tempFile, "WindowSettings",	"gui_main_sidebar_bgmode"
		;== Successful save routine =================================================
		; If everything succeeded, move the previously known-good save to a backup file, and write the new one.
		if FileExist(settingsFile)
			FileCopy settingsFile, backupFile, 1 ; Keep last-known-good before swapping in the new one.

		FileMove tempFile, settingsFile, 1

	} catch as Err {
		Log("Failed to save settings: " Err.Message ". Your previous settings were not changed.", "ERROR", "SaveMainSettings")
		try FileDelete tempFile
		return false
	}
	return true
}

SaveEnabledAddons(*) { ; Write the enable addons to an ahk file with #Include directives for each one.
	global LoadedAddonsLV, loadedAddonsFile
	tempFile := loadedAddonsFile ".tmp"
	backupFile := loadedAddonsFile ".bak"

	try {
		if FileExist(tempFile) ; Delete any temporary files that happen to exist.
			FileDelete tempFile

		fileHeader :=
		(
		"; #########LOADED ADDONS##########################################################################
		; This file includes all the addons as configured in the Settings GUI.
		; Please do not modify this file manually`n`n"
		)
		
		FileAppend fileHeader, tempFile ; Add the header to the temporary file.

		RowCount := LoadedAddonsLV.GetCount()
		Loop RowCount { ; Format each addon as a properly-formatted #Include line.
			RowText := LoadedAddonsLV.GetText(A_Index)
			FileAppend "#Include %A_ScriptDir%\addons\" RowText "\" RowText ".ahk `n", tempFile
		}

		if !FileExist(tempFile) || FileGetSize(tempFile) = 0 ; Check that the temp file was successfully made.
			throw Error("Generated addon file is empty or missing.")

		if FileExist(loadedAddonsFile) ; Keep a backup of the last-known-good file before replacing it.
			FileCopy loadedAddonsFile, backupFile, 1

		FileMove tempFile, loadedAddonsFile, 1 ; Replace the previous loaded addons file with the new one.

	} catch as Err {
		Log("Failed to save addon list: " Err.Message ". Your addon configuration was not changed.", "ERROR", "SaveEnabledAddons")
		try FileDelete tempFile
		return false
	}
	return true
}

;## Read settings from main ini file ############################################
ReadSettings(*) {
	try {
		;-- UI settings -------------------------------------------------------------
		global gui_main_showcontrols :=			IniRead(settingsFile, "WindowSettings", "gui_main_showcontrols", TRUE)
		global tray_iconenabled :=				IniRead(settingsFile, "WindowSettings", "tray_iconenabled", TRUE)
		global gui_main_showintaskbar :=		IniRead(settingsFile, "WindowSettings", "gui_main_showintaskbar", TRUE) ; Currently not being used, overlaps show controls functionality.	
		global gui_main_rememberscreenpos :=	IniRead(settingsFile, "WindowSettings", "gui_main_rememberscreenpos", TRUE)
		global window_main_draggable :=			IniRead(settingsFile, "WindowSettings", "window_main_draggable", TRUE)
		global gui_main_sidebar_bg :=			IniRead(settingsFile, "WindowSettings", "gui_main_sidebar_bg", "")
		global gui_main_sidebar_bgmode :=		IniRead(settingsFile, "WindowSettings", "gui_main_sidebar_bgmode", "fill")
		global window_main_inactiveopacity :=	IniRead(settingsFile, "WindowSettings", "window_main_inactiveopacity", 130)
		;-- Startup -----------------------------------------------------------------
		global startup_disablestandby :=		IniRead(settingsFile, "StartupSettings", "startup_disablestandby", TRUE)
		global startup_mainguihidden :=			IniRead(settingsFile, "StartupSettings", "startup_mainguihidden", TRUE)
		global startup_alwaysontop :=			IniRead(settingsFile, "StartupSettings", "startup_alwaysontop", TRUE)
		;-- Language ----------------------------------------------------------------
		global active_language :=				IniRead(settingsFile, "AppSettings", "language", "en_us")
		;-- Updates -----------------------------------------------------------------
		global update_autocheck :=				IniRead(settingsFile, "UpdateSettings", "update_autocheck", TRUE)
		global update_lastcheck :=				IniRead(settingsFile, "UpdateSettings", "update_lastcheck", "")
		global update_notifiedversion :=		IniRead(settingsFile, "UpdateSettings", "update_notifiedversion", "")
	} catch as Err {
		; If the settings file exists but can't be read, fall back to defaults for this session.
		Log("Settings file could not be read, using defaults for this session: " Err.Message, "WARN", "ReadSettings")
		global gui_main_showcontrols := TRUE
		global tray_iconenabled := TRUE
		global gui_main_showintaskbar := TRUE
		global gui_main_rememberscreenpos := TRUE
		global window_main_draggable := TRUE
		global gui_main_sidebar_bg := ""
		global gui_main_sidebar_bgmode := "fill"
		global window_main_inactiveopacity := 130
		global startup_disablestandby := TRUE
		global startup_mainguihidden := TRUE
		global startup_alwaysontop := TRUE
		global active_language := "en_us"
		global update_autocheck := TRUE
		global update_lastcheck := ""
		global update_notifiedversion := ""
	}
}


CheckScreenSize(*) { ; On launch, check if screen resolution changed and act accordingly.
	global settingsFile, last_screen_size_w, last_screen_size_h, window_main_position_x, window_main_position_y
	
	;-- Window positioning ------------------------------------------------------
	try {
		global last_screen_size_w :=		IniRead(settingsFile, "WindowSettings", "last_screen_size_w", "1024")
		global last_screen_size_h :=		IniRead(settingsFile, "WindowSettings", "last_screen_size_h", "768")
		global window_main_position_x :=	IniRead(settingsFile, "WindowSettings", "window_main_position_x", A_ScreenWidth/2)
		global window_main_position_y :=	IniRead(settingsFile, "WindowSettings", "window_main_position_y", A_ScreenHeight/2)
	} catch as Err {
		Log("Could not read screen position settings, using defaults: " Err.Message, "WARN", "CheckScreenSize")
		global last_screen_size_w := A_ScreenWidth
		global last_screen_size_h := A_ScreenHeight
		global window_main_position_x := A_ScreenWidth/2
		global window_main_position_y := A_ScreenHeight/2
	}
	; Global flag to signal uf a screen size change has been detected.
	global screenSizeChanged :=				FALSE
	; Check if screen resolution has changed from last time and reset the window to a default location if it has changed.
	if (last_screen_size_w != A_ScreenWidth or last_screen_size_h != A_ScreenHeight) {
		global window_main_position_x	:= A_ScreenWidth/2
		global window_main_position_y	:= A_ScreenHeight/2
		global screenSizeChanged		:= TRUE ; Global flag to signal that the resolution has changed.
	; Write the new screen size to settings.
		try {
			IniWrite A_ScreenWidth, settingsFile, "windowSettings", "last_screen_size_w"
			IniWrite A_ScreenHeight, settingsFile, "windowSettings", "last_screen_size_h"
		} catch as Err {
			Log("Could not save updated screen size: " Err.Message, "WARN", "CheckScreenSize")
		}
	}
	; Check settings if position remembering is disabled, load default positions if so.
	try
		gui_main_rememberscreenpos :=	IniRead(settingsFile, "WindowSettings", "gui_main_rememberscreenpos", FALSE)
	catch
		gui_main_rememberscreenpos := FALSE
	if gui_main_rememberscreenpos = FALSE {
		global window_main_position_x	:= "400" ; Reset the window to a default location if it has changed.
		global window_main_position_y	:= "300" ; Window will be positioned in the center of the screen.
		global screenSizeChanged		:= TRUE ; Set this flag so that anything that detects screen size changes resets.
	}
}

SaveScreenPosition(*) { ; Gets the current screen's size and window positioning for next launch.
	global settingsFile
	if !IsWorkingDirAccessible()
		return
	try {
		IniWrite A_ScreenWidth, settingsFile, "windowSettings", "last_screen_size_w"
		IniWrite A_ScreenHeight, settingsFile, "windowSettings", "last_screen_size_h"
		mainGui.GetPos(&X, &Y, &Width, &Height)
		IniWrite X, settingsFile, "windowSettings", "window_main_position_x"
		IniWrite Y, settingsFile, "windowSettings", "window_main_position_y"
	} catch as Err {
		LogInfo("Could not save screen position on exit: " Err.Message, "SaveScreenPosition")
	}
}

IsWorkingDirAccessible(*) { ; Verifies the script's drive/folder is still reachable.
	return DirExist(A_WorkingDir) && FileExist(userProfile)
}

BuildLanguageList(*) { ; Scan lang\*.ini files and return an array of language codes for the DropDownList.
; The currently active language is moved to the front so AHK selects it by default via Choose().
; Display names are shown separately in LanguageMetaBox via ReadLanguageMeta().
	global active_language
	entries := []
	loop Files langDir "\*.ini" {
		code := StrReplace(A_LoopFileName, ".ini", "")
		if code = active_language
			entries.InsertAt(1, code) ; Active language first so DDL defaults to it.
		else
			entries.Push(code)
	}
	if !entries.Length
		entries.Push("en_us") ; Graceful fallback if lang\ is somehow empty.
	return entries
}