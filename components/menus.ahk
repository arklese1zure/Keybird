;		=========================================================================
;		|||||						Gui menus								|||||
;		=========================================================================

;## Menu items ##################################################################
BuildMainGuiMenus(*) { ; Build all the main gui's menus.
	;== Addons menu =============================================================
	global AddonsMenu := Menu()
	
	;== Main menu ===============================================================
	A_TrayMenu.Delete() ; Remove standard AHK tray items for cleaner look.
	; Items that get checked/toggled/set-as-default later go through MenuAdd() so they
	; can be referenced by a stable key instead of by their current translated text.
	; Plain fire-and-forget entries can keep using .Add() directly.
	MenuAdd(A_TrayMenu, "keep_visible",  T("tray_keep_visible"),  ToggleKeepMainOnTop)
	MenuAdd(A_TrayMenu, "disable_sleep", T("tray_disable_sleep"), ToggleStayAwake)
	MenuAdd(A_TrayMenu, "disable_keys",  T("tray_disable_keys"),  ToggleHotkeys)
	MenuAdd(A_TrayMenu, "lock_app",      T("tray_lock_app"),      ObjBindMethod(GuiLocker, "LockFromMenu"))
	A_TrayMenu.Add() ;-----------------------------------------------------------
	MenuAdd(A_TrayMenu, "settings",     T("settings_title"),     (*) => LaunchSettings())
	A_TrayMenu.Add(T("tray_view_log"), OpenLogFile)
	A_TrayMenu.Add() ;-----------------------------------------------------------
	MenuAdd(A_TrayMenu, "addons",       T("tab_settings_addons"), AddonsMenu)
	BuildMainMenuItems() ; Hook for inserting extra entries to the addons menu.
	A_TrayMenu.Add() ;-----------------------------------------------------------
	A_TrayMenu.Add(T("tray_exit"), GUIExit)
	A_TrayMenu.Default := MenuLabel(A_TrayMenu, "disable_sleep")
		
	global HelpMenu := Menu() ;==Help menu=======================================
	HelpMenu.Add(T("tray_user_manual"), (*) => BuildHelpViewer("Frontpage.md"))
	HelpMenu.Add() ;-------------------------------------------------------------
	HelpMenu.Add(T("tray_check_updates"), (*) => Updater.CheckNow())
	HelpMenu.Add(T("tray_about"), (*) => BuildHelpViewer("About.md"))
}

;## Menu item registry ###########################################################
;	Addons can use these too: e.g. the mascot plugin shows A_TrayMenu on right-
;	click, so any addon wanting a checkable item on that same menu should route
;	its Plugin_AddMainMenuItem registration through a pluginKey (see hooks.ahk),
;	then call MenuLabel(AddonsMenu, "its_plugin_key") wherever it needs to act on
;	its own entry (e.g. AddonsMenu.ToggleCheck(MenuLabel(AddonsMenu, "myaddon"))).

MenuAdd(menuObj, itemKey, displayText, callback, options := "") {
;	Save menu items under a special registry (itemKey) so they can be resolved
;	without translation interfering with functions that work via labels.
	global MenuItemLabels
	menuObj.Add(displayText, callback, options)
	if !MenuItemLabels.Has(menuObj)
		MenuItemLabels[menuObj] := Map()
	MenuItemLabels[menuObj][itemKey] := displayText
}

MenuLabel(menuObj, itemKey) {
;	Resolves itemKey back to the item's actual label.
;	Only items something that need to reference again (e.g. checkable items, the
;	Default item, disabled entries) need to go through MenuAdd().
;	Simple menu entries with a translatable label can go through Menu.Add() directly.
;	Returns "" (and logs) if the key was never registered on that menu
	global MenuItemLabels
	if MenuItemLabels.Has(menuObj) && MenuItemLabels[menuObj].Has(itemKey)
		return MenuItemLabels[menuObj][itemKey]
	Log("No menu item registered for key '" itemKey "'.", "WARN", "MenuLabel")
	return ""
}

;## Menu spawning functions #####################################################
ShowMainMenu(*) {
    button_main.GetPos(&x, &y, &w, &h) ; Get button's coordinates.
	A_TrayMenu.Show(x, y+h) ; Show menu directly under the button
}

HelpMenuShow(*) {
	HelpMenu.Show()
}

ShowQuickMenu(*) { ; Pop up the addons menu at the mouse pointer. Callback of the core.quickmenu hotkey.
	global AddonsMenu
	if !IsSet(AddonsMenu) || DllCall("GetMenuItemCount", "Ptr", AddonsMenu.Handle, "Int") < 1 { ; Not built yet, or no addon added an entry.
		Log("The quick-actions menu has no entries, so it wasn't shown.", "INFO", "ShowQuickMenu")
		return
	}
	; A popup menu can be dismissed by a modifier being released (Alt in particular), and the hotkey's own modifiers are
	; usually still down at this point. Wait for them to be let go. The timeout keeps a stuck key from blocking the menu.
	for key in ["LAlt", "RAlt", "LCtrl", "RCtrl", "LShift", "RShift", "LWin", "RWin"]
		KeyWait(key, "T1")
	AddonsMenu.Show() ; No coordinates: it opens at the mouse pointer.
}