
;		=========================================================================
;		|||||							KeyBird								|||||
;		=========================================================================

;## Startup #####################################################################
;== Script parameters ===========================================================
#Requires AutoHotkey v2
#SingleInstance Force
SetWorkingDir A_ScriptDir ; Start directory structure in the same folder as this script.
FileEncoding "UTF-8" ; Unicode UTF-8, equivalent to CP65001.

;== Info and variables ==========================================================
; Helper variables so developers can add gui elements inside main tabs easier.

ProgramInfo := {
    Name: "Keybird"
}

;-- Main tab layout -------------------------------------------------------------
global main_width			:= 295	; Total width of the window.
global main_height			:= 340	; Total height of the window.
global main_toolbar_h		:= 26	; Toolbar strip height.
global main_sidebar_w		:= 55	; Width of the tab switcher ListView.
global main_tab3_x			:= 44	; Tab geometry. The tab control is intentionally clipped.
global main_tab3_y			:= 21
global main_tab3_w			:= 286	; Total width of the tab control.
global main_tab3_h			:= 361	; Total height of the tab control.
global main_tab_x0			:= 46	; Left edge of the tab area.
global main_tab_y0			:= 26	; Top edge of the tab area.
global main_tab_margin_x	:= 1	; Right inset from the window edge.
global main_tab_margin_bot	:= 5	; Bottom inset from the window edge.
global main_tab_w			:= main_width - main_tab_x0 - main_tab_margin_x		; = 248
global main_tab_h			:= main_height - main_tab_y0 - main_tab_margin_bot	; = 309 (no bottom bar)
;-- Optional bottom bar --
global main_bar_h			:= 25	; Height of the bottom bar row (without padding).
global main_bar_gap			:= 1	; Gap between tab content and the bar.
global main_bar_y			:= main_height - main_tab_margin_bot - main_bar_h	; = 310
global main_tab_h_bar		:= main_bar_y - main_bar_gap - main_tab_y0			; = Height of the bottom bar (with padding).

;== Directories =================================================================
;-- Main folders ----------------------------------------------------------------
global iconsDir 			:= A_WorkingDir "\res\ico" ; Folder for icons.
global addonsFolder			:= A_WorkingDir "\addons" ; Addons folder.
global langDir				:= A_WorkingDir "\lang" ; Localization folder.
;-- User profile folder ---------------------------------------------------------
global userProfile 			:= A_WorkingDir "\userprofile" ; Folder for user settings.
global settingsFile			:= A_WorkingDir "\userprofile\settings.ini" ; Settings file.
StartupCheckUserProfile() ; Check folders for integrity.

;== Error logging ===============================================================
#Include components\log.ahk

;== Start hooks =================================================================
InitializeHooks() ; Initialize hooks so addon functions can be registered.

;== Include addons ==============================================================
#Include *i %A_ScriptDir%\userprofile\LoadedAddons.ahk ; Load addons from generated file.

;== Include scripts and libraries ===============================================
;-- Functions -------------------------------------------------------------------
#Include %A_ScriptDir%\components\fn.ahk
#Include %A_ScriptDir%\components\hooks.ahk
#Include %A_ScriptDir%\components\pluginbase.ahk
;-- Gui components --------------------------------------------------------------
#Include %A_ScriptDir%\components\hotkeys.ahk
#Include %A_ScriptDir%\components\menus.ahk
#Include %A_ScriptDir%\components\settings.ahk
#Include %A_ScriptDir%\components\guilocker.ahk
#Include %A_ScriptDir%\components\docsviewer.ahk
;-- Libraries -------------------------------------------------------------------
#Include %A_ScriptDir%\lib\ListViewExtensions.ahk
#Include %A_ScriptDir%\lib\GuiButtonIcon.ahk
#Include %A_ScriptDir%\lib\String.ahk
#Include %A_ScriptDir%\lib\RichEdit.ahk
#Include %A_ScriptDir%\lib\RichEditDlgs.ahk
#Include %A_ScriptDir%\lib\JSON.ahk
#Include %A_ScriptDir%\lib\Gdip_All.ahk

;== Load settings ===============================================================
ReadSettings() ; Load settings.

;== Load graphics library (Gdip_All.ahk) ========================================
global gdipToken := 0
try gdipToken := Gdip_Startup()
catch as Err
	Log("GDI+ failed to start; image features will be unavailable: " Err.Message, "WARN", "Startup")
OnExit((*) => (gdipToken && Gdip_Shutdown(gdipToken)))

;== Post-startup ================================================================
PluginBase.LoadLanguage(active_language) ; Load UI strings for the active language (saved in settings).
CheckScreenSize() ; Check for screen changes (e.g. resolution has changed).
ReadAddonSettings() ; (Hook) read addon settings.
OnStartUp() ; (Hook) Trigger actions before Main gui is built.
Hotkeys.Start() ; Bind registered hotkeys and resolve conflicts. Addons register their hotkeys via __New() and the startup hook.

;## Build Main gui ##############################################################
global mainGui := Gui() ; Create GUI object.
mainGui.Title := programinfo.name ; Gui title.
BuildMainGuiMenus() ; Load menus (menus.ahk).
BuildMainGuiToolbar() ; Main GUI toolbar.
BuildMainGuiTabs() ; Tab contents.

;== Gui sizing ==================================================================
; Add properties to the window. It'll be hidden until the lock check.
mainGui.Show(
	"w"  main_width
	" h" main_height
	" x" window_main_position_x
	" y" window_main_position_y
	" Hide"
)
global window_main_ishidden := TRUE

;== Main gui properties =========================================================
if startup_alwaysontop = TRUE { ; Check if the main window should be always on top, based on settings.
	global window_main_alwaysontop := FALSE
	ToggleKeepMainOnTop()
}

if gui_main_showcontrols = FALSE { ; Hide the window header buttons, based on settings.
	mainGui.Opt("-SysMenu +ToolWindow")
}

;== Main gui event handlers =====================================================
;-- Main gui events -------------------------------------------------------------
mainGui.OnEvent("Close", ToggleHideWindow) ; Hides the main gui window when X is pressed, instead of exiting.

;-- Exit handling ---------------------------------------------------------------
OnExit(MainExitHandler, -1) ; Runs on every exit path. -1 = before the GDI+ shutdown handler registered earlier.

;## Post-startup ################################################################
;== Stay awake ==================================================================
global disable_standby	:= FALSE ; Check if the always awake function should be on at launch.
if startup_disablestandby = TRUE
	ToggleStayAwake()

;== System tray =================================================================
A_TrayMenu.Default := "" ; Suppress default action on tray icon single-click.
UpdateTrayTooltip() ; Set initial tray tooltip.

;== Monitor system messages =====================================================
OnMessage 0x06,		WM_ACTIVATE ; Activate on window focus.
OnMessage 0x0201,	WM_LBUTTONDOWN ; Monitor for left clicks on GUI.
OnMessage 0x204,	WM_RBUTTONDOWN ; Monitor for right clicks on GUI.

;== Gui lock check ==============================================================
GuiLocker.InitLock() ; If lock-on-startup is enabled, InitLock() leaves the main gui hidden and shows the password prompt.
if (!GuiLocker.isLocked && startup_mainguihidden != TRUE) ; If not locked and not set up to start hidden, reveal the window.
	SetMainWindowVisible(TRUE)

;## Functions ###################################################################
;== Startup functions ===========================================================
StartupCheckUserProfile(*) { ; Check integrity of files.
	if !DirExist(userProfile) { ; Check for user profile folder.
		; Profile folder not found, offer to create a new one.
		result := MsgBox(T("msgbox_nouserprofilefound"), programinfo.name, "YesNo Icon!")
		if result = "Yes" {
			try DirCreate userProfile
			catch as Err {
				Log("Could not create userprofile folder: " Err.Message, "FATAL", "StartupCheckUserProfile")
			}
		} else {
			ExitApp
		}
	}
}

;== Build functions =============================================================
;-- Toolbar ---------------------------------------------------------------------
BuildMainGuiToolbar(*) {
	global mainGui
	ToolbarGroupBox := mainGui.Add("GroupBox", "w" main_width " h34 x0 y-6")			; Frame for the toolbar.
	global button_main := mainGui.Add("Button", "w50 h25 xp+2 yp+7")
		GuiButtonIcon(button_main, "shell32.dll",044, "s16")
		button_main.OnEvent("Click", ShowMainMenu)
	button_help := mainGui.Add("Button", "w25 h25 x+2")
		GuiButtonIcon(button_help, iconsDir "\apps\help-browser.ico", 1, "s16")
		button_help.OnEvent("Click", HelpMenuShow)
}

;-- Tab switcher ----------------------------------------------------------------
BuildMainGuiTabs(*) {
	global mainGui, Main_AddTab, Main_ActiveTabs
	global mainTabsLV := mainGui.Add("ListView", "x-1 y" main_toolbar_h " w" main_sidebar_w " h" (main_height - main_toolbar_h + 1) " -E0x200", ["Tabs"])
		mainTabsLV.Base := ListViewExtensions.Prototype
		mainTabsLV.Opt("+Icon -0x100000 -Hdr -Multi")
		mainTabsLV.SetIconSpacing(40 , 50)
		mainTabsLV.OnEvent("ItemSelect", TabSwitcher)
		mainTabsLV.OnEvent("ItemFocus", TabNameTooltip)
		mainTabsLV.OnEvent("ContextMenu", TabLVRightClick)
		mainTabsLV.ModifyCol(1, 30)
		ApplySidebarBackground()
	global mainTabs := mainGui.Add("Tab3", "x44 y21 w286 h361", [])
		SendMessage(0x1329, 0, (1)|(1<<16), , mainTabs.hwnd) ; Hide tab headers. Width = 0, height = 1 (cannot be zero)
	BuildAddonTabs() ; Hook for adding the tab gui elements, icons, and the mainTabsLV row.
	if Main_ActiveTabs.Length {
		mainGui.Title := programinfo.name " — " Main_ActiveTabs[1].Name ; Use the first successfully-built tab.
	} else {
		mainGui.Title := programinfo.name
		Log("No addon tabs built successfully. Main window will have no tab content.", "WARN", "BuildMainGuiTabs")
	}
}

BuildBackgroundBitmap(imagePath, mode, w, h, bgARGB) { ; Creates the bitmap for the sidebar listview background.
	pSrc := Gdip_CreateBitmapFromFile(imagePath)
	if pSrc <= 0
		return 0
	Gdip_GetImageDimensions(pSrc, &sw, &sh)
	pDst := Gdip_CreateBitmap(w, h)
	G := Gdip_GraphicsFromImage(pDst)
	Gdip_GraphicsClear(G, bgARGB)		; Fills whatever the image doesn't cover ("fit" and "center").
	Gdip_SetInterpolationMode(G, 7)		; High quality bicubic.
	switch mode {
		case "stretch": ; Fill the area, ignore aspect ratio.
			Gdip_DrawImage(G, pSrc, 0, 0, w, h, 0, 0, sw, sh)
		case "fit": ; Whole image visible, empty bands on the sides.
			s := Min(w / sw, h / sh), dw := Round(sw * s), dh := Round(sh * s)
			Gdip_DrawImage(G, pSrc, (w - dw) // 2, (h - dh) // 2, dw, dh, 0, 0, sw, sh)
		case "center": ; Original size, centered, cropped if larger.
			Gdip_DrawImage(G, pSrc, (w - sw) // 2, (h - sh) // 2, sw, sh, 0, 0, sw, sh)
		case "tile":
			pBrush := Gdip_CreateTextureBrush(pSrc, 0) ; 0 = WrapModeTile.
			Gdip_FillRectangle(G, pBrush, 0, 0, w, h)
			Gdip_DeleteBrush(pBrush)
		default: ; "fill": cover the whole area keeping aspect ratio, crop the overflow.
			s := Max(w / sw, h / sh), dw := Round(sw * s), dh := Round(sh * s)
			Gdip_DrawImage(G, pSrc, (w - dw) // 2, (h - dh) // 2, dw, dh, 0, 0, sw, sh)
	}
	hBitmap := Gdip_CreateHBITMAPFromBitmap(pDst)
	Gdip_DeleteGraphics(G), Gdip_DisposeImage(pDst), Gdip_DisposeImage(pSrc)
	return hBitmap ; Returns an HBITMAP of exactly w×h, or 0 on failure.
}

ApplySidebarBackground(*) { ; Applies the user-chosen sidebar background image, or clears it.
	global mainTabsLV, gui_main_sidebar_bg, gui_main_sidebar_bgmode, userProfile, gdipToken
	if !gdipToken
		return
	if gui_main_sidebar_bg = "" {
		mainTabsLV.SetBkImage(0)
		return
	}
	imagePath := userProfile "\backgrounds\" gui_main_sidebar_bg
	if !FileExist(imagePath) {
		Log("Sidebar background not found: " imagePath, "WARN", "ApplySidebarBackground")
		return
	}
	; Target size: the ListView's client area.
	rect := Buffer(16, 0)
	DllCall("GetClientRect", "Ptr", mainTabsLV.Hwnd, "Ptr", rect)
	w := NumGet(rect, 8, "Int"), h := NumGet(rect, 12, "Int")
	; ListView background color (BGR) → ARGB, for the areas "fit"/"center" leave uncovered.
	c := SendMessage(0x1000, 0, 0, mainTabsLV) ; LVM_GETBKCOLOR
	bgARGB := 0xFF000000 | ((c & 0xFF) << 16) | (c & 0xFF00) | ((c >> 16) & 0xFF)
	try {
		hBitmap := BuildBackgroundBitmap(imagePath, gui_main_sidebar_bgmode, w, h, bgARGB)
		if !hBitmap || !mainTabsLV.SetBkImage(hBitmap) ; The ListView owns the bitmap from here; don't delete it.
			Log("Could not load sidebar background: " imagePath, "WARN", "ApplySidebarBackground")
	} catch as Err {
		Log("Could not load sidebar background: " Err.Message, "WARN", "ApplySidebarBackground")
	}
}

;== Main gui element functions ==================================================
;-- Tab switcher ----------------------------------------------------------------
TabNameTooltip(*) {	; Shows the tab's complete name when hovering. Useful for names that are too long.
	global mainTabsLV, mainTabs, mainGui, Main_ActiveTabs
    row := mainTabsLV.GetNext()
	if !row
		return
	if !Main_ActiveTabs.Has(row) ; Should always be true, but never trust a UI index blindly.
		return
	tabName := Main_ActiveTabs[row].Name
		ToolTip tabName
	SetTimer () => ToolTip(), -500
	return
}

TabSwitcher(*)	{ ; Maps mainTabsLV selections to mainTabs. Works as a prettier-looking tab switcher.
	global mainTabsLV, mainTabs, mainGui, Main_ActiveTabs
    row := mainTabsLV.GetNext()
	if !row ; No row selected.
		return
	if !Main_ActiveTabs.Has(row) {
		Log("Tab switcher row " row " has no matching active tab.", "WARN", "TabSwitcher")
		return
	}
	tabObj := Main_ActiveTabs[row]
	mainTabs.Choose(row)
	mainGui.Title := programinfo.name " — " tabObj.Name
	mainTabsLV.Redraw()
	; Hook for calling functions assigned to tab switching.
	Hooks_Call(tabObj.OnSelect, "Tab OnSelect hook", tabObj.Name, {throttle: true})
}

;-- Tray icon & menu ------------------------------------------------------------
UpdateTrayTooltip(*) { ; Rebuild the tray icon tooltip from current state.
	global disable_standby
	tip := programinfo.name
	if GuiLocker.isLocked
		tip .= "`n" "[" T("tray_tooltip_locked") "]"
	if disable_standby
		tip .= "`n" "[" T("tray_tooltip_nosleep") "]"
	A_IconTip := tip
}

;-- Events ----------------------------------------------------------------------
GUIExit(*) {
	ExitApp ; MainExitHandler (registered with OnExit) runs ExitRoutine for every exit path, including this one.
}

MainExitHandler(exitReason, exitCode) { ; Single place for "the script is ending" work: exit, reload, logoff, shutdown.
	; Remove message monitors before shutdown.
	OnMessage(0x06,   WM_ACTIVATE,    0)
	OnMessage(0x0201, WM_LBUTTONDOWN, 0)
	OnMessage(0x204,  WM_RBUTTONDOWN, 0)
	static ran := false
	if ran
		return 0
	ran := true
	SaveScreenPosition()
	OnMainGuiExit() ; Script shutdown hook.
	return 0 ; Non-zero cancels the exit, which must never happen on logoff/shutdown.
}

;== Toggles =====================================================================
ToggleHideWindow(*) { ; Toggle hiding the main gui
	global window_main_ishidden
	if GuiLocker.isLocked = TRUE {
		GuiLocker.ShowLockPrompt()
		return
	}
	SetMainWindowVisible(window_main_ishidden = 1, true) ; Hidden: show it. Shown: hide it.
}

ToggleHotkeys(*) { ; Suspend all hotkeys and hotstrings.
	Hotkeys.ToggleUserSuspend() ; The registry owns Suspend, so unlocking can't undo this.
	A_TrayMenu.ToggleCheck(MenuLabel(A_TrayMenu, "disable_keys")) ; Disable hotkeys & hotstrings.
}

ToggleKeepMainOnTop(*) { ; Toggle main gui being always on top
global window_main_alwaysontop
	if window_main_alwaysontop = 0 {
		mainGui.Opt("+AlwaysOnTop")
		A_TrayMenu.ToggleCheck(MenuLabel(A_TrayMenu, "keep_visible"))
		global window_main_alwaysontop := 1
	} else {
		mainGui.Opt("-AlwaysOnTop")
		A_TrayMenu.ToggleCheck(MenuLabel(A_TrayMenu, "keep_visible"))
		global window_main_alwaysontop := 0
	}
}

ToggleStayAwake(*) { ; Prevents the system from going to standby mode.
    global disable_standby
	disable_standby := !disable_standby
    if disable_standby {
        KeepAwakeOn()
		A_TrayMenu.ToggleCheck(MenuLabel(A_TrayMenu, "disable_sleep"))
    } else {
        KeepAwakeOff()
		A_TrayMenu.ToggleCheck(MenuLabel(A_TrayMenu, "disable_sleep"))
    }
	UpdateTrayTooltip()
}

;== Window hide/unhide logic ====================================================
SetMainWindowVisible(visible, activate := false) { ; Handle the main gui's show/hide events.
	; visible	- true to show, false to hide.
	; activate	- true to also bring the window to the front and give it focus (and un-minimize it if needed).
	; Returns true if the window was correctly shown/hidden.
	global mainGui, window_main_ishidden, window_main_alwaysontop
	if !IsSet(mainGui) { ; Catch in case main gui doesn't exist yet (e.g. A hotkey can fire before the gui exists).
		verb := visible ? "shown" : "hidden"
		Log("The main window doesn't exist yet, so it can't be " verb ".", "INFO", "SetMainWindowVisible")
		return false
	}
	if visible {
		WinShow "ahk_id" mainGui.Hwnd
		WinSetTransparent 255, "ahk_id" mainGui.Hwnd ; Set window opacity to opaque.
		if IsSet(window_main_alwaysontop) && window_main_alwaysontop = 1
			WinSetAlwaysOnTop 1, "ahk_id" mainGui.Hwnd ; "Keep above others" set while the window is hidden doesn't hold, so apply it again now.
		window_main_ishidden := 0
		if activate {
			if WinGetMinMax("ahk_id" mainGui.Hwnd) = -1 ; Minimized.
				WinRestore "ahk_id" mainGui.Hwnd
			WinActivate "ahk_id" mainGui.Hwnd
		}
	} else {
		mainGui.Hide() ; Not WinHide: that throws if the window is already hidden.
		window_main_ishidden := 1
	}
	return true
}

ShowMainWindow(*) { ; Show the main gui and bring it to the front. Callback of the core.show hotkey.
	if GuiLocker.isLocked = TRUE { ; Hotkeys are suspended while locked, so a hotkey can't get here. Safety net for other callers.
		GuiLocker.ShowLockPrompt()
		return
	}
	SetMainWindowVisible(true, true)
}

HideMainWindow(*) { ; Hide the main gui. Callback of the core.hide hotkey.
	if GuiLocker.isLocked = TRUE ; Locking already hides it.
		return
	SetMainWindowVisible(false)
}

;== DLL wrappers ================================================================
KeepAwakeOn(*) { ; Prevents system and monitor to go standby
	DllCall("SetThreadExecutionState", "UInt", 0x80000002)
}

KeepAwakeOff(*) { ; Allows standby again.
	DllCall("SetThreadExecutionState", "UInt", 0x80000000)
}

;== Event wrappers ==============================================================
WM_ACTIVATE(wParam, lParam, msg, hwnd) {
	global window_main_inactiveopacity
	if !IsSet(mainGui) ; Handle missing mainGui hwnd.
		return
	mainGuiHwnd := mainGui.Hwnd
	if (hwnd == mainGuiHwnd && WinActive("ahk_id" mainGuiHwnd))
		WinSetTransparent 255, "ahk_id"	mainGuiHwnd
	if (hwnd == mainGuiHwnd && !WinActive("ahk_id" mainGuiHwnd))
		try
			WinSetTransparent window_main_inactiveopacity, "ahk_id"	mainGuiHwnd
		catch as Err
			LogInfo("Could not set window transparency: " Err.Message, "WM_ACTIVATE")
	else
		return
}

WM_LBUTTONDOWN(wParam, lParam, msg, hwnd) { ; Monitor if a specific gui window is left-clicked.
	global leftclickguihwnd := hwnd ; Store currently clicked GUI in a global variable.
	global window_main_draggable
	if window_main_draggable = TRUE
		PostMessage 0xA1, 2 ; Makes all script windows draggable from anywhere.
	OnGuiLeftClick() ; Hook for doing things when left-clicking the gui.
}

WM_RBUTTONDOWN(wParam, lParam, msg, hwnd) { ; Monitor if a specific gui window is right-clicked.
global rightclickguihwnd := hwnd ; Store currently clicked GUI in a global variable.
	OnGuiRightClick() ; Hook for doing things when right-clicking the gui.
}