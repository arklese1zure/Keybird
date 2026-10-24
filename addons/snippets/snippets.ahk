
;				=========================================================================
;				|||||						Snippets manager						|||||
;				=========================================================================

class PluginSnippets extends PluginBase {
	
	static PluginKey    := "snippets"           ; internal plugin name, must match lang\en.ini section
	
	static __New() { ;## Startup ########################################################
		;== Bound functions =============================================================
		this.FocusLostHandler	:= ObjBindMethod(this, "OnFocusLost")
		this.HotkeyHandler		:= ObjBindMethod(this, "OpenPopup", "Hotkey")

		;== Hooks =======================================================================
		Plugin_Main_AddTab(
			ObjBindMethod(this, "BuildTabContents"),		; Tab contents
			"Snippets",										; Tab name. This works as fallback.
			"\addons\snippets\res\tabicon.ico",				; Tab icon
			ObjBindMethod(this, "RefreshSnippetsLV"),		; Function when tab is selected
			ObjBindMethod(this, "ShowQuickMenu"),			; Function when tab is right-clicked
			"snippets"										; PluginKey (internal name).
		)
		Plugin_AddMainMenuItem(ObjBindMethod(this, "MenuTrigger"), "Insert snippet", "snippets")

		;== Variables ===================================================================
		this.snippetFolder		:= userProfile "\snippets"
		this.PopupGui			:= ""
		this.PopupHwnd			:= ""
		this.TargetWinHwnd		:= ""
		this.SendBtnLabel		:= ""
		this.FileNames			:= [] ; Filenames array for the popup listbox.

		;== Ensure snippet folder exists ================================================
		this.EnsureFolder(this.snippetFolder)

		;== Hotkeys =====================================================================
		Plugin_AddHotkey("snippets.popup", "^F2", this.HotkeyHandler) ; Bound by the main script in Hotkeys.Start().
		this.NavCriteria	:= ObjBindMethod(this, "PopupIsActive") ; One stable HotIf object. Every distinct HotIf function creates a permanent hotkey variant.
		this.NavCreated		:= false
	}

	;## Bound functions #################################################################
	static FocusLostHandler	:= "" ; Closes the popup when it loses focus.
	static HotkeyHandler	:= "" ; Entry point for the keyboard shortcut.

	static BuildTabContents() { ;## Gui tab contents ####################################
		;== Gui menus ===================================================================
		;-- Context menu ----------------------------------------------------------------
		this.ContextMenu := Menu()
		this.ContextMenu.Add(this.T("contextmenu_newsnippet"), ObjBindMethod(this, "HandleMenuAction"))
			this.ContextMenu.Default := this.T("contextmenu_newsnippet")
		this.ContextMenu.Add()
		this.ContextMenu.Add(this.T("contextmenu_refresh"), ObjBindMethod(this, "HandleMenuAction"))
		this.ContextMenu.Add()
		this.ContextMenu.Add(this.T("contextmenu_edit"), ObjBindMethod(this, "HandleMenuAction"))
		this.ContextMenu.Add(this.T("contextmenu_delete"), ObjBindMethod(this, "HandleMenuAction"))

		;-- Tab right-click quick menu --------------------------------------------------
		this.QuickMenu := Menu()
		this.QuickMenu.Add(this.T("contextmenu_newsnippet"), ObjBindMethod(this, "HandleMenuAction"))

		;== Gui components ==============================================================
		ImageListID2 := IL_Create(5)
		Loop 5
			IL_Add(ImageListID2, "shell32.dll", A_Index)
		;-- Snippets ListView -----------------------------------------------------------
		this.LV_Snippets := mainGui.Add("ListView", "h283 w248 x+0 y+0 Sort ImageList" ImageListID2, [this.T("lv_snippets_col1")])
			this.LV_Snippets.SetImageList(ImageListID2)
			this.LV_Snippets.OnEvent("DoubleClick", ObjBindMethod(this, "EditSnippet"))
			this.LV_Snippets.OnEvent("ContextMenu", ObjBindMethod(this, "ShowContextMenu"))
		this.PopulateLV()
		;-- Buttons ---------------------------------------------------------------------
		BtnActionsMenu := mainGui.Add("Button", "w25 h25 xp+2 y312")
			GuiButtonIcon(BtnActionsMenu, iconsDir "\categories\applications-system.ico", 1, "s16")
			BtnActionsMenu.OnEvent("Click", ObjBindMethod(this, "ShowContextMenuFromButton"))
		BtnRefresh := mainGui.Add("Button", "w25 h25 x+1")
			GuiButtonIcon(BtnRefresh, iconsDir "\actions\view-refresh.ico", 1, "s16")
			BtnRefresh.OnEvent("Click", ObjBindMethod(this, "RefreshSnippetsLV"))
		BtnAddSnippet := mainGui.Add("Button", "w25 h25 x+1")
			GuiButtonIcon(BtnAddSnippet, iconsDir "\actions\list-add.ico", 1, "s16")
			BtnAddSnippet.OnEvent("Click", ObjBindMethod(this, "CreateSnippet"))
	}

	;## Gui functions ###################################################################
	static PopulateLV(*) { ; Initial population of the snippets ListView and filename array.
		if not this.snippetFolder
			return
		if SubStr(this.snippetFolder, -1, 1) = "\"
			this.snippetFolder := SubStr(this.snippetFolder, 1, -1)
		this.LV_Snippets.Opt("-Redraw")
		Loop Files, this.snippetFolder "\*.*" {
			this.LV_Snippets.Add("Icon2", A_LoopFileName)
			this.FileNames.Push(A_LoopFileName)
		}
		this.LV_Snippets.Opt("+Redraw")
	}

	static RefreshSnippetsLV(*) { ; Clear and reload the ListView and filename array.
		this.LV_Snippets.Opt("-Redraw")
		this.LV_Snippets.Delete()
		this.FileNames := []
		Loop Files, this.snippetFolder "\*.*" {
			this.LV_Snippets.Add("Icon2", A_LoopFileName)
			this.FileNames.Push(A_LoopFileName)
		}
		this.LV_Snippets.Opt("+Redraw")
	}

	static EditSnippet(LV_Snippets, RowNumber) { ; Open the selected snippet file for editing.
		FileName := this.LV_Snippets.GetText(RowNumber, 1)
		try
			Run(this.snippetFolder "\" FileName)
		catch
			MsgBox("Could not open " this.snippetFolder "\" FileName ".")
	}

	static CreateSnippet(*) { ; Prompt for a name and create a new snippet file.
		newSnippetName := InputBox("Insert the new text snippet's name.", programinfo.name " - Snippets")
		if newSnippetName.Result = "Cancel"
			return
		if newSnippetName.Value = "" {
			MsgBox("Name cannot be blank, please try again.", "Error", 16)
			return
		}
		newSnippetFile := this.snippetFolder "\" newSnippetName.Value ".txt"
		if FileExist(newSnippetFile) {
			MsgBox("There's already a snippet with that name. Please try again.", "Error", 16)
			return
		}
		try {
			file := FileOpen(newSnippetFile, "w", "UTF-8")
			if !IsObject(file) {
				MsgBox("Could not create the file.`nPlease check that the folder is accessible and you have sufficient permissions.", "Error", 16)
				return
			}
			file.Write("Write or paste your snippet here.")
			file.Close()
		} catch as Err {
			try file.Close()
			Log("Could not create snippet file '" newSnippetFile "': " Err.Message, "ERROR", "PluginSnippets")
			MsgBox("Could not create the file.`nPlease check that the folder is accessible and you have sufficient permissions.", "Error", 16)
			return
		}
		Run newSnippetFile
		this.RefreshSnippetsLV()
	}

	static ShowContextMenu(LV, Item, IsRightClick, X, Y) {
		this.ContextMenu.Show(X, Y)
	}

	static ShowContextMenuFromButton(*) {
		this.ContextMenu.Show()
	}

	static ShowQuickMenu(*) {
		this.QuickMenu.Show()
	}

	static HandleMenuAction(ItemName, *) { ; Dispatcher for all context and quick menu actions.
		FocusedRowNumber := this.LV_Snippets.GetNext(0, "F")
		if (ItemName = this.T("contextmenu_newsnippet")) {
			this.CreateSnippet()
			return
		}
		if (ItemName = this.T("contextmenu_refresh")) {
			this.RefreshSnippetsLV()
			return
		}
		if not FocusedRowNumber
			return
		FileName := this.LV_Snippets.GetText(FocusedRowNumber, 1)
		try {
			if (ItemName = this.T("contextmenu_edit"))
				Run(this.snippetFolder "\" FileName)
			if (ItemName = this.T("contextmenu_delete")) {
				result := MsgBox(this.T("msgbox_confirmfiledelete") " " FileName ,, "YesNo")
				if (result = "Yes") {
					FileRecycle this.snippetFolder "\" FileName
					this.RefreshSnippetsLV()
				}
			}
		} catch {
			MsgBox(this.T("msgbox_file_ioerror") " " this.snippetFolder "\" FileName ".")
		}
	}

	;## Popup GUI #######################################################################
	static MenuTrigger(*) { ; Entry point when invoked from the main menu.
		this.OpenPopup("Menu")
	}

	static OpenPopup(trigger, *) { ; Open the snippet search popup. Guards against opening twice.
		if (this.PopupHwnd != "" && WinExist("ahk_id " this.PopupHwnd)) {
			WinActivate("ahk_id " this.PopupHwnd)
			return
		}
		if trigger = "Hotkey" {
			CoordMode "Mouse", "Screen"
			MouseGetPos &mouseX, &mouseY
			popupCoords := "x" mouseX " y" mouseY
			this.SendBtnLabel := this.T("popupgui_button_send")
			sendMode := "sendAsInput"
		} else {
			mouseX := A_ScreenWidth - 300
			mouseY := A_ScreenHeight - 300
			popupCoords := "x" mouseX " y" mouseY
			this.SendBtnLabel := this.T("popupgui_button_clipboard")
			sendMode := "sendToClipboard"
		}
		this.TargetWinHwnd := WinActive("A")
		this.PopupGui := Gui()
			this.PopupGui.Opt("-Caption +ToolWindow +AlwaysOnTop")
			this.PopupGui.MarginX := 5
			this.PopupGui.MarginY := 5
		;-- Search box ------------------------------------------------------------------
		this.SearchBox := this.PopupGui.Add("Edit", "x2 w225 vSearchTerm")
			this.SearchBox.OnEvent("Change", ObjBindMethod(this, "FilterList"))
		this.PopupGui.Add("Picture", "w24 h24 x+2", A_WorkingDir "\addons\snippets\res\search.ico")
		;-- Results listbox -------------------------------------------------------------
		this.ResultsBox := this.PopupGui.Add("ListBox", "x2 w250 r8 vSelectedSnippet", this.FileNames)
			this.ResultsBox.OnEvent("DoubleClick", ObjBindMethod(this, "InsertSnippet", sendMode, this.TargetWinHwnd))
		;-- Insert button ---------------------------------------------------------------
		this.BtnInsert := this.PopupGui.Add("Button", "x67 y144 h25 w120 -Wrap Default", this.SendBtnLabel)
			this.BtnInsert.OnEvent("Click", ObjBindMethod(this, "InsertSnippet", sendMode, this.TargetWinHwnd))
			GuiButtonIcon(this.BtnInsert, A_WorkingDir "\addons\snippets\res\go.ico", 0, "s16 a0 l2")
		this.PopupGui.Show(popupCoords " h172 w254")
			this.PopupGui.OnEvent("Escape", ObjBindMethod(this, "ClosePopup"))
			this.PopupGui.OnEvent("Close",  ObjBindMethod(this, "ClosePopup"))
		;-- Post-build ------------------------------------------------------------------
		this.PopupHwnd := this.PopupGui.Hwnd
		this.AddDropShadow(this.PopupHwnd)
		;-- Contextual hotkeys for easier navigation ------------------------------------
		this.SetNavHotkeys(true)
		;-- Restore coord mode and begin monitoring focus loss --------------------------
		if trigger = "Hotkey"
			CoordMode "Mouse", "Window"
		OnMessage 0x06, this.FocusLostHandler
	}

	static AddDropShadow(Hwnd) {
		margins := Buffer(16, 0)
		NumPut("Int", 1, margins, 0), NumPut("Int", 1, margins, 4)
		NumPut("Int", 1, margins, 8), NumPut("Int", 1, margins, 12)
		DllCall("dwmapi\DwmExtendFrameIntoClientArea", "Ptr", Hwnd, "Ptr", margins)
		try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", Hwnd, "Int", 33, "Int*", 2, "Int", 4)
	}

	;== Popup functions =================================================================
	static FilterList(*) { ; Case-insensitive, accent-ignoring search against FileNames.
		searchTerm := this.SearchBox.Value
		filtered := []
		for item in this.FileNames {
			try {
				if InStr(RemoveAccents(item), RemoveAccents(searchTerm))
					filtered.Push(item)
			}
		}
		this.ResultsBox.Delete()
		if (filtered.Length > 0) {
			this.ResultsBox.Add(filtered)
			this.ResultsBox.Choose(1)
		}
	}

	static InsertSnippet(sendMode, targetHwnd, *) { ; Read and send the selected snippet.
		savedItem := this.ResultsBox.Text
		this.ClosePopup()
		if !savedItem
			return
		loadedSnippet := FileRead(this.snippetFolder "\" savedItem)
		if sendMode = "sendToClipboard" {
			A_Clipboard := this.SanitizeSnippet(loadedSnippet)
		} else if sendMode = "sendAsInput" {
			if !WinExist("ahk_id " targetHwnd)
				return
			WinActivate("ahk_id " targetHwnd)
			SendText this.SanitizeSnippet(loadedSnippet)
		}
	}

	static OnFocusLost(wParam, lParam, msg, hwnd) { ; Close popup if it loses focus.
		if (wParam = 0 && this.PopupGui && hwnd = this.PopupGui.Hwnd)
			this.ClosePopup()
	}

	static ClosePopup(*) {
		this.SetNavHotkeys(false)
		OnMessage 0x06, this.FocusLostHandler, 0
		this.PopupGui.Destroy()
		this.PopupHwnd := ""
	}

	;== Navigation hotkeys ==============================================================
	static PopupIsActive(*) { ; HotIf criteria: Up/Down only move the list while the popup is the active window.
		return (this.PopupHwnd != "") && WinActive("ahk_id " this.PopupHwnd)
	}

	static NavigateList(key, *) { ; Forward the key to the results listbox, whichever control has focus (usually the search box).
		ControlSend(key, this.ResultsBox)
	}

	static SetNavHotkeys(state) { ; Switch the popup's Up/Down hotkeys on or off. Created on first use, then only toggled.
		try {
			HotIf(this.NavCriteria)
			if (state && !this.NavCreated) {
				Hotkey("Up",   ObjBindMethod(this, "NavigateList", "{Up}"),   "On")
				Hotkey("Down", ObjBindMethod(this, "NavigateList", "{Down}"), "On")
				this.NavCreated := true
			} else if this.NavCreated {
				Hotkey("Up",   state ? "On" : "Off")
				Hotkey("Down", state ? "On" : "Off")
			}
		} catch as Err
			Log("Could not " (state ? "enable" : "disable") " the popup's Up/Down hotkeys: " Err.Message, "WARN", "PluginSnippets")
		HotIf() ; Never leave a context set: it would leak into the next Hotkey() call anywhere in the script.
	}

	static SanitizeSnippet(text) { ; Normalize whitespace before sending.
		text := RegExReplace(text, "\t")				; Remove tabs.
		text := RegExReplace(text, "\r\n|\r|\n", "`n")	; Normalize newlines.
		text := RegExReplace(text, "\s+$")				; Remove trailing whitespace.
		return text
	}
}
