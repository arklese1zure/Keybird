;				=========================================================================
;				|||||						Desktop pet								|||||
;				=========================================================================

;## Included libraries and scripts ######################################################

class PluginMascot extends PluginBase {
	static settingsFile := A_WorkingDir "\userprofile\mascot.ini"
	
	static PluginKey := "mascot"
	; Formats GDI+ can decode (GdipCreateBitmapFromFile). exe/dll icon extraction in Gdip_All is deliberately not offered.
	static imageExtPattern := "i)^(png|gif|jpe?g|jpe|jfif|bmp|dib|tiff?|ico)$"

	static __New() { ;## Startup ########################################################
	;== Setup ===========================================================================
	this.mascotFolder := A_WorkingDir "\userprofile\mascot"
	this.defaultImage := A_WorkingDir "\addons\mascot\res\default.png" ; Bundled image, copied into mascotFolder on first run.
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
		this.mascotPreview := SettingsGui.Add("Picture",		"xp+10 yp+15 w128 h128") ; 128x128 preview area; SetPreview sizes and centers the image in it.
		this.mascotPreview.GetPos(&px, &py)
		this.previewBox := { x: px, y: py }
		this.SetPreview(this.mascotImageFullPath) ; Validated path, falls back to res\default.png.
		;== Startup =====================================================================
		SettingsGui.Add("GroupBox",								"x+10 y" settings_tab_y0 " w309 h45",	this.T("settings_gb_picker"))
		this.MascotDropDown := SettingsGui.Add("DropDownList",	"xp+8 yp+17 w206 r20",	[""])
		this.MascotDropDown.OnEvent("Change", ObjBindMethod(this, "LoadMascotPreview"))
		this.LoadMascotList()
		this.pendingImage := "" ; Full source path of a browsed image staged for copying on Save; "" if none.
		this.pendingName  := "" ; Name it will get inside mascotFolder (also its dropdown entry).
		BtnBrowse := SettingsGui.Add("Button",					"x+5 yp-1 w80 h23",	T("browse"))
		BtnBrowse.OnEvent("Click", ObjBindMethod(this, "BrowseMascotImage"))
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
		if pBitmap <= 0 { ; Image load failed. Log it and return FALSE.
			Log("Could not load mascot image: " this.mascotImageFullPath, "ERROR", "PluginMascot")
			return false
		}
		; Source size, and the size it will be displayed at (see GetDisplaySize).
		Gdip_GetImageDimensions(pBitmap, &w, &h)
		this.GetDisplaySize(w, h, &dw, &dh, &smooth)
		; Build a GDI device context exactly the displayed size, so nothing is cropped.
		hbm := CreateDIBSection(dw, dh)
		hdc := CreateCompatibleDC()
		obm := SelectObject(hdc, hbm)
		G   := Gdip_GraphicsFromHDC(hdc)
		if smooth {
			Gdip_SetInterpolationMode(G, 7) ; HighQualityBicubic — smooth downscaling.
		} else {
			Gdip_SetInterpolationMode(G, 5) ; NearestNeighbor — crisp 1:1 or integer upscaling.
			DllCall("gdiplus\GdipSetPixelOffsetMode", "Ptr", G, "Int", 4) ; PixelOffsetModeHalf — no half-pixel shift/edge bleed.
		}
		Gdip_DrawImage(G, pBitmap, 0, 0, dw, dh, 0, 0, w, h)
		; Paint the DC onto the layered window at the saved screen position.
		UpdateLayeredWindow(this.hwnd_mascotGui, hdc, this.mascot_window_x, this.mascot_window_y, dw, dh)
		; Release all GDI+ and GDI resources.
		SelectObject(hdc, obm)
		DeleteObject(hbm)
		DeleteDC(hdc)
		Gdip_DeleteGraphics(G)
		Gdip_DisposeImage(pBitmap)
		return true
	}

	static GetDisplaySize(w, h, &dw, &dh, &smooth, box := 128) { ; Decide how big a w×h image is shown.
		; Larger than the box: shrink to fit, keeping aspect ratio (smooth).
		; Fits in the box: grow by the largest whole factor that still fits (crisp), so tiny images stay clickable
		; without blurring. A 90px image stays 90px; a 1px image becomes 128px; a 40px image becomes 120px.
		if (w <= 0 || h <= 0) {
			dw := dh := box, smooth := true
			return
		}
		if (w > box || h > box) {
			s := Min(box / w, box / h)
			dw := Max(1, Round(w * s)), dh := Max(1, Round(h * s)), smooth := true
		} else {
			s := Max(1, Min(box // w, box // h))
			dw := w * s, dh := h * s, smooth := false
		}
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
		;== Prepare user mascot folder ==================================================
		this.SeedMascotFolder()
		if (this.mascot_currentimage = "" && FileExist(this.mascotFolder "\default.png"))
			this.mascot_currentimage := "default.png" ; Fresh install: preselect the seeded default.
		;== Validate image file =========================================================
		; Fall back to the bundled default if the saved image is blank or missing.
		mascotImagePath := this.mascotFolder "\" this.mascot_currentimage
		if (this.mascot_currentimage = "" || !FileExist(mascotImagePath))
			this.mascotImageFullPath := this.defaultImage
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

	static SeedMascotFolder(*) { ; Create userprofile\mascot and copy the bundled default into it if it has no images.
		if !this.EnsureFolder(this.mascotFolder)
			return false
		Loop Files this.mascotFolder "\*.*", "F"
			if this.IsImageFile(A_LoopFileName)
				return true ; Already has at least one image; leave the user's folder alone.
		try {
			FileCopy this.defaultImage, this.mascotFolder "\default.png"
			return true
		} catch as Err {
			Log("Could not copy default mascot image into '" this.mascotFolder "': " Err.Message, "WARN", "PluginMascot")
			return false
		}
	}

	static IsImageFile(fileName) { ; True if the file's extension is a format the mascot can load.
		SplitPath fileName, , , &ext
		return RegExMatch(ext, this.imageExtPattern) > 0
	}

	static LoadMascotList(*) { ; Fill mascot chooser dropdown.
		if !this.mascotFolder
			return
		folder := SubStr(this.mascotFolder, -1, 1) = "\" ? SubStr(this.mascotFolder, 1, -1) : this.mascotFolder
		Loop Files folder "\*", "F" { ; Files only; skip subfolders.
			if this.IsImageFile(A_LoopFileName) ; Skip non-images (.bak, .txt, Thumbs.db...) that would fail to load.
				this.MascotDropDown.Add([A_LoopFileName])
		}
		if this.mascot_currentimage
			this.MascotDropDown.Choose(this.mascot_currentimage)
	}

	static LoadMascotPreview(*) { ; Update preview picture when dropdown selection changes.
		selectedMascot := this.MascotDropDown.Text
		if (selectedMascot = "")
			return
		if (this.pendingImage != "" && selectedMascot = this.pendingName)
			this.SetPreview(this.pendingImage) ; Not copied yet; preview from its original location.
		else
			this.SetPreview(this.mascotFolder "\" selectedMascot)
	}

	static BrowseMascotImage(*) { ; Browse button: pick an image anywhere; it's copied into mascotFolder on Save.
		file := FileSelect(1, , this.T("settings_filedialog_image", "Choose a mascot image"),
			"Images (*.png; *.gif; *.jpg; *.jpeg; *.jpe; *.jfif; *.bmp; *.dib; *.tif; *.tiff; *.ico)")
		if file = ""
			return
		if !this.IsImageFile(file) { ; The dialog lets users type any name, so check anyway.
			Log("Unsupported mascot image format: " file, "WARN", "PluginMascot")
			return
		}
		SplitPath file, &fileName, &fileDir
		; Drop the entry of any image browsed earlier in this session but never saved.
		if (this.pendingName != "") {
			for i, item in ControlGetItems(this.MascotDropDown)
				if (item == this.pendingName) {
					this.MascotDropDown.Delete(i)
					break
				}
			this.pendingImage := "", this.pendingName := ""
		}
		if (StrLower(RTrim(fileDir, "\")) = StrLower(RTrim(this.mascotFolder, "\"))) {
			; Already in the mascot folder: just select it, nothing to copy.
			this.SelectMascotItem(fileName)
			this.SetPreview(file)
			return
		}
		fileName := this.UniqueMascotName(fileName)
		this.MascotDropDown.Add([fileName])
		this.SelectMascotItem(fileName)
		this.pendingImage := file, this.pendingName := fileName
		this.SetPreview(file)
	}

	static SelectMascotItem(name) { ; Select a dropdown entry by exact name (Choose("text") would match by prefix).
		items := ControlGetItems(this.MascotDropDown)
		for i, item in items
			if (item == name) {
				this.MascotDropDown.Value := i
				return true
			}
		this.MascotDropDown.Add([name]) ; Not listed yet (e.g. added to the folder after the tab was built).
		this.MascotDropDown.Value := items.Length + 1
		return true
	}

	static UniqueMascotName(fileName) { ; Append " (2)", " (3)"... so a browsed image never overwrites one in mascotFolder.
		SplitPath fileName, , , &ext, &nameNoExt
		candidate := fileName, n := 2
		while FileExist(this.mascotFolder "\" candidate)
			candidate := nameNoExt " (" n++ ")" (ext != "" ? "." ext : "")
		return candidate
	}

	static SetPreview(path) { ; Show path in the preview at the same size the mascot window will use, centered in the 128x128 area.
		w := h := 0
		if ((pBitmap := Gdip_CreateBitmapFromFile(path)) > 0) {
			Gdip_GetImageDimensions(pBitmap, &w, &h)
			Gdip_DisposeImage(pBitmap)
		}
		if (w <= 0 || h <= 0) {
			Log("Could not load mascot preview image: " path, "WARN", "PluginMascot")
			return false
		}
		this.GetDisplaySize(w, h, &dw, &dh, &smooth)
		this.mascotPreview.Value := "*w" dw " *h" dh " " path
		this.mascotPreview.Move(this.previewBox.x + (128 - dw) // 2, this.previewBox.y + (128 - dh) // 2, dw, dh)
		return true
	}

	static SaveMascotSettings(*) { ; Save settings when the settings GUI save button is pressed.
		; Copy a browsed image into the mascot folder, but only if it's still the one selected.
		if (this.pendingImage != "" && this.MascotDropDown.Text = this.pendingName) {
			if !this.EnsureFolder(this.mascotFolder)
				return FALSE
			try FileCopy this.pendingImage, this.mascotFolder "\" this.pendingName
			catch as Err {
				Log("Could not copy mascot image '" this.pendingImage "' into '" this.mascotFolder "': " Err.Message, "ERROR", "PluginMascot")
				return FALSE ; Abort the save/reload so the setting never points at a missing file.
			}
			this.pendingImage := "", this.pendingName := ""
		}
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
