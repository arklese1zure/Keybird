;				=========================================================================
;				|||||						Desktop pet								|||||
;				=========================================================================

;## Included libraries and scripts ######################################################

class PluginMascot extends PluginBase {
	static settingsFile := A_WorkingDir "\userprofile\mascot.ini"
	
	static PluginKey := "mascot"

	static __New() { ;## Startup ########################################################
	;== Setup ===========================================================================
	this.mascotFolder := A_WorkingDir "\userprofile\mascot"
	; Get the hwnd for the Windows taskbar. Used to assign window ownership so the mascot stays above it.
	this.Tray := WinExist("ahk_class Shell_TrayWnd")
	; Storage for Win32 hook handles that must outlive KeepOverTaskBar's stack frame.
	this.hookCallback	:= ""
	this.hHook			:= 0
	; Flag so Mascot_OnExit knows whether BuildGui actually succeeded.
	this.guiReady		:= false

	;== Hooks ===========================================================================
	Plugin_Settings_AddTab(ObjBindMethod(this, "BuildSettingsTab"), "Mascot", "mascot")
	Plugin_Main_LoadSettings(ObjBindMethod(this, "LoadMascotSettings"), "Mascot")
	Plugin_Main_OnStartUp(ObjBindMethod(this, "BuildGui"), "Mascot")
	Plugin_Main_LeftClick(ObjBindMethod(this, "HideMainGuiWindow"), "Mascot")
	Plugin_Main_RightClick(ObjBindMethod(this, "ShowMascotMenu"), "Mascot")
	Plugin_Settings_SaveSettings(ObjBindMethod(this, "SaveMascotSettings"), "Mascot")
	Plugin_Main_OnExit(ObjBindMethod(this, "Mascot_OnExit"), "Mascot")
	}

	static BuildGui(*) { ;## Build mascot window and render bitmap ######################
		if !this.CheckGDIP() ; Don't build anything if GDI+ isn't available.
			return
		this.mascotGui := Gui()
			; Layered window: no caption, always on top, no taskbar entry.
			; +E0x80000 is required for UpdateLayeredWindow to work.
			this.mascotGui.Opt("-Caption -DPIScale +E0x80000 +AlwaysOnTop +ToolWindow +Owner" this.Tray)
			this.KeepOverTaskBar(this.mascotGui.hwnd)
		this.mascotGui.Show("NoActivate w128 h128")
		this.hwnd_mascotGui := this.mascotGui.hwnd
		if !this.ApplyBitmap() { ; If ApplyBitmap returns false (failure), destroy the window.
			this.mascotGui.Destroy()
			return
		}
		this.guiReady := true ; Mark GUI as successfully built so exit handler can use it.
	}

	static BuildSettingsTab(*) { ;## Settings gui tab ###################################
		;== UI settings =================================================================
		SettingsGui.Add("GroupBox",								"x" settings_tab_x0 " y" settings_tab_y0 " w145 h145",		this.T("settings_gb_preview"))
		this.mascotPreview := SettingsGui.Add("Picture",		"xp+10 yp+15 w128 h128",	this.mascotFolder "\" this.mascot_currentimage)
		;== Startup =====================================================================
		SettingsGui.Add("GroupBox",								"x+10 y" settings_tab_y0 " w309 h45",	this.T("settings_gb_picker"))
		this.MascotDropDown := SettingsGui.Add("DropDownList",	"xp+8 yp+17 w206 r20",	[""])
		this.MascotDropDown.OnEvent("Change", ObjBindMethod(this, "LoadMascotPreview"))
		this.LoadMascotList()
		SettingsGui.Add("GroupBox",									"x" settings_tab_x0 " y160 w309 h95",						 this.T("settings_gb_options"))
		this.chkboxSaveScreenPos    := SettingsGui.Add("CheckBox",	"xp+7 yp+15 w290 h23 Checked" this.mascot_rememberscreenpos, this.T("settings_chkbox_screenpos"))
		this.chkboxKeepOnTop        := SettingsGui.Add("CheckBox",	"y+1 w290 h23 Checked" this.mascot_window_keepontop,         this.T("settings_chkbox_ontop"))
		this.chkboxShowContextMenu  := SettingsGui.Add("CheckBox",	"y+1 w290 h23 Checked" this.mascot_rcmenu_enabled,           this.T("settings_chkbox_rcmenu"))
	}

	;######### Functions ########################################################################
	;========= Actions ==========================================================================
	static HideMainGuiWindow(*) { ; Toggle the main gui when the mascot is left-clicked.
		global leftclickguihwnd
		if leftclickguihwnd = this.hwnd_mascotGui
			ToggleHideWindow() ; This function belongs to Keybird.ahk
	}

	static ShowMascotMenu(*) { ; Show the tray menu when the mascot is right-clicked.
		global rightclickguihwnd
		if rightclickguihwnd = this.hwnd_mascotGui
			A_TrayMenu.Show
	}

	;========= GDI+ drawing functions ===========================================================
	static ApplyBitmap(*) { ; Load image file and paint it onto the layered window.
		pBitmap := Gdip_CreateBitmapFromFile(this.mascotImageFullPath)
		if !pBitmap { ; Image load failed. Log it and return FALSE.
			Log("Could not load mascot image: " this.mascotImageFullPath, "ERROR", "PluginMascot")
			return false
		}
		; Get canvas dimensions from the loaded bitmap.
		w := Gdip_GetImageWidth(pBitmap)
		h := Gdip_GetImageHeight(pBitmap)
		; Build a GDI device context to draw into.
		hbm := CreateDIBSection(w, h)
		hdc := CreateCompatibleDC()
		obm := SelectObject(hdc, hbm)
		G   := Gdip_GraphicsFromHDC(hdc)
		Gdip_SetInterpolationMode(G, 7) ; HighQualityBicubic — smooth resizing.
		; Draw the loaded bitmap into the DC, scaled to 128x128.
		Gdip_DrawImage(G, pBitmap, 0, 0, 128, 128, 0, 0, w, h)
		; Paint the DC onto the layered window at the saved screen position.
		UpdateLayeredWindow(this.hwnd_mascotGui, hdc, this.mascot_window_x, this.mascot_window_y, w, h)
		; Release all GDI+ and GDI resources.
		SelectObject(hdc, obm)
		DeleteObject(hbm)
		DeleteDC(hdc)
		Gdip_DeleteGraphics(G)
		Gdip_DisposeImage(pBitmap)
		return true
	}

	static CheckGDIP(*) { ; Start GDI+. Returns false if unavailable so callers can act accordingly.
		global pToken := Gdip_Startup()
		if !pToken {
			Log("GDI+ failed to initialize — mascot will not be displayed.", "ERROR", "PluginMascot")
			return false
		}
		return true
	}

	static KeepOverTaskBar(guihwnd) { ; Use a Win32 event hook to keep mascot above the taskbar.
		; Round window corners on Windows 11.
		DllCall("dwmapi\DwmSetWindowAttribute", "ptr", guihwnd, "uint", 12, "uint*", 1, "uint", 4)
		; WinEventHookProc is a closure — it captures guihwnd from this stack frame.
		; The callback pointer and hook handle must be stored as instance properties or they get
		; garbage-collected when this function returns, silently killing the hook.
		WinEventHookProc(hWinEventHook, event, hwnd, idObject, idChild, dwEventThread, dwmsEventTime) {
			if !hwnd || idObject = 0xFFFFFFF7
				return
			; Use a one-shot timer so we're not blocking the event thread with a DllCall.
			SetTimer () => DllCall("SetWindowPos", "ptr", this.Tray, "ptr", guihwnd,
				"int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x10|0x2|0x200), -1
		}
		this.hookCallback := CallbackCreate(WinEventHookProc) ; Keep pointer alive.
		this.hHook := DllCall(
			"SetWinEventHook"
			, "UInt", 0x8005  ; EVENT_OBJECT_FOCUS
			, "UInt", 0x800B  ; EVENT_OBJECT_LOCATIONCHANGE
			, "Ptr",  0
			, "Ptr",  this.hookCallback
			, "UInt", 0, "UInt", 0, "UInt", 0x2
		)
		if !this.hHook
			Log("SetWinEventHook failed — mascot may not stay above taskbar.", "WARN", "PluginMascot")
	}

	;========= Settings tab functions ===========================================================
	static LoadMascotSettings(*) { ; Read settings on load — uses GetSetting so missing keys return safe defaults.
		global screenSizeChanged
		this.mascot_currentimage      := this.GetSetting("Main",   	     "mascot_currentimage",      "")
		this.mascot_rememberscreenpos := this.GetSetting("Positioning",  "mascot_rememberscreenpos", 1)
		this.mascot_window_keepontop  := this.GetSetting("Positioning",  "mascot_window_keepontop",  1)
		this.mascot_rcmenu_enabled    := this.GetSetting("Features",     "mascot_rcmenu_enabled",    1)
		;== Validate image file =========================================================
		; Fall back to the bundled default if the saved image is blank or missing.
		mascotImagePath := this.mascotFolder "\" this.mascot_currentimage
		if (this.mascot_currentimage = "" || !FileExist(mascotImagePath))
			this.mascotImageFullPath := A_WorkingDir "\addons\mascot\res\default.png"
		else
			this.mascotImageFullPath := mascotImagePath
		;== Window position =============================================================
		; Reset to a safe position if the screen size changed since last launch.
		if screenSizeChanged {
			this.mascot_window_x := 400
			this.mascot_window_y := 300
		} else {
			this.mascot_window_x := this.GetSetting("Positioning", "mascot_window_x", 400)
			this.mascot_window_y := this.GetSetting("Positioning", "mascot_window_y", 300)
		}
	}

	static LoadMascotList(*) { ; Fill mascot chooser dropdown.
		if !this.mascotFolder
			return
		folder := SubStr(this.mascotFolder, -1, 1) = "\" ? SubStr(this.mascotFolder, 1, -1) : this.mascotFolder
		Loop Files folder "\*" {
			this.MascotDropDown.Add([A_LoopFileName])
		}
		if this.mascot_currentimage
			this.MascotDropDown.Choose(this.mascot_currentimage)
	}

	static LoadMascotPreview(*) { ; Update preview picture when dropdown selection changes.
		selectedMascot := this.MascotDropDown.Text
		if (selectedMascot = "")
			return
		this.mascotPreview.Value := this.mascotFolder "\" selectedMascot
	}

	static SaveMascotSettings(*) { ; Save settings when the settings GUI save button is pressed.
		this.SaveSetting("Main",       "mascot_currentimage",      this.MascotDropDown.Text)
		this.SaveSetting("Positioning", "mascot_rememberscreenpos", this.chkboxSaveScreenPos.Value)
		this.SaveSetting("Positioning", "mascot_window_keepontop",  this.chkboxKeepOnTop.Value)
		this.SaveSetting("Features",   "mascot_rcmenu_enabled",    this.chkboxShowContextMenu.Value)
		return TRUE
	}

	static Mascot_OnExit(*) { ; Save position and clean up GDI+ and the Win32 event hook.
		; Save window position only if the GUI was successfully built and the user wants it remembered.
		if this.guiReady && this.mascot_rememberscreenpos {
			try {
				this.mascotGui.GetPos(&X, &Y)
				this.SaveSetting("Positioning", "mascot_window_x", X)
				this.SaveSetting("Positioning", "mascot_window_y", Y)
			} catch as Err {
				LogInfo("Could not save mascot position: " Err.Message, "PluginMascot")
			}
		}
		; Unhook the Win32 event hook before freeing the callback, in that order.
		; Freeing the callback while the hook is still live would crash the process.
		if this.hHook {
			DllCall("UnhookWinEvent", "Ptr", this.hHook)
			this.hHook := 0
		}
		if this.hookCallback {
			CallbackFree(this.hookCallback)
			this.hookCallback := ""
		}
		; Shut down GDI+ last — other cleanup may still use GDI resources.
		global pToken
		if pToken {
			Gdip_Shutdown(pToken)
			pToken := 0
		}
	}
}
