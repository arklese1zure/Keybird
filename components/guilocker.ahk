
;		=========================================================================
;		|||||					KeyBird — GUI Locker						|||||
;		=========================================================================
;
;	Provides password-based locking of the main GUI and all hotkeys.
;	Integrates with the startup sequence in Keybird.ahk via GuiLocker.InitLock().
;	Settings are stored in userprofile\guilocker.ini.

class GuiLocker {

	static settingsFile		:= A_WorkingDir "\userprofile\guilocker.ini"
	static isLocked			:= false
	static wrongAttempts	:= 0
	static trayLockKeys		:= ["disable_keys", "keep_visible", "disable_sleep", "settings", "addons"] ; Tray menu are disabled while locked. Exit and Lock stay available.

	static __New() { ;## Startup ########################################################
		;== Register hooks ==============================================================
		Plugin_Settings_AddTab(ObjBindMethod(this, "BuildSettingsTab"), "Locker")
		Plugin_Settings_SaveSettings(ObjBindMethod(this, "SaveSettings"), "Locker")

		;== Load settings ===============================================================
		this.startup_locked	:= this.GetSetting("StartupSettings", "startup_guilocked", "FALSE") = "TRUE"
		this.password		:= this.GetSetting("PasswordLock", "gui_password", "")
	}

	;## Settings helpers ################################################################
	static GetSetting(section, key, default := "") {
		try
			return IniRead(this.settingsFile, section, key, default)
		catch
			return default
	}

	static SaveSetting(section, key, value) {
		if !IsWorkingDirAccessible() {
			Log("Drive not accessible, cannot save locker setting.", "WARN", "GuiLocker")
			return false
		}
		try {
			IniWrite value, this.settingsFile, section, key
			return true
		} catch as Err {
			Log("Could not save locker setting [" section "] " key ": " Err.Message, "ERROR", "GuiLocker")
			return false
		}
	}

	;## Startup lock ####################################################################
	static InitLock() { ; Called from Keybird.ahk before mainGui.Show(). Handles lock-on-startup.
		if (!this.startup_locked || this.password = "") {
			; Not locked or no password set -> start normally.
			; Show a one-time hint in the tray tooltip if no password has been configured yet.
			if (this.password = "")
				Log("No lock password set. Go to Settings > Locker to configure one.", "INFO", "GuiLocker")
			return
		}
		; Lock immediately: suspend hotkeys, hide window, show prompt.
		this.ApplyLock()
		this.ShowLockPrompt()
	}

	;## Lock / Unlock ###################################################################
	static ApplyLock() { ; Suspend hotkeys, hide the main window, update tray state.
		global disable_standby
		Hotkeys.SetLocked(true)
		this.resumeStayAwake := disable_standby ; Remember it so unlocking restores the user's state.
		if disable_standby
			ToggleStayAwake() ; It's a toggle: only call it when keep-awake is actually on.
		SetMainWindowVisible(false) ; Hides it (nothing happens if it's already hidden).
		this.isLocked := true
		this.SetTrayItemsEnabled(false)
		A_TrayMenu.ToggleCheck(MenuLabel(A_TrayMenu, "lock_app"))
		UpdateTrayTooltip()
		OnMainGuiLock() ; On unlock hook. Let addons be aware of the event (e.g. resume timers, monitors and popups).
	}
	
	static ApplyUnlock() { ; Resume hotkeys, show the main window, update tray state.
		global disable_standby
		Hotkeys.SetLocked(false) ; Stays suspended if the user disabled hotkeys from the tray.
		SetMainWindowVisible(true)
		this.isLocked := false
		this.SetTrayItemsEnabled(true)
		this.wrongAttempts := 0
		A_TrayMenu.ToggleCheck(MenuLabel(A_TrayMenu, "lock_app"))
		if (this.resumeStayAwake && !disable_standby)
		ToggleStayAwake()
		this.resumeStayAwake := false
		OnMainGuiUnlock() ; On unlock hook, similar to OnMainGuiLock.
	}

	static SetTrayItemsEnabled(enabled) { ; Enable or disable the tray entries listed in trayLockKeys.
		for _, key in this.trayLockKeys {
			label := MenuLabel(A_TrayMenu, key) ; Logs and returns "" if the key was never registered.
			if label = ""
				continue
			if enabled
				A_TrayMenu.Enable(label)
			else
				A_TrayMenu.Disable(label)
		}
	}

	static LockFromMenu(*) { ; Called from the main menu.
		if this.isLocked {
			this.ShowLockPrompt()
			return
		}
		if (this.password = "") {
			MsgBox(T("msgbox_err_nopasswd"), programinfo.name, 48)
			return
		}
		this.ApplyLock()
	}

	;## Lock prompt #####################################################################
	static ShowLockPrompt() { ; Minimal always-on-top password prompt.
		this.LockGui := Gui()
		this.LockGui.Opt("+AlwaysOnTop -SysMenu +ToolWindow +OwnDialogs")
		this.LockGui.Title := programinfo.name
		this.LockGui.MarginX := 12
		this.LockGui.MarginY := 12

		this.LockGui.Add("Text",, T("text_guilocked"))
		this.LockGui.Add("Text", "y+4 cGray", T("text_passwdprompt"))
		this.PromptField := this.LockGui.Add("Edit", "y+10 w200 +Password")
		BtnUnlock := this.LockGui.Add("Button", "y+8 w95 Default", "Unlock")
			BtnUnlock.OnEvent("Click", ObjBindMethod(this, "TryUnlock"))
		BtnCancel := this.LockGui.Add("Button", "x+10 w95", "Cancel")
			BtnCancel.OnEvent("Click", ObjBindMethod(this, "CancelPrompt"))

		this.LockGui.OnEvent("Close",  ObjBindMethod(this, "CancelPrompt"))
		this.LockGui.OnEvent("Escape", ObjBindMethod(this, "CancelPrompt"))
		this.LockGui.Show("AutoSize")
		WinActivate "ahk_id " this.LockGui.hwnd
	}

	static TryUnlock(*) { ; Validate the entered password.
		entered := this.PromptField.Value
		if (entered = this.password) {
			this.LockGui.Destroy()
			this.ApplyUnlock()
		} else {
			this.wrongAttempts++
			this.PromptField.Value := ""
			; Brief delay after repeated failures to slow brute force attempts.
			if (this.wrongAttempts >= 3)
				Sleep this.wrongAttempts * 500
			MsgBox(T("msgbox_wrongpasswd"), programinfo.name, 48)
			this.PromptField.Focus()
		}
	}

	static CancelPrompt(*) { ; Dismiss the prompt — stay locked, shrink to tray.
		this.LockGui.Destroy()
		; Remain locked and hidden. User can right-click the tray icon to try again.
	}

	;## Settings tab ####################################################################
	static BuildSettingsTab(*) {
		;-- Startup behaviour -----------------------------------------------------------
		SettingsGui.Add("GroupBox", "x" settings_tab_x0 " y" settings_tab_y0 " w461 h45", T("gb_settings_lockerstartup"))
		this.ChkStartLocked := SettingsGui.Add("CheckBox", "xp+10 yp+20 w430", T("chkbox_settings_startlocked"))
			this.ChkStartLocked.Value := this.startup_locked ? 1 : 0

		;-- Password change -------------------------------------------------------------
		SettingsGui.Add("GroupBox", "x" settings_tab_x0 " y+30 w461 h135", T("gb_settings_lockerpasswd"))
		SettingsGui.Add("Text", "xp+10 y95 w120 +0x200", T("text_settings_lockercurrpasswd"))
		SettingsGui.Add("Text", "xp y+18 w120 +0x200", T("text_settings_lockernewpasswd"))
		SettingsGui.Add("Text", "xp y+18 w120 +0x200", T("text_settings_lockerconfpasswd"))
		this.PrevPasswd    := SettingsGui.Add("Edit", "xp+90 y90 w200 +Password")
		this.NewPasswd     := SettingsGui.Add("Edit", "xp y+10  w200 +Password")
		this.ConfirmPasswd := SettingsGui.Add("Edit", "xp y+10  w200 +Password")
		BtnPeek := SettingsGui.Add("Button", "x+8 y101 w60", "Show")
			BtnPeek.OnEvent("Click", ObjBindMethod(this, "TogglePasswordVisibility"))

		;-- Info text -------------------------------------------------------------------
		infoText := (this.password = "")
			? T("text_settings_lockernopasswd")
			: T("text_settings_lockersetpasswd")
		SettingsGui.Add("Text", "x" settings_tab_x0 " y228 w461 cGray", infoText)

		this.passwordFieldVisible := false
	}

	static TogglePasswordVisibility(*) {
		this.passwordFieldVisible := !this.passwordFieldVisible
		opt := this.passwordFieldVisible ? "-Password" : "+Password"
		this.PrevPasswd.Opt(opt)
		this.NewPasswd.Opt(opt)
		this.ConfirmPasswd.Opt(opt)
	}

	static SaveSettings(*) {
		newPw     := this.NewPasswd.Value
		confirmPw := this.ConfirmPasswd.Value
		currentPw := this.PrevPasswd.Value

		; Validate first, write second.
		if (newPw != "") {
			if (this.password != "" && currentPw != this.password) {
				MsgBox(T("msgbox_settings_lockerwrongpasswd"), programinfo.name, 48)
				return false
			}
			if (newPw != confirmPw) {
				MsgBox(T("msgbox_settings_lockerpasswdmismatch"), programinfo.name, 48)
				return false
			}
		}

		ok := this.SaveSetting("StartupSettings", "startup_guilocked", this.ChkStartLocked.Value ? "TRUE" : "FALSE")
		if ok
			this.startup_locked := (this.ChkStartLocked.Value = 1)
		if (newPw != "") {
			if this.SaveSetting("PasswordLock", "gui_password", newPw)
				this.password := newPw
			else
				ok := false
		}
		return ok
	}
}
