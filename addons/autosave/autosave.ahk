;				=========================================================================
;				|||||		Autosave — Local autosave for MS Office applications	|||||
;				=========================================================================
;
;	Periodically saves any open Word, Excel, or PowerPoint documents that have unsaved
;	changes, via COM automation.
;	Doesn't save documents that haven't been saved at least once.
;	On failure (locked file, disk full, etc.) it logs the error and shows a TrayTip.

class PluginAutosave extends PluginBase {

	static PluginKey    := "autosave" ; internal plugin name, must match lang\en_us.ini section
	static settingsFile := A_WorkingDir "\userprofile\autosave.ini"

	static __New() { ;## Startup ########################################################
		;== Bound functions =============================================================
		this.TimerHandler := ObjBindMethod(this, "RunAutosave")

		;== Hooks =======================================================================
		Plugin_Main_OnStartUp(ObjBindMethod(this, "LoadAutosaveSettings"), "Autosave")
		Plugin_Settings_AddTab(ObjBindMethod(this, "BuildSettingsTab"), "Autosave", "autosave")
		Plugin_Settings_SaveSettings(ObjBindMethod(this, "SaveSettings"), "Autosave")
		Plugin_Main_OnExit(ObjBindMethod(this, "StopMonitoring"), "Autosave") ; Shut down autosave timer.
		Plugin_Main_OnLock(ObjBindMethod(this, "StopMonitoring"), "Autosave") ; Stop autosave times while locked.
		Plugin_Main_OnUnlock(ObjBindMethod(this, "LoadAutosaveSettings"), "Autosave") ; Restart autosave timer.
	}

	;## Bound functions #################################################################
	static TimerHandler := "" ; Entry point for the periodic SetTimer loop.

	;## Startup #########################################################################
	static LoadAutosaveSettings(*) { ; Read settings and start the timer if enabled.
		enabled := this.GetSetting("Settings", "enabled", 1)
		if enabled = 0
			return
		this.StartTimer()
	}

	static StartTimer(*) {
		intervalMinutes := this.GetSetting("Settings", "interval_minutes", 5)
		if intervalMinutes < 1
			intervalMinutes := 1 ; Limit spamming COM (e.g. if the settings file was hand-edited to some weird value).
		SetTimer this.TimerHandler, intervalMinutes * 60000
	}

	;## Autosave routine ################################################################
	static RunAutosave(*) { ; Fired by SetTimer on the configured interval.
		if GuiLocker.isLocked ; Prevent auto-saving if GUI is locked.
			return
		if this.GetSetting("Settings", "watch_word", 1)
			this.SaveWordDocs()
		if this.GetSetting("Settings", "watch_excel", 1)
			this.SaveExcelDocs()
		if this.GetSetting("Settings", "watch_powerpoint", 1)
			this.SavePowerPointDocs()
	}

	static SaveWordDocs(*) {
		try
			app := ComObjActive("Word.Application")
		catch
			return ; Word isn't running.
		try
			docs := app.Documents
		catch as Err {
			Log("Could not read Word.Documents: " Err.Message, "WARN", "PluginAutosave")
			return
		}
		Loop docs.Count
			this.SaveIfDirty(docs.Item(A_Index), "Word")
	}

	static SaveExcelDocs(*) {
		try
			app := ComObjActive("Excel.Application")
		catch
			return ; Excel isn't running.
		try
			docs := app.Workbooks
		catch as Err {
			Log("Could not read Excel.Workbooks: " Err.Message, "WARN", "PluginAutosave")
			return
		}
		Loop docs.Count
			this.SaveIfDirty(docs.Item(A_Index), "Excel")
	}

	static SavePowerPointDocs(*) {
		try
			app := ComObjActive("PowerPoint.Application")
		catch
			return ; PowerPoint isn't running.
		try
			docs := app.Presentations
		catch as Err {
			Log("Could not read PowerPoint.Presentations: " Err.Message, "WARN", "PluginAutosave")
			return
		}
		Loop docs.Count
			this.SaveIfDirty(docs.Item(A_Index), "PowerPoint")
	}

	static SaveIfDirty(doc, appLabel) { ; Save one document/workbook/presentation if it needs it.
		try {
			if (doc.Path = "")
				return ; File hasn't been saved. Save() would pop a Save As dialog, so leaving this up to the user.
			if doc.Saved
				return ; No unsaved changes.
			doc.Save()
		} catch as Err {
			this.NotifyFailure(appLabel, Err.Message)
		}
	}

	static NotifyFailure(appLabel, errMsg) { ; Log and surface a save failure.
		Log("Autosave failed for " appLabel ": " errMsg, "ERROR", "PluginAutosave")
		TrayTip appLabel ": " errMsg, this.T("notify_failure_title"), "Icon!"
	}
	
	static StopMonitoring(*) { ; Disable timer before shutting down the program, so save function doesn't get caught mid-shutdown.1
		SetTimer this.TimerHandler, 0
	}
	
	;## Settings tab ####################################################################
	static BuildSettingsTab(*) { ; Adds this addon's own page to the existing settings tab control.
			SettingsGui.Add("GroupBox",								"x" settings_tab_x0 " y" settings_tab_y0 " w" settings_tab_w " h170",	this.T("gb_settings_autosave"))
			this.ChkEnabled := SettingsGui.Add("CheckBox",			"xp+10 yp+20 w200 h23 Checked" this.GetSetting("Settings", "enabled", 1),			this.T("chk_enabled"))
			SettingsGui.Add("Text",									"y+8",				this.T("lbl_interval"))
			this.EditInterval := SettingsGui.Add("Edit",			"y+2 w60",			this.GetSetting("Settings", "interval_minutes", 5))
			this.ChkWord := SettingsGui.Add("CheckBox",				"y+10 w200 h23 Checked" this.GetSetting("Settings", "watch_word", 1),		this.T("chk_watch_word"))
			this.ChkExcel := SettingsGui.Add("CheckBox",			"y+1 w200 h23 Checked" this.GetSetting("Settings", "watch_excel", 1),		this.T("chk_watch_excel"))
			this.ChkPowerpoint := SettingsGui.Add("CheckBox",		"y+1 w200 h23 Checked" this.GetSetting("Settings", "watch_powerpoint", 1),	this.T("chk_watch_powerpoint"))
	}

	static SaveSettings(*) {
		; Called by the main Save button via the Settings_SaveSettings hook.
		; Returns false on any failed write, which SaveAddonSettings() reports as a failed save.
		intervalRaw := this.EditInterval.Value
		if !IsInteger(intervalRaw) || Integer(intervalRaw) < 1 {
			Log("Invalid autosave interval '" intervalRaw "', falling back to 5 minutes.", "WARN", "PluginAutosave")
			interval := 5
		} else {
			interval := Integer(intervalRaw)
		}

		ok := true
		ok := this.SaveSetting("Settings", "enabled", this.ChkEnabled.Value) && ok
		ok := this.SaveSetting("Settings", "interval_minutes", interval) && ok
		ok := this.SaveSetting("Settings", "watch_word", this.ChkWord.Value) && ok
		ok := this.SaveSetting("Settings", "watch_excel", this.ChkExcel.Value) && ok
		ok := this.SaveSetting("Settings", "watch_powerpoint", this.ChkPowerpoint.Value) && ok
		if !ok {
			Log("One or more autosave settings failed to write.", "ERROR", "PluginAutosave")
			return false
		}
		return true
	}
}