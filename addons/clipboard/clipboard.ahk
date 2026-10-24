
;				=========================================================================
;				|||||						Clipboard manager						|||||
;				=========================================================================

class PluginClipboardManager extends PluginBase {
	
	static PluginKey    := "clipboard"
	
	static settingsFile := A_WorkingDir "\userprofile\clipboard.ini"

	static __New() { ;## Startup ########################################################
		;== Bound functions =============================================================
		this.ClipStatus := ObjBindMethod(this, "ClipChanged")
		this.AltPasteFn := ObjBindMethod(this, "AlternatePaste")

		;== Hooks =======================================================================
		Plugin_Main_AddTab(
			ObjBindMethod(this, "BuildTabContents"),				; Tab contents.
			"Clipboard manager",									; Tab name.
			"\addons\clipboard\res\tab.ico",						; Tab icon.
			,														; Tab left-click action.
			,														; Tab right-click action.
			"clipboard"												; PluginKey (internal name).
		)
		Plugin_Settings_AddTab(ObjBindMethod(this, "BuildSettingsTab"), "Clipboard manager", "clipboard")
		Plugin_Settings_SaveSettings(ObjBindMethod(this, "SaveSettings"), "Clipboard manager")
		Plugin_Main_OnExit(ObjBindMethod(this, "StopMonitoring"), "Clipboard manager")
		Plugin_Main_OnLock(ObjBindMethod(this, "StopMonitoring"), "Clipboard manager") ; Stop monitoring clipboard when locked.
		Plugin_Main_OnUnlock(ObjBindMethod(this, "StartMonitoring"), "Clipboard manager") ; Restart clipboard monitoring.

		;== Load settings ===============================================================
		this.MaxHistory		 := Integer(this.GetSetting("Settings", "MaxHistory",	  20))

		;== Variables ===================================================================
		this.ClipHistory := [] ; Array to hold clipboard entries.

		;== Hotkey ======================================================================
		; Ctrl+Alt+V for alternate paste. Off until switched on; the checkbox in this addon's settings tab drives it.
		Plugin_AddHotkey("clipboard.altpaste", "^!v", this.AltPasteFn, {enabled: false})

		;== Clipboard monitor ===========================================================
		OnClipboardChange(this.ClipStatus) ; Start monitoring clipboard for changes.
	}

	;## Bound functions #################################################################
	static ClipStatus  := "" ; Bound ClipChanged — kept as property to survive GC.
	static AltPasteFn  := "" ; Bound AlternatePaste — kept as property to survive GC.

	static BuildTabContents(*) { ;## Gui tab contents ###################################
		;== Gui components ==============================================================
		;-- Clip list ------------------------------------------------------------------
		this.CBListLV := mainGui.Add("ListView", "h140 w248 x+0 y+0 -Multi", [this.T("cblistlv_col_time"),this.T("cblistlv_col_text")])
			this.CBListLV.OnEvent("DoubleClick", ObjBindMethod(this, "UpdateClipboard"))
			this.CBListLV.OnEvent("ItemSelect",  ObjBindMethod(this, "UpdateClipPreview"))

		;-- Preview box ----------------------------------------------------------------
		this.CBPreviewBox := mainGui.Add("Edit", "h137 w248 y+6 +Multi +ReadOnly vPreview")

		;-- Buttons --------------------------------------------------------------------
		BtnOpenSettings := mainGui.Add("Button", "w25 h25 xp+2 y312")
			GuiButtonIcon(BtnOpenSettings, iconsDir "\categories\applications-system.ico", 1, "s16")
			BtnOpenSettings.OnEvent("Click", (*) => LaunchSettings("clipboard")) ; Stable key, not the translated caption -- see BuildSettingsTab below.
		BtnClearClipboard := mainGui.Add("Button", "w25 h25 x+1")
			GuiButtonIcon(BtnClearClipboard, iconsDir "\actions\edit-clear.ico", 1, "s16")
			BtnClearClipboard.OnEvent("Click", ObjBindMethod(this, "ClearClipBoard"))
	}

	static BuildSettingsTab(*) { ;## Settings tab contents ##############################
		;-- History length -------------------------------------------------------------
		SettingsGui.Add("GroupBox",  "x" settings_tab_x0 " y" settings_tab_y0 " w461 h50", this.T("gb_settings_history"))
		SettingsGui.Add("Text",      "xp+15 yp+20", this.T("text_settings_maxentries")) ; Maximum entries
		this.SettingsMaxHistory := SettingsGui.Add("Edit",   "x+8 yp-3 w50 Number")
			this.SettingsMaxHistory.Value := this.MaxHistory
		SettingsGui.Add("UpDown", "Range5-100", this.MaxHistory) ; Spinner attached to the Edit above

		;-- Alternate paste ------------------------------------------------------------
		SettingsGui.Add("GroupBox", "x" settings_tab_x0 " y+20 w461 h90", this.T("gb_settings_altpaste")) ; Alternate paste.
		SettingsGui.Add("Text", "xp+15 yp+20 w430 cGray", this.T("text_settings_altpaste")) ; Alt paste description.
		SettingsGui.Add("Text", "xp y+6 w430", this.T("text_settings_altpaste_hotkeys")) ; Where to turn it on and pick its key.
	}

	;## Gui functions ###################################################################
	static ClipChanged(DataType) { ; Fires automatically every time the clipboard changes.
		if GuiLocker.isLocked ; Don't save to clipboard manager is GUI is locked.
			return
		if (DataType != 1) ; DataType 1 = Text, 2 = Non-Text (images etc.), 0 = Empty.
			return
		try ; Prevent crashing if another application is holding the clipboard.
			CurrentClip := A_Clipboard
		catch
			return
		if (this.ClipHistory.Length > 0 && this.ClipHistory[1].Text == CurrentClip) ; Prevent duplicates.
			return
		ClipData := {Text: CurrentClip, Time: FormatTime(, "HH:mm:ss")}
		this.ClipHistory.InsertAt(1, ClipData)
		if (this.ClipHistory.Length > this.MaxHistory) ; Trim to MaxHistory.
			this.ClipHistory.Pop()
		this.RedrawList()
	}

	static RedrawList() { ; Rebuild the ListView from ClipHistory.
		if !this.HasProp("CBListLV")
			return
		this.CBListLV.Opt("-Redraw")
		this.CBListLV.Delete()
		for item in this.ClipHistory {
			snippet := StrReplace(item.Text, "`n", " ")
			snippet := StrReplace(snippet, "`r", "")
			if (StrLen(snippet) > 50)
				snippet := SubStr(snippet, 1, 50) . "..."
			this.CBListLV.Add("", item.Time, snippet)
		}
		this.CBListLV.ModifyCol(1, "AutoHdr")
		this.CBListLV.ModifyCol(2, "AutoHdr")
		this.CBListLV.Opt("+Redraw")
	}

	static UpdateClipPreview(CtrlObj, ItemIndex, Selected) {
		if !this.HasProp("CBListLV")
			return
		ItemIndex := this.CBListLV.GetNext(0, "Focused")
		if (ItemIndex == 0) {
			this.CBPreviewBox.Value := ""
			return
		}
		this.CBPreviewBox.Value := this.ClipHistory[ItemIndex].Text
	}

	static UpdateClipboard(*) { ; Restores a history entry to the clipboard on double-click.
		RowIndex := this.CBListLV.GetNext(0, "Focused")
		if (RowIndex == 0)
			return
		OnClipboardChange(this.ClipStatus, 0) ; Pause monitoring to avoid logging this as a new entry.
		A_Clipboard := this.ClipHistory[RowIndex].Text
		ClipWait(1)
		OnClipboardChange(this.ClipStatus, 1) ; Resume monitoring.
	}

	static AlternatePaste(*) { ; Send current clipboard text as keystrokes (Ctrl+Alt+V).
		text := A_Clipboard
		if (text = "") {
			ToolTip this.T("tooltip_altpaste_warn1") ; Alternate paste: clipboard is empty.
			SetTimer () => ToolTip(), -2000
			return
		}
		targetHwnd := WinActive("A")
		if (targetHwnd = mainGui.Hwnd) {
			ToolTip this.T("tooltip_altpaste_warn2") ; Alternate paste: switch to a target window first.
			SetTimer () => ToolTip(), -2000
			return
		}
		if !WinExist("ahk_id " targetHwnd) {
			ToolTip this.T("tooltip_altpaste_warn3") ; Alternate paste: target window no longer exists.
			SetTimer () => ToolTip(), -2000
			return
		}
		SendText text
	}

	static ClearClipBoard(*) { ; Clear all saved entries.
		this.ClipHistory := []
		this.CBListLV.Delete()
		this.CBPreviewBox.Value := ""
	}
	
	static StopMonitoring(*) { ; Stop clipboard monitoring.
      OnClipboardChange(this.ClipStatus, 0)
	}

	static StartMonitoring(*) { ; Start or resume clipboard monitoring.
		OnClipboardChange(this.ClipStatus, 1)
	}
	
	;## Settings functions ##############################################################
	static SaveSettings(*) {
		newMax := Integer(this.SettingsMaxHistory.Value)
		if (newMax < 5 || newMax > 100) {
			Log("MaxHistory value out of range (" newMax "), keeping previous value.", "WARN", "PluginClipboardManager")
			newMax := this.MaxHistory
		}

		this.SaveSetting("Settings", "MaxHistory",	  newMax)

		; Apply immediately — no restart needed.
		this.MaxHistory := newMax
		if (this.ClipHistory.Length > this.MaxHistory) { ; Trim live history if limit was reduced.
			while (this.ClipHistory.Length > this.MaxHistory)
				this.ClipHistory.Pop()
			this.RedrawList()
		}
	}
}