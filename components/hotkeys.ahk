
;		=========================================================================
;		|||||						KeyBird - Hotkeys						|||||
;		=========================================================================
;
;	The main script owns and manages all hotkeys to prevent conflicts between addons.
;	Priority is user-assigned > addon defaults > script defaults. The first registered gets priority.
;	Addons register what hotkeys they want; Hotkeys.Start() settles conflicts and binds the "winners".
;	The "loser" stays unbound and is logged at INFO.
;	CAUTION: Static `::` hotkeys, hotstrings and other scripts' hotkeys can't be seen from here.
;
;	USAGE:
;	Registering can be done from an addon's __New() or an OnStartUp hook:
;		Plugin_AddHotkey("snippets.popup", "^F2", this.HotkeyHandler)
;		Plugin_AddHotkey("clipboard.altpaste", "^!v", this.AltPasteFn, {enabled: false})
;	  id	<pluginKey>.<action>. Stable: user overrides are stored by id in userprofile\hotkeys.json, never by key text.
;	  opts	{enabled: false} registers the hotkey switched off until the user turns it on.
;
;	Start() runs once per launch, so enabling or rebinding applies on the reload that saving settings triggers.
;	Settings > Hotkeys (registered by Start()) lists everything and lets the user rebind, enable and disable. The name shown
;	for a hotkey comes from the lang key <pluginKey>.hotkey_<action> (for example [snippets] hotkey_popup), falling back to the id.
;	Suspend has a single owner (this class): the tray's "Disable hotkeys" and the lock both go through it.

;## Public registration function ################################################
Plugin_AddHotkey(id, defaultKey, fn, opts := "") { ; Register a hotkey with the main script. Returns false (and logs) if it was rejected.
	; id			- "<pluginKey>.<action>", e.g. "snippets.popup".
	; defaultKey	- AutoHotkey hotkey name, e.g. "^F2". "" registers it unassigned.
	; fn			- Function object to call. It receives no parameters.
	; opts			- Optional object. {enabled: false} = off until the user turns it on.
	return Hotkeys.Add(id, defaultKey, fn, opts)
}

class Hotkeys {

	static filePath			:= A_WorkingDir "\userprofile\hotkeys.json"
	static entries			:= Map()	; id -> entry. A Map enumerates sorted by key, so registration order is kept in 'order'.
	static order			:= []		; Ids in registration order. Breaks ties: first registered wins.
	static overrides		:= Map()	; id -> Map("key", ..., "enabled", ...). Only what the user changed, as read from hotkeys.json.
	static started			:= false
	static userSuspended	:= false	; Tray: "Disable hotkeys".
	static locked			:= false	; GuiLocker.
	static capturing		:= false	; Settings panel: a Hotkey control has focus, so hotkeys must not fire while the user presses keys in it.
	static pending			:= Map()	; Settings panel: id -> Map("key", ..., "enabled", ...), staged until the user saves.

	;## Registration ################################################################
	static Add(id, defaultKey, fn, opts := "") { ; Record a hotkey. Nothing is bound until Start().
		if this.started {
			Log("Hotkey '" id "' was registered after Hotkeys.Start() and was ignored. Register from __New() or an OnStartUp hook.", "WARN", "Hotkeys")
			return false
		}
		if !RegExMatch(id, "^\w+\.\w+$") {
			Log("Hotkey id '" id "' is not valid. Use <pluginKey>.<action>, e.g. snippets.popup.", "WARN", "Hotkeys")
			return false
		}
		if this.entries.Has(id) {
			Log("A hotkey with id '" id "' is already registered and was not added again.", "WARN", "Hotkeys")
			return false
		}
		if !HasMethod(fn, "Call") {
			Log("Hotkey '" id "' was not registered: the callback isn't callable. Pass the function itself (MyFunc), not its result (MyFunc()).", "WARN", "Hotkeys")
			return false
		}
		enabled := true
		if (IsObject(opts) && opts.HasProp("enabled"))
			enabled := opts.enabled ? true : false
		dot := InStr(id, ".")
		this.entries[id] := {
			id:				id,
			owner:			SubStr(id, 1, dot - 1),	; The pluginKey.
			action:			SubStr(id, dot + 1),
			fn:				fn,
			defaultKey:		defaultKey,
			defaultEnabled:	enabled,
			key:			defaultKey,		; Effective values. Settled by Resolve().
			userKey:		false,			; True if 'key' comes from the user's override.
			enabled:		enabled,
			status:			"pending",		; "ok", "conflict", "disabled", "unassigned" or "error" once resolved.
			conflictWith:	"",				; Id of the hotkey that holds the key, if status is "conflict".
			errorText:		""
		}
		this.order.Push(id)
		return true
	}

	;## Startup ######################################################################
	static Start() { ; Load the user's overrides, settle conflicts and bind. Called once from Keybird.ahk.
		if this.started
			return
		this.started := true
		Plugin_Settings_AddTab(ObjBindMethod(this, "BuildSettingsTab"), "Hotkeys", "hotkeys") ; Registered here, not in __New, so its place among the tabs doesn't depend on which addon registers a hotkey first.
		Plugin_Settings_SaveSettings(ObjBindMethod(this, "SaveSettings"), "Hotkeys")
		this.LoadOverrides()
		this.Resolve()
		this.BindAll()
		counts := Map()
		for id in this.order
			counts[this.entries[id].status] := counts.Get(this.entries[id].status, 0) + 1
		Log(this.order.Length " hotkey(s) registered: " counts.Get("ok", 0) " active, " counts.Get("conflict", 0) " in conflict, "
			. counts.Get("disabled", 0) " disabled, " counts.Get("unassigned", 0) " unassigned, " counts.Get("error", 0) " failed to bind.", "INFO", "Hotkeys")
	}

	static LoadOverrides() { ; Read userprofile\hotkeys.json. A missing file just means "no overrides".
		this.overrides := Map()
		if !FileExist(this.filePath)
			return
		try {
			data := JSON.parse(FileRead(this.filePath, "UTF-8"), , true) ; as_map := true. Booleans come back as 1/0.
			if !(data is Map) || !data.Has("overrides") || !(data["overrides"] is Map)
				throw Error('Unexpected structure, expected an "overrides" object.')
			for id, ov in data["overrides"] {
				if (ov is Map)
					this.overrides[id] := ov
			}
		} catch as Err {
			Log("Could not read '" this.filePath "', using the default hotkeys: " Hooks_ErrorText(Err), "WARN", "Hotkeys")
			this.overrides := Map()
		}
	}

	static Resolve() { ; Work out each entry's effective key and state, then settle who gets which key.
		for id in this.order {
			e := this.entries[id]
			ov := this.overrides.Has(id) ? this.overrides[id] : ""
			e.userKey := (ov is Map) && ov.Has("key")
			e.key := e.userKey ? String(ov["key"]) : e.defaultKey
			e.enabled := ((ov is Map) && ov.Has("enabled")) ? (ov["enabled"] ? true : false) : e.defaultEnabled
			e.conflictWith := ""
			if !e.enabled
				e.status := "disabled"
			else if (Trim(e.key) = "")
				e.status := "unassigned"
			else
				e.status := "candidate"
		}

		; Pass 1 hands out the keys the user chose, pass 2 the addons' defaults. Registration order breaks ties inside a pass.
		claimed := Map() ; Canonical key -> id that holds it.
		for pass in [1, 2] {
			for id in this.order {
				e := this.entries[id]
				if (e.status != "candidate")
					continue
				if (pass = 1 && !e.userKey) || (pass = 2 && e.userKey)
					continue
				canon := this.ParseKey(e.key).canon
				if claimed.Has(canon) {
					e.status := "conflict"
					e.conflictWith := claimed[canon]
					Log("Hotkey '" id "' wants " e.key ", which '" e.conflictWith "' already holds. It was left unbound.", "INFO", "Hotkeys")
				} else {
					claimed[canon] := id
					e.status := "ok"
				}
			}
		}

		; A wildcard (*) hotkey also fires for the same key with other modifiers. Not blocked, just logged.
		winners := []
		for id in this.order {
			if (this.entries[id].status = "ok")
				winners.Push(this.entries[id])
		}
		for i, a in winners {
			pa := this.ParseKey(a.key)
			Loop (winners.Length - i) {
				b := winners[i + A_Index]
				pb := this.ParseKey(b.key)
				if (pa.main = pb.main && (pa.wildcard || pb.wildcard) && pa.canon != pb.canon)
					Log("Hotkeys '" a.id "' (" a.key ") and '" b.id "' (" b.key ") overlap: the wildcard one also fires for the other's key combination.", "INFO", "Hotkeys")
			}
		}
	}

	static BindAll() { ; Bind every entry that won its key.
		HotIf() ; Global context. A leftover HotIf criteria would turn these into context-sensitive variants.
		for id in this.order {
			e := this.entries[id]
			if (e.status != "ok")
				continue
			try {
				Hotkey(e.key, ObjBindMethod(this, "Fire", id), "On")
			} catch as Err {
				e.status := "error"
				e.errorText := Hooks_ErrorText(Err)
				Log("Could not bind hotkey '" e.key "' for '" id "': " e.errorText, "WARN", "Hotkeys")
			}
		}
	}

	static Fire(id, *) { ; Every registered hotkey lands here, so a failing callback is logged instead of raising an AutoHotkey error dialog.
		if !this.entries.Has(id)
			return
		Hooks_Call(this.entries[id].fn, "Hotkey", id)
	}

	;## Key names ####################################################################
	static ParseKey(key) { ; Split a hotkey name into modifiers and base key. Returns {canon, main, wildcard}. (Not "base": that name is reserved for an object's base object.)
		; "^!v" and "!^v" are the same key, so canon sorts the modifiers. The $ and ~ prefixes change how a hotkey
		; behaves, not which keystroke triggers it, so they don't take part. A leading * (wildcard) does.
		key := Trim(key)
		wildcard := false
		mods := []
		i := 1
		while (i <= StrLen(key)) {
			ch := SubStr(key, i, 1)
			nextCh := SubStr(key, i + 1, 1)
			if (ch = "*") {
				wildcard := true
			} else if (ch = "~" || ch = "$") {
				; Doesn't change which keystroke fires it.
			} else if InStr("^!+#", ch) {
				mods.Push(ch)
			} else if ((ch = "<" || ch = ">") && nextCh != "" && InStr("^!+#", nextCh)) {
				mods.Push(ch . nextCh) ; Left/right-specific modifier, e.g. <^
				i++
			} else {
				break
			}
			i++
		}
		main := StrLower(SubStr(key, i))
		joined := ""
		for _, m in SortedArray(mods)
			joined .= m
		return {canon: (wildcard ? "*" : "") . joined . "|" . main, main: main, wildcard: wildcard}
	}

	;## Overrides ####################################################################
	static IsEnabled(id) { ; Whether the hotkey is switched on (the user's choice, else the addon's default).
		return this.entries.Has(id) && this.entries[id].enabled
	}

	static SetEnabled(id, state) { ; Switch a hotkey on or off and save it. Takes effect on the next reload. Returns true if it was saved.
		if !this.entries.Has(id) {
			Log("Cannot change hotkey '" id "': it isn't registered.", "WARN", "Hotkeys")
			return false
		}
		this.SetOverride(id, "enabled", state)
		return this.Save()
	}

	static SetOverride(id, field, value) { ; Record one override in memory ("key" or "enabled"). Doesn't save. Drops it again if it equals the addon's default.
		e := this.entries[id]
		ov := this.overrides.Has(id) ? this.overrides[id] : Map()
		if (field = "enabled")
			value := value ? true : false
		dflt := (field = "key") ? e.defaultKey : e.defaultEnabled
		if (value = dflt) {
			if ov.Has(field)
				ov.Delete(field)
		} else
			ov[field] := value
		this.overrides[id] := ov
	}

	static Save() { ; Write the overrides to userprofile\hotkeys.json. Returns true on success.
		; Rebuilt from scratch so booleans go out as true/false (the JSON library writes plain 1/0 as numbers)
		; and entries with nothing left to override don't clutter the file.
		out := Map()
		for id, ov in this.overrides {
			o := Map()
			if ov.Has("key")
				o["key"] := String(ov["key"])
			if ov.Has("enabled")
				o["enabled"] := ov["enabled"] ? JSON.true : JSON.false
			if o.Count
				out[id] := o
		}
		data := Map("version", 1, "overrides", out)
		return PluginBase.SaveFile(this.filePath, JSON.stringify(data, , "  "))
	}

	;## Suspend (single owner) ########################################################
	static SetLocked(state) { ; Called by GuiLocker. Hotkeys stay suspended while locked, and after unlocking if the user had disabled them.
		this.locked := state ? true : false
		this.ApplySuspend()
	}

	static ToggleUserSuspend() { ; Called by the tray's "Disable hotkeys". Returns the new state.
		this.userSuspended := !this.userSuspended
		this.ApplySuspend()
		return this.userSuspended
	}

	static ApplySuspend() {
		Suspend((this.userSuspended || this.locked || this.capturing) ? true : false)
	}

	static SetCapturing(state, *) { ; Hotkeys must not fire while the user is choosing a key in the settings panel's Hotkey control.
		this.capturing := state ? true : false
		this.ApplySuspend()
	}

	static WatchFocus() { ; Timer, runs while the settings window exists. The Hotkey control has no Focus event, so poll for it.
		gone := false
		try {
			hwnd := this.keyCtl.Gui.Hwnd
			held := WinActive("ahk_id " hwnd) && (ControlGetFocus("ahk_id " hwnd) = this.keyCtl.Hwnd)
		} catch {
			SetTimer(this.watchFn, 0) ; The settings window is gone.
			held := false
			gone := true
		}
		held := held ? true : false
		if (held != this.capturing) {
			this.SetCapturing(held)
			if (!held && !gone && this.selectedId != "")
				this.LoadControls(this.selectedId) ; Focus left the box (Alt+Tab, a click elsewhere): show the row's real key again, since the control may have blanked itself.
		}
	}

	;## Settings panel ################################################################
	static BuildSettingsTab(*) { ; The Hotkeys tab. Edits are staged in 'pending' and written by SaveSettings().
		this.SetCapturing(false)
		this.pending := Map()
		this.rowIds := []
		this.selectedId := ""
		this.selPrefix := ""
		this.suppress := false
		x0 := settings_tab_x0
		y0 := settings_tab_y0
		gy2 := y0 + 191 ; Top of the second group box.

		;-- Registered hotkeys ---------------------------------------------------------
		SettingsGui.Add("GroupBox", "x" x0 " y" y0 " w461 h185", T("gb_settings_hotkeys"))
		this.lv := SettingsGui.Add("ListView", "xp+8 yp+18 w445 h132 -Multi", [T("column_hotkeys_action"), T("column_hotkeys_addon"), T("column_hotkeys_key"), T("column_hotkeys_status")])
		this.warnIcon := 0
		icons := IL_Create(2)
		try this.warnIcon := IL_Add(icons, iconsDir "\status\dialog-warning.ico")
		if !this.warnIcon
			Log("Could not load the warning icon for the hotkeys list.", "INFO", "Hotkeys")
		this.lv.SetImageList(icons)
		this.lv.OnEvent("ItemSelect", ObjBindMethod(this, "RowSelected"))
		this.detail := SettingsGui.Add("Text", "xp y+4 w445 h26 cGray", T("hotkeys_detail_select"))

		;-- Selected hotkey ------------------------------------------------------------
		SettingsGui.Add("GroupBox", "x" x0 " y" gy2 " w461 h122", T("gb_settings_hotkeyedit"))
		SettingsGui.Add("Text", "x" (x0 + 10) " y" (gy2 + 26) " w40 h21 +0x200", T("text_hotkeys_key"))
		this.keyCtl := SettingsGui.Add("Hotkey", "x" (x0 + 54) " y" (gy2 + 26) " w170 Limit1") ; Limit1: no bare keys, so nobody binds plain "a".
		this.winChk := SettingsGui.Add("CheckBox", "x" (x0 + 240) " y" (gy2 + 26) " w200 h21", T("chk_hotkeys_win"))
		this.enChk := SettingsGui.Add("CheckBox", "x" (x0 + 10) " y" (gy2 + 58) " w220 h21", T("chk_hotkeys_enabled"))
		this.resetBtn := SettingsGui.Add("Button", "x" (x0 + 240) " y" (gy2 + 56) " w160 h23", T("btn_hotkeys_reset"))
		SettingsGui.Add("Text", "x" (x0 + 10) " y" (gy2 + 86) " w440 cGray", T("text_hotkeys_note"))
		this.keyCtl.OnEvent("Change", ObjBindMethod(this, "KeyEdited"))
		this.winChk.OnEvent("Click", ObjBindMethod(this, "KeyEdited"))
		this.enChk.OnEvent("Click", ObjBindMethod(this, "EnabledEdited"))
		this.resetBtn.OnEvent("Click", ObjBindMethod(this, "ResetSelected"))
		this.SetControlsEnabled(false)
		this.Populate()
		if !this.HasProp("watchFn")
			this.watchFn := ObjBindMethod(this, "WatchFocus")
		SetTimer(this.watchFn, 50)
	}

	static Populate() { ; Fill the list: the program's own hotkeys first, then the addons', each in registration order.
		this.lv.Opt("-Redraw")
		this.lv.Delete()
		this.rowIds := []
		for pass in [1, 2] {
			for id in this.order {
				if ((this.entries[id].owner = "core") != (pass = 1))
					continue
				this.lv.Add(this.RowIconOpt(id), this.Label(id), this.OwnerName(this.entries[id].owner), this.KeyText(id), this.StatusText(id))
				this.rowIds.Push(id)
			}
		}
		this.lv.ModifyCol(1, 145)
		this.lv.ModifyCol(2, 80)
		this.lv.ModifyCol(3, 95)
		this.lv.ModifyCol(4, 95)
		this.lv.Opt("+Redraw")
	}

	static SetControlsEnabled(state) {
		this.keyCtl.Enabled := state
		this.winChk.Enabled := state
		this.enChk.Enabled := state
		this.resetBtn.Enabled := state
	}

	;-- Events ------------------------------------------------------------------------
	static RowSelected(lv, item, selected, *) { ; A row was selected in the list.
		if (!selected || !item || !this.rowIds.Has(item))
			return
		this.selectedId := this.rowIds[item]
		this.LoadControls(this.selectedId)
		this.SetControlsEnabled(true)
		this.UpdateDetail(this.selectedId)
	}

	static LoadControls(id) { ; Show the selected hotkey's current (staged or saved) values in the edit controls.
		key := this.ViewKey(id)
		RegExMatch(key, "^([*~$]*)([<>^!+#]*)(.*)$", &m)
		this.selPrefix := m[1] ; Prefixes the Hotkey control can't show are kept as they were.
		this.suppress := true
		try
			this.keyCtl.Value := StrReplace(m[2], "#") . m[3] ; The control can't hold the Win key; that's the checkbox.
		catch
			try this.keyCtl.Value := ""
		this.winChk.Value := InStr(m[2], "#") ? 1 : 0
		this.enChk.Value := this.ViewEnabled(id) ? 1 : 0
		this.suppress := false
	}

	static KeyEdited(*) { ; The key box or the Windows checkbox changed.
		if (this.suppress || this.selectedId = "")
			return
		val := this.keyCtl.Value
		if (val != "" && RegExMatch(val, "^[\^!+]+$")) ; Only modifiers so far (the control reports them while keys are held down).
			return
		if (val = "") { ; The control went blank (it clears itself when it loses focus, and can't show every key): keep the row's own key.
			RegExMatch(this.ViewKey(this.selectedId), "^([*~$]*)([<>^!+#]*)(.*)$", &m)
			val := StrReplace(m[2], "#") . m[3]
		}
		if (val = "")
			return
		this.Stage(this.selectedId, "key", this.selPrefix . (this.winChk.Value ? "#" : "") . val)
	}

	static EnabledEdited(*) { ; The Enabled checkbox changed.
		if (this.suppress || this.selectedId = "")
			return
		this.Stage(this.selectedId, "enabled", this.enChk.Value = 1)
	}

	static ResetSelected(*) { ; Back to the addon's default key and state.
		id := this.selectedId
		if (id = "")
			return
		this.Stage(id, "key", this.entries[id].defaultKey)
		this.Stage(id, "enabled", this.entries[id].defaultEnabled)
		this.LoadControls(id)
	}

	static Stage(id, field, value) { ; Remember an edit until Save. An edit that matches how things are now is forgotten again.
		e := this.entries[id]
		if !this.pending.Has(id)
			this.pending[id] := Map()
		p := this.pending[id]
		p[field] := value
		if (p.Has("key") && p["key"] = e.key)
			p.Delete("key")
		if (p.Has("enabled") && p["enabled"] = e.enabled)
			p.Delete("enabled")
		if !p.Count
			this.pending.Delete(id)
		this.RefreshRow(id)
		this.UpdateDetail(id)
	}

	static SaveSettings(*) { ; Settings Save button: write the staged edits. Returns true on success. The reload that follows applies them.
		if !this.pending.Count
			return true
		for id, p in this.pending {
			if p.Has("key")
				this.SetOverride(id, "key", p["key"])
			if p.Has("enabled")
				this.SetOverride(id, "enabled", p["enabled"])
		}
		return this.Save()
	}

	;-- Display -----------------------------------------------------------------------
	static ViewKey(id) { ; The key as the panel should show it: staged edit first, else what's active now.
		return (this.pending.Has(id) && this.pending[id].Has("key")) ? this.pending[id]["key"] : this.entries[id].key
	}

	static ViewEnabled(id) {
		return (this.pending.Has(id) && this.pending[id].Has("enabled")) ? this.pending[id]["enabled"] : this.entries[id].enabled
	}

	static Label(id) { ; Translated name of the action (<pluginKey>.hotkey_<action>), else the id.
		e := this.entries[id]
		key := e.owner ".hotkey_" e.action
		return PluginBase.Strings.Has(key) ? PluginBase.Strings[key] : id
	}

	static OwnerName(owner) {
		return (owner = "core") ? T("app_name") : _ResolveAddonDisplayName(owner)
	}

	static KeyText(id) {
		key := this.PrettyKey(this.ViewKey(id))
		return (key != "") ? key : T("hotkeys_key_none")
	}

	static StatusText(id) {
		static keys := Map("ok", "hotkeys_status_ok", "disabled", "hotkeys_status_disabled", "unassigned", "hotkeys_status_unassigned"
			, "conflict", "hotkeys_status_conflict", "error", "hotkeys_status_error")
		if this.pending.Has(id)
			return T("hotkeys_status_changed")
		return T(keys.Get(this.entries[id].status, "hotkeys_status_ok"))
	}

	static RowIconOpt(id) { ; Warning icon for rows that can't be active. The other rows get an icon number past the end of the list, which shows nothing.
		problem := !this.pending.Has(id) && (this.entries[id].status = "conflict" || this.entries[id].status = "error")
		return (problem && this.warnIcon) ? "Icon" this.warnIcon : "Icon2"
	}

	static RefreshRow(id) {
		row := 0
		for i, rowId in this.rowIds {
			if (rowId = id) {
				row := i
				break
			}
		}
		if !row
			return
		this.lv.Modify(row, this.RowIconOpt(id), this.Label(id), this.OwnerName(this.entries[id].owner), this.KeyText(id), this.StatusText(id))
	}

	static UpdateDetail(id) { ; The grey line under the list: why a hotkey isn't active, or its default.
		e := this.entries[id]
		if this.pending.Has(id)
			text := T("hotkeys_detail_changed")
		else if (e.status = "conflict")
			text := T("hotkeys_detail_conflict") " " this.Label(e.conflictWith)
		else if (e.status = "error")
			text := T("hotkeys_detail_error") " " e.errorText
		else {
			dflt := this.PrettyKey(e.defaultKey)
			text := T("hotkeys_detail_default") " " (dflt != "" ? dflt : T("hotkeys_key_none"))
		}
		other := this.SameKeyLabel(id)
		if (other != "" && (this.pending.Has(id) || e.status != "conflict"))
			text .= "`n" T("hotkeys_detail_samekey") " " other
		this.detail.Value := text
	}

	static SameKeyLabel(id) { ; Name of another enabled hotkey that shows the same key right now, or "".
		if (!this.ViewEnabled(id) || this.ViewKey(id) = "")
			return ""
		canon := this.ParseKey(this.ViewKey(id)).canon
		for otherId in this.order {
			if (otherId = id || !this.ViewEnabled(otherId) || this.ViewKey(otherId) = "")
				continue
			if (this.ParseKey(this.ViewKey(otherId)).canon = canon)
				return this.Label(otherId)
		}
		return ""
	}

	static PrettyKey(key) { ; "^!v" -> "Ctrl+Alt+V". Anything it doesn't understand is shown as written.
		key := Trim(key)
		if (key = "" || !RegExMatch(key, "^[*~$]*([<>^!+#]*)(.+)$", &m))
			return key
		parts := ""
		Loop Parse m[1] {
			switch A_LoopField {
				case "^": parts .= "Ctrl+"
				case "!": parts .= "Alt+"
				case "+": parts .= "Shift+"
				case "#": parts .= "Win+"
			}
		}
		return parts . (StrLen(m[2]) = 1 ? StrUpper(m[2]) : m[2])
	}
}

;## Core hotkeys ################################################################
Plugin_AddHotkey("core.show", "", ShowMainWindow) ; Show the main window, or bring it to the front. Unassigned until the user picks a key.
Plugin_AddHotkey("core.hide", "", HideMainWindow) ; Hide the main window. Unassigned until the user picks a key.
Plugin_AddHotkey("core.quickmenu", "", ShowQuickMenu) ; Pop up the addons menu at the mouse pointer. Unassigned until the user picks a key.
Plugin_AddHotkey("core.reload", "^F12", Reload) ; Developer shortcut: reload the script.
