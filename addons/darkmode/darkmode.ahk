;				=========================================================================
;				|||||					Dark Mode Toggle							|||||
;				=========================================================================
;
;	One-click toggle for Windows 11's light/dark theme, via the same HKCU registry keys
;	Settings > Personalization > Colors writes to. Manual toggle only.
;
;	Compatibility: AppsUseLightTheme didn't exist before Windows 10 1607 (build 14393).
;	Windows 7/8/8.1 and early Windows 10 have no app/system dark theme at all.
;	Unsupported systems will not see the menu option; this plugin is essentially useless
;	in that case.
;	Scoped to HKCU, so no elevation is needed.

class PluginDarkMode extends PluginBase {

	static PluginKey	:= "darkmode" ; internal plugin name, must match lang\en.ini section
	static RegKey		:= "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
	static MinBuild		:= 14393 ; This is Windows 10 1607 (Anniversary Update).

	static __New() { ;## Startup ########################################################
		if this.IsDarkModeSupported() ; Check if current Windows version is compatible.
			Plugin_AddMainMenuItem(ObjBindMethod(this, "ToggleDarkMode"), "Windows Dark Mode", "darkmode")
		else
			Log("Windows build " A_OSVersion " doesn't support AppsUseLightTheme. Menu item skipped.", "INFO", "PluginDarkMode")
	}

	;## Compatibility ####################################################################
	static IsDarkModeSupported(*) { ; Check if dark mode is supported by parsing the windows version.
		try {
			parts := StrSplit(A_OSVersion, ".") ; Split the build number, we'll use the last bit.
			build := Integer(parts[3])
			return build >= this.MinBuild
		} catch {
			return false ; Unparseable OS version string.
		}
	}

	;## Toggle ###########################################################################
	static ToggleDarkMode(*) {
		try {
			current  := RegRead(this.RegKey, "AppsUseLightTheme", 1) ; Default to light if the key doesn't exist yet.
			newValue := current ? 0 : 1 ; Flip: 1 = light, 0 = dark.
			RegWrite newValue, "REG_DWORD", this.RegKey, "AppsUseLightTheme"   ; App theme (this app, Settings, etc).
			RegWrite newValue, "REG_DWORD", this.RegKey, "SystemUsesLightTheme" ; Taskbar/Start theme.
			this.BroadcastThemeChange()
		} catch as Err {
			Log("Could not toggle dark mode: " Err.Message, "ERROR", "PluginDarkMode")
		}
	}

	static BroadcastThemeChange(*) { ; Broadcast theme change via DllCall so it shows up immediately.
	; Tell Explorer and other running apps to re-read the theme immediately, so the change
	; is visible without a logoff/logon. This is the same message Windows Settings sends.
	; SendNotifyMessage won't wait for apps to respond, unlike the SendMessageTimeout method.
		DllCall("SendNotifyMessage"
			, "Ptr",  0xFFFF					; HWND_BROADCAST.
			, "UInt", 0x1A						; WM_SETTINGCHANGE.
			, "Ptr",  0							; wParam, unused.
			, "Str",  "ImmersiveColorSet"		; lParam, the specific setting that changed.
			, "UInt", 0x02						; SMTO_ABORTIFHUNG.
			, "UInt", 100						; Timeout in ms per receiving window.
			, "Ptr*", &result := 0)
	}
}
