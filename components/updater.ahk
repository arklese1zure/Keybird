
;		=========================================================================
;		|||||					Keybird - Update checker					|||||
;		=========================================================================
; Asks GitHub for the latest published release and tells the user when it's newer
; than ProgramInfo.Version. Notify-only: nothing is downloaded or installed.
;
; Automatic check: a few seconds after startup, at most once every CheckIntervalHours,
; only when "Check for updates automatically" is on. A newer release adds an
; "Update available" entry to the Help menu and, once per version, shows a TrayTip.
; Manual check: Help menu > "Check for updates". Always runs and always reports back.
;
; Releasing: tag the release with the same version as ProgramInfo.Version (e.g. v0.2.0).
; GitHub's /releases/latest skips drafts and pre-releases, so those never trigger a notice.

;## Settings (read by ReadSettings in settings.ahk) ##############################
;	[UpdateSettings]
;	update_autocheck		1/0. Automatic checks on startup.
;	update_lastcheck		Timestamp (YYYYMMDDHH24MISS) of the last successful check.
;	update_notifiedversion	Last version a TrayTip was shown for, so it isn't repeated every day.

class Updater {
	static StartupDelayMs		:= 10000	; Wait after launch so the check never competes with startup.
	static CheckIntervalHours	:= 24		; Automatic checks happen at most this often.
	static TimeoutMs			:= 15000	; Give up on a request after this long.
	static PollMs				:= 250		; How often the pending request is polled.
	static NotesMaxChars		:= 800		; Release notes longer than this are cut in the dialog.

	static request			:= ""		; In-flight WinHttp request, or "" when idle.
	static requestStarted	:= 0
	static isManual			:= false	; Whether the current check should report its result to the user.
	static pollTimer		:= ""
	static latest			:= ""		; {version, url, notes} of a newer release, once one is found.
	static menuLabel		:= ""		; Text of the "Update available" Help menu entry, once added.
	static balloonPending	:= false	; True while our TrayTip is on screen, so clicks on it can be told apart from other TrayTips.

	static ApiUrl() => "https://api.github.com/repos/" ProgramInfo.Repo "/releases/latest"

	;## Entry points ################################################################
	static Start() { ; Called once at startup.
		global update_autocheck
		OnMessage(0x404, ObjBindMethod(this, "OnTrayNotify")) ; AHK_NOTIFYICON, to catch clicks on the TrayTip.
		if update_autocheck
			SetTimer(() => this.AutoCheck(), -this.StartupDelayMs)
	}

	static CheckNow(*) { ; Help menu > Check for updates.
		if this.latest != "" { ; Already know about one this session, no need to ask again.
			this.ShowUpdateDialog()
			return
		}
		this.Check(true)
	}

	static AutoCheck() {
		global update_lastcheck
		if update_lastcheck != "" {
			try {
				if DateDiff(A_Now, update_lastcheck, "Hours") < this.CheckIntervalHours
					return
			} ; A malformed timestamp just means "check now".
		}
		this.Check(false)
	}

	;## Request #####################################################################
	static Check(manual) {
		if this.request != "" { ; A check is already running; a manual request upgrades it so the result gets shown.
			this.isManual := this.isManual || manual
			return
		}
		this.isManual := manual
		try {
			req := ComObject("WinHttp.WinHttpRequest.5.1")
			req.Open("GET", this.ApiUrl(), true) ; true = async. Polled by a timer so the GUI never freezes.
			req.SetRequestHeader("User-Agent", ProgramInfo.Name "-UpdateCheck/" ProgramInfo.Version) ; GitHub rejects requests without one.
			req.SetRequestHeader("Accept", "application/vnd.github+json")
			req.Send()
		} catch as Err {
			this.Fail("Could not start the request: " Err.Message)
			return
		}
		this.request := req
		this.requestStarted := A_TickCount
		this.pollTimer := ObjBindMethod(this, "Poll")
		SetTimer(this.pollTimer, this.PollMs)
	}

	static Poll() {
		req := this.request
		try
			done := req.WaitForResponse(0) ; 0 = don't wait, just report whether it finished.
		catch as Err { ; Offline, DNS failure, TLS error...
			this.StopPolling()
			this.Fail("Network error: " Trim(Err.Message))
			return
		}
		if !done {
			if A_TickCount - this.requestStarted > this.TimeoutMs {
				try req.Abort()
				this.StopPolling()
				this.Fail("The request timed out.")
			}
			return
		}
		this.StopPolling()
		this.HandleResponse(req)
	}

	static StopPolling() {
		if this.pollTimer != ""
			SetTimer(this.pollTimer, 0)
		this.pollTimer := ""
		this.request := ""
	}

	static HandleResponse(req) {
		status := req.Status
		if status = 404 {
			this.Fail("No published release found for " ProgramInfo.Repo " (the repository may be private or have no releases yet).")
			return
		}
		if status = 403 || status = 429 {
			this.Fail("GitHub's rate limit was reached. Try again later.")
			return
		}
		if status != 200 {
			this.Fail("GitHub answered with HTTP " status ".")
			return
		}
		try {
			release := JSON.parse(req.ResponseText, , false) ; as_map := false -> plain Object.
			tag := release.HasProp("tag_name") ? release.tag_name : ""
			url := release.HasProp("html_url") ? release.html_url : ""
			notes := release.HasProp("body") ? release.body : ""
			if tag = "" || url = ""
				throw Error("The response has no tag_name or html_url.")
		} catch as Err {
			this.Fail("Could not read GitHub's response: " Err.Message)
			return
		}
		this.SaveSetting("update_lastcheck", A_Now)
		if CompareVersions(tag, ProgramInfo.Version) > 0
			this.OnUpdateFound(tag, url, notes)
		else if this.isManual
			MsgBox(Format(T("msgbox_update_uptodate"), "v" ProgramInfo.Version), ProgramInfo.Name, "64")
	}

	static Fail(reason) { ; Automatic checks fail quietly into the log. Manual ones tell the user.
		Log("Update check failed: " reason, "INFO", "Updater")
		if this.isManual
			MsgBox(T("msgbox_update_failed") "`n`n" reason, ProgramInfo.Name, "48")
	}

	;## Notifying ###################################################################
	static OnUpdateFound(version, url, notes) {
		global update_notifiedversion
		this.latest := { version: version, url: url, notes: notes }
		this.AddMenuEntry(version)
		if this.isManual {
			this.ShowUpdateDialog()
			return
		}
		if version = update_notifiedversion ; Already told them about this one; the Help menu entry is enough.
			return
		this.balloonPending := true
		TrayTip(Format(T("traytip_update_text"), version), T("traytip_update_title"), "Iconi")
		update_notifiedversion := version
		this.SaveSetting("update_notifiedversion", version)
	}

	static AddMenuEntry(version) { ; Persistent, low-key reminder at the top of the Help menu.
		global HelpMenu
		label := Format(T("menu_update_available"), version)
		if this.menuLabel = label
			return
		if this.menuLabel != "" {
			HelpMenu.Rename(this.menuLabel, label)
		} else {
			HelpMenu.Insert("1&", label, (*) => this.ShowUpdateDialog())
			HelpMenu.Insert("2&") ; Separator.
		}
		this.menuLabel := label
	}

	static ShowUpdateDialog(*) {
		if this.latest = ""
			return
		notes := Trim(this.latest.notes, " `t`r`n")
		if StrLen(notes) > this.NotesMaxChars
			notes := SubStr(notes, 1, this.NotesMaxChars) "…"
		text := Format(T("msgbox_update_available"), this.latest.version, "v" ProgramInfo.Version)
		if notes != ""
			text .= "`n`n" T("msgbox_update_notes") "`n" notes
		text .= "`n`n" T("msgbox_update_open")
		if MsgBox(text, ProgramInfo.Name, "YesNo Iconi") = "Yes" {
			try Run(this.latest.url)
			catch as Err
				Log("Could not open the release page: " Err.Message, "WARN", "Updater")
		}
	}

	static OnTrayNotify(wParam, lParam, msg, hwnd) { ; AHK_NOTIFYICON. Must not return a value, so AHK keeps handling tray clicks normally.
		if !this.balloonPending
			return
		event := lParam & 0xFFFF
		if event = 0x405 { ; NIN_BALLOONUSERCLICK
			this.balloonPending := false
			SetTimer(() => this.ShowUpdateDialog(), -1) ; Leave the message handler before showing a dialog.
		} else if event = 0x403 || event = 0x404 ; NIN_BALLOONHIDE / NIN_BALLOONTIMEOUT
			this.balloonPending := false
	}

	;## Helpers #####################################################################
	static SaveSetting(key, value) {
		global settingsFile
		if !IsWorkingDirAccessible()
			return
		try IniWrite(value, settingsFile, "UpdateSettings", key)
		catch as Err
			Log("Could not save " key ": " Err.Message, "INFO", "Updater")
	}
}
