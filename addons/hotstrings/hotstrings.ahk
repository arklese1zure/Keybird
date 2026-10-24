
;				=========================================================================
;				|||||						Hotstring manager						|||||
;				=========================================================================

class PluginHotstrings extends PluginBase {
	
	static PluginKey    := "hotstrings"           ; internal plugin name, used to match it with several elements.
	
	static settingsFile := A_WorkingDir "\userprofile\hotstrings.ini"	
		
	static __New() { ;## Startup ########################################################
		;== Hooks =======================================================================
		Plugin_Main_AddTab(ObjBindMethod(this, "BuildTabContents"), "Hotstrings", "\addons\hotstrings\res\tabicon.ico",,, "hotstrings")
		Plugin_Settings_AddTab(ObjBindMethod(this, "BuildSettingsTab"), "Hotstrings", "hotstrings")
		Plugin_Settings_SaveSettings(ObjBindMethod(this, "SaveSettings"), "Hotstrings")
		
		;== Variables ===================================================================
		this.hotstringFolder  := A_WorkingDir "\userprofile\hotstrings"
		this.activeHotstrings := [] ; IDs (":options:trigger") currently registered by this addon. See LoadHotstringsFromFile.
		this.editingTrigger   := "" ; Original trigger of the entry being edited, if any. See OpenHotstringGui/SaveHotstring.
		; Default to empty string if no dictionary has been selected (e.g. first run).
		this.currentHSFile    := this.GetSetting("Dictionary", "current_dict", "")
		this.hotstringsFile   := A_ScriptDir "\userprofile\hotstrings\" this.currentHSFile
		this.LoadHotstringsFromFile(this.hotstringsFile) ; Register hotstrings dynamically from JSON.
	}

	static BuildTabContents() { ;## Gui tab contents ####################################
		;== Gui menus ===================================================================
		;-- Hotstrings ListView context menu --------------------------------------------
		this.HotstringsMenu := Menu()																	
			this.HotstringsMenu.Add(this.T("menu_hs_newhotstring"), ObjBindMethod(this, "AddHotstring"))
			this.HotstringsMenu.Add(this.T("menu_hs_edithotstring"), ObjBindMethod(this, "EditHotstring"))
			this.HotstringsMenu.Add(this.T("menu_hs_deletehotstring"), ObjBindMethod(this, "RemoveHotstring"))
			this.HotstringsMenu.Add()
			this.HotstringsMenu.Add(this.T("options"), ObjBindMethod(this, "OpenSettingsTab"))

		;== Gui components ==============================================================
		;-- Hotstrings ListView ---------------------------------------------------------
		this.LV_hotstrings := mainGui.Add("ListView", "h283 w248 x+0 y+0 Sort", [this.T("lv_hotstrings_col1"),this.T("lv_hotstrings_col2")])
			this.LV_hotstrings.OnEvent("DoubleClick", ObjBindMethod(this, "EditHotstring")) ; Double-click a row to edit it.
		this.FillHotstringsLV()
		this.LV_hotstrings.ModifyCol(1, 90)
		this.LV_hotstrings.ModifyCol(2, 400)
		
		;-- Buttons ---------------------------------------------------------------------
		BtnContextMenu := mainGui.Add("Button", "w25 h25 xp y310")
			GuiButtonIcon(BtnContextMenu, iconsDir "\categories\applications-system.ico", 1, "s16")
			BtnContextMenu.OnEvent("Click", ObjBindMethod(this, "HotstringsContextMenuButton"))
		BtnAddHotstring := mainGui.Add("Button", "w25 h25 x+1")
			GuiButtonIcon(BtnAddHotstring, iconsDir "\actions\list-add.ico", 1, "s16")
			BtnAddHotstring.OnEvent("Click", ObjBindMethod(this, "AddHotstring"))
		BtnDeleteHotstring := mainGui.Add("Button", "w25 h25 x+1")
			GuiButtonIcon(BtnDeleteHotstring, iconsDir "\actions\list-remove.ico", 1, "s16")
			BtnDeleteHotstring.OnEvent("Click", ObjBindMethod(this, "RemoveHotstring"))
	}

	static BuildSettingsTab(*) { ;## Settings gui tab ###################################
		;== Gui components ==============================================================
		;-- Hotstrings file selection dropdown ------------------------------------------
		SettingsGui.Add("GroupBox",								"x" settings_tab_x0 " y" settings_tab_y0 " w461 h45",		this.T("settings_gb_main"))
		SettingsGui.Add("Text",									"xp+8 yp+20",			this.T("settings_text_selectdict"))
		this.HSFileDropDown := SettingsGui.Add("DropDownList",	"x+5 yp-3 w246 r20")
			this.HSFileDropDown.OnEvent("Change",  ObjBindMethod(this, "LoadHSFilePreview"))
		
		;-- Hotstrings file description -------------------------------------------------
		this.HSFileDescBox := SettingsGui.Add("GroupBox",		"x" settings_tab_x0 " y+10 w225 h95",		this.T("settings_gb_desc"))
		this.HSFileNameBox := SettingsGui.Add("Edit",			"xp+1 yp+15 w220 r5", 	this.T("settings_edit_fileselecthint"))
		
		;-- Hotstrings preview ListView -------------------------------------------------
		SettingsGui.Add("GroupBox",								"x+10 yp-15 w232 h270",	this.T("settings_gb_preview"))
		this.HSPreviewLV := SettingsGui.Add("ListView",			"xp+2 yp+18 w228 h250",	[this.T("settings_lv_prev_col1"),this.T("settings_lv_prev_col2")])
		
		;-- Hotstrings file options -----------------------------------------------------
		SettingsGui.Add("GroupBox",								"x" settings_tab_x0 " y155 w225 h77",		this.T("options"))
		;BtnDeleteHSFile := SettingsGui.Add("Button",			"xp+7 yp+20 w80",	this.T("settings_btn_delete"))
		BtnDeleteHSFile := SettingsGui.Add("Button",			"xp+7 yp+20 w90",	this.T("settings_btn_delete"))
			BtnDeleteHSFile.OnEvent("Click", DummyFunction)
		;BtnNewHSFile := SettingsGui.Add("Button",				"x+7 yp w80",			this.T("settings_btn_newdict"))
		BtnNewHSFile := SettingsGui.Add("Button",				"y+5 w90",			this.T("settings_btn_newdict"))
			BtnNewHSFile.OnEvent("Click", ObjBindMethod(this, "NewHotstringFile"))
		
		;== Gui functions ===============================================================
		this.FillHSDropdown() ; Fill dropdownlist with available hotstring files.
	}

	;## Gui functions ###################################################################
	;== Main gui tab ====================================================================
	static FillHotstringsLV(*) { ; Fill hotstrings listview
		dict := this.LoadDictionary(this.hotstringsFile)
		this.LV_hotstrings.Opt("-Redraw")
		for entry in dict.hotstrings {
			try this.LV_hotstrings.Add(, entry.trigger, entry.text)
			catch as Err
				Log("Skipped malformed hotstring entry: " Err.Message, "WARN", "PluginHotstrings")
		}
		this.LV_hotstrings.Opt("+Redraw")
	}

	static RefreshHotstringsLV(*) { ; Refresh listview in main gui.
		this.LV_hotstrings.Delete()
		this.FillHotstringsLV()
	}

	static HotstringsContextMenuButton(*) { ; This is just for triggering the context menu.
		this.HotstringsMenu.Show
	}

	;== Settings gui tab ================================================================
	static FillHSDropdown(*) { ; Fill dropdownlist with available hotstring files.
		if not this.hotstringFolder ; Check if folder exists.
			return
		if SubStr(this.hotstringFolder, -1, 1) = "\" ; Check if the last character of the folder name is a backslash.
			this.hotstringFolder := SubStr(this.hotstringFolder, 1, -1) ; Remove it to prevent double-backslashes later on.
		; Get dictionary file names from the hotstrings folder and append them to the ListView.
		Loop Files this.hotstringFolder "\*.json" {
			this.HSFileDropDown.Add([A_LoopFileName])
		}
		if (this.currentHSFile) { ; Get the currently loaded hotstrings file.
			this.HSFileDropDown.Choose(this.currentHSFile) ; Select the hotstrings file's name on the DropDownList.
			this.PreviewHSFile(this.currentHSFile) ; Load its preview on the ListView.
		}
	}

	static PreviewHSFile(file) { ; Load the hotstrings file into a listview for previewing.
		if !file {
			this.HSPreviewLV.Delete()
			this.HSFileNameBox.Value := this.T("settings_prompt_selectdict")
			return
		}
		filePath := A_WorkingDir "\userprofile\hotstrings\" file
		if !FileExist(filePath) {
			this.HSPreviewLV.Delete()
			this.HSFileNameBox.Value := this.T("settings_err_filenotfound")
			return
		}
		dict := this.LoadDictionary(filePath)
		this.HSFileNameBox.Value := dict.description
		this.HSPreviewLV.Delete()
		this.HSPreviewLV.Opt("-Redraw")
		for entry in dict.hotstrings {
			try this.HSPreviewLV.Add(, entry.trigger, entry.text)
			catch as Err
				Log("Skipped malformed hotstring entry: " Err.Message, "WARN", "PluginHotstrings")
		}
		this.HSPreviewLV.Opt("+Redraw")
	}

	static LoadHSFilePreview(*) { ; Load the hotstrings file into a listview for previewing.
		selectedHSFile := this.HSFileDropDown.Text ; Retrieve the ListBox's current selection.
		this.PreviewHSFile(selectedHSFile)
	}

	;== Hotstrings file operations ======================================================
	static AddHotstring(*) { ; Open the hotstring gui in "new" mode.
		this.OpenHotstringGui()
	}

	static EditHotstring(*) { ; Open the hotstring gui in "edit" mode for the selected row.
		focusedRowNumber := this.LV_hotstrings.GetNext(0, "F")
		if !focusedRowNumber
			return
		selectedTrigger := this.LV_hotstrings.GetText(focusedRowNumber, 1)
		dict := this.LoadDictionary(this.hotstringsFile)
		for entry in dict.hotstrings {
			try {
				if entry.trigger == selectedTrigger {
					this.OpenHotstringGui(entry)
					return
				}
			}
		}
		; The entry is somehow gone (e.g. the dictionary changed elsewhere). Log unexpected event and reload the hotstrings instead.
		Log("Could not find hotstring '" selectedTrigger "' to edit; the dictionary may have changed.", "WARN", "PluginHotstrings")
		this.ReloadHotstrings()
	}

	static OpenHotstringGui(existingEntry := "") { ; Shared gui for adding a new hotstring or editing an existing one.
		isEditing := IsObject(existingEntry)
		this.editingTrigger := isEditing ? existingEntry.trigger : ""
		; Missing requiresTriggerKey/caseSensitive default to true.
		requiresTriggerKey := !isEditing || !(existingEntry.HasProp("requiresTriggerKey") && !existingEntry.requiresTriggerKey)
		caseSensitive := isEditing && existingEntry.HasProp("caseSensitive") && existingEntry.caseSensitive

		mainGUI.Opt("+Disabled") ; Disable main GUI.
		this.newHotstringGui := Gui()
		this.newHotstringGui.Add("GroupBox",								"x3 y3 w344 h140", this.T("hsgui_gb_title"))
		this.newHotstringGui.Add("Text",									"x12 y20 r1", this.T("hsgui_text_fulltexthint"))
		this.newHotstringText := this.newHotstringGui.Add("Edit",			"x8 y34 r4 w334", isEditing ? existingEntry.text : "")
		this.newHotstringGui.Add("Text",									"x12 y100 r1", this.T("hsgui_text_hotstringhint"))
		this.newHotstringWord := this.newHotstringGui.Add("Edit",			"x8 y114 r1 w334", isEditing ? existingEntry.trigger : "")
		this.newHotstringGui.Add("GroupBox",								"x3 y144 w344 h40", this.T("options"))
		this.HSCheckBox1 := this.newHotstringGui.Add("CheckBox",			"x12 y156 w190 h23" (requiresTriggerKey ? " Checked" : ""), this.T("hsgui_text_requiretrigger"))
		this.HSCheckBox2 := this.newHotstringGui.Add("CheckBox",			"x+8 yp w120 h23" (caseSensitive ? " Checked" : ""), this.T("hsgui_text_respectcase"))
		btnSaveHotstring := this.newHotstringGui.Add("Button",				"x180 y190 w80 h23 Default", this.T("hsgui_btn_default"))
			btnSaveHotstring.OnEvent("Click", ObjBindMethod(this, 			"SaveHotstring"))
		btnCloseNewHotstringGui := this.newHotstringGui.Add("Button",		"x+5 w80 h23", this.T("cancel"))
			btnCloseNewHotstringGui.OnEvent("Click", ObjBindMethod(this,	"CloseNewHotstringGui"))
		this.newHotstringGui.Title := programinfo.name " — " (isEditing ? this.T("menu_hs_edithotstring") : this.T("menu_hs_newhotstring"))
		this.newHotstringGui.OnEvent("Close", ObjBindMethod(this, 			"CloseNewHotstringGui"))
		this.newHotstringGui.OnEvent("Escape", ObjBindMethod(this,			"CloseNewHotstringGui"))
		this.newHotstringGui.Show("h220 w350")
	}

	static SaveHotstring(*) { ; Check the hotstring, then add it or, if editing, replace the original entry.
		trigger := Trim(this.newHotstringWord.Value) ; Get the value from the gui's box.
		if (trigger = "" || RegExMatch(trigger, "\s")) {
			MsgBox(this.T("hsgui_msgbox_errblank"), "Error", 16)
			return
		}
		if this.HotstringIsDuplicate(trigger, this.editingTrigger) { ; Check if string is duplicate.
			MsgBox(this.T("hsgui_msgbox_errduplicate"), "Error", 16)
			return
		}
		; Assemble new hotstring entry as a JSON object for saving.
		newEntry := {
			trigger: trigger,
			text: this.newHotstringText.Value,
			caseSensitive: this.HSCheckBox2.Value ? JSON.true : JSON.false,
			requiresTriggerKey: this.HSCheckBox1.Value ? JSON.true : JSON.false
		}
		dict := this.LoadDictionary(this.hotstringsFile)
		replaced := false
		if this.editingTrigger != "" { ; Loop until the entry to replace is found.
			for index, entry in dict.hotstrings {
				try {
					if entry.trigger == this.editingTrigger {
						dict.hotstrings[index] := newEntry
						replaced := true
						break
					}
				}
			}
			if !replaced ; If the entry to replace was somehow not found, act as if it's just a new hotstring entry, but log it.
				Log("Hotstring '" this.editingTrigger "' no longer exists; saving the edit as a new entry instead.", "WARN", "PluginHotstrings")
		}
		if !replaced
			dict.hotstrings.Push(newEntry)
		if this.SaveDictionary(this.hotstringsFile, dict) {
			this.CloseNewHotstringGui()
			this.ReloadHotstrings()
		}
	}

	static CloseNewHotstringGui(*) { ; Cancel adding/editing a hotstring.
		this.newHotstringGui.Destroy
		this.editingTrigger := ""
		mainGUI.Opt("-Disabled") ; Reenable main GUI (owner).
	}

	static RemoveHotstring(*) { ; Remove hotstring from hotstrings file.
		focusedRowNumber := this.LV_hotstrings.GetNext(0, "F")
		if !focusedRowNumber
			return
		selectedHotstring := this.LV_hotstrings.GetText(focusedRowNumber, 1)
		result := MsgBox(this.T("gui_msgbox_confirmdelete") "`n" selectedHotstring,, "YesNo")
		if (result != "Yes")
			return
		dict := this.LoadDictionary(this.hotstringsFile)
		kept := []
		for entry in dict.hotstrings {
			matches := false
			try matches := (entry.trigger == selectedHotstring)
			if !matches
				kept.Push(entry) ; Keep everything except the entry being deleted.
		}
		dict.hotstrings := kept
		if this.SaveDictionary(this.hotstringsFile, dict)
			this.ReloadHotstrings()
	}
		
	static NewHotstringFile(*) { ; Create a new, preformatted hotstrings file for adding new ones.
		; Collect all input before touching the filesystem.
		newHotstringFileName := InputBox(this.T("settings_inputbox_newdictname"), programinfo.name " — " this.T("hsgui_title"))
		if newHotstringFileName.Result = "Cancel"
			return
		if newHotstringFileName.Value = "" {
			MsgBox(this.T("settings_msgbox_errblankname"), "Error", 16)
			return
		}
		newHotstringFile := A_ScriptDir "\userprofile\hotstrings\" newHotstringFileName.Value ".json"
		if FileExist(newHotstringFile) {
			MsgBox(this.T("settings_msgbox_errdupename"), "Error", 16)
			return
		}
		newHotstringFileDesc := InputBox(this.T("settings_inputbox_description"), programinfo.name " — " this.T("hsgui_title"))
		if newHotstringFileDesc.Result = "Cancel"
			return
		; Create the file with collected input.
		newDict := { description: newHotstringFileDesc.Value, hotstrings: [] }
		if this.SaveDictionary(newHotstringFile, newDict)
			this.HSFileDropDown.Add([newHotstringFileName.Value ".json"])
	}

	static DeleteHotstringFile(*) { ; Delete the currently selected hotstring file.
		selectedHSFile := this.hotstringFolder . "\" . this.HSFileDropDown.Text
		result := MsgBox(this.T("settings_msgbox_confirmdelete") "`n" this.HSFileDropDown.Text, programinfo.name, "OKCancel")
		if Result = "OK" {
			FileDelete selectedHSFile
			this.HSFileDropDown.Delete(this.HSFileDropDown.Value)
			return
		}
		else
			return
	}

	;## Other functions #############################################################
	static SanitizeString(text) { ; Use RegExReplace to remove all blank space.
		text := RegExReplace(text, "\t") ; Remove tabs
		text := RegExReplace(text, "\r\n|\r|\n", "`n") ; Normalize newlines
		text := RegExReplace(text, "\s+$") ; Remove trailing spaces
		return text
	}

	;## Dictionary file I/O ##########################################################
	static LoadDictionary(file) { ; Parse a dictionary file into {description, hotstrings} object.
		if !FileExist(file) || DirExist(file)
			return { description: "", hotstrings: [] }
		try {
			dict := JSON.parse(FileRead(file, "UTF-8"), , false) ; as_map:=false -> plain Objects, dot-notation.
			if !IsObject(dict) || !dict.HasProp("hotstrings") || Type(dict.hotstrings) != "Array" ; Validate before loading.
				throw Error(this.T("settings_err_invalidfile"))
			if !dict.HasProp("description") ; If file is valid but has no description, leave it blank.
				dict.description := ""
			return dict
		} catch as Err {
			Log("Could not read hotstring dictionary '" file "': " Err.Message, "ERROR", "PluginHotstrings")
			return { description: "", hotstrings: [] } ; Return an empty dictionary in case of error.
		}
	}

	static SaveDictionary(file, dict) { ; Format objects back to JSON.
		return this.SaveFile(file, JSON.stringify(dict, , "  "))
	}

	static HotstringIsDuplicate(value, excludeTrigger := "") { ; Check for duplicates in the hotstring file.
	; excludeTrigger skips the entry currently being edited, so it won't trigger duplicate detection.
		dict := this.LoadDictionary(this.hotstringsFile)
		for entry in dict.hotstrings {
			try {
				if entry.trigger == value && entry.trigger != excludeTrigger
					return true
			}
		}
		return false
	}

	static LoadHotstringsFromFile(file) { ; Register every entry in a dictionary file as a dynamic hotstring.
	; Called from __New() at startup, and via ReloadHotstrings() after adding/removing an entry or switching dictionaries.
		for _, hsId in this.activeHotstrings {
			try Hotstring(hsId, , "Off") ; Turn off whatever this addon previously registered.
		}
		this.activeHotstrings := []

		if this.currentHSFile = ""
			return ; No dictionary selected yet.

		dict := this.LoadDictionary(file)
		skipped := 0
		for entry in dict.hotstrings {
			try {
				; "R" (raw) is always included so the saved text is sent literally
				; requiresTriggerKey/caseSensitive revert to default to if missing from an entry (e.g. a hand-edited file).
				options := "R"
					. ((entry.HasProp("requiresTriggerKey") && !entry.requiresTriggerKey) ? "?*" : "")
					. ((entry.HasProp("caseSensitive") && entry.caseSensitive) ? "C" : "")
				hsId := ":" options ":" entry.trigger
				Hotstring(hsId, entry.text, "On") ; Hotstring() throws a catchable error on invalid input, so only the malformed line is skipped
				this.activeHotstrings.Push(hsId)
			} catch as Err {
				Log("Skipped invalid hotstring entry: " Err.Message, "WARN", "PluginHotstrings")
				skipped++
			}
		}
		if skipped
			Log(skipped " hotstring(s) in '" file "' could not be loaded and were skipped.", "WARN", "PluginHotstrings")
	}

	static ReloadHotstrings(*) { ; Re-register hotstrings from the current dictionary and refresh the tab's ListView.
		this.LoadHotstringsFromFile(this.hotstringsFile)
		this.RefreshHotstringsLV()
	}
	
	;## Hook functions ##############################################################
	static SaveSettings(*) { ; Things to do when the save button is clicked.
	; Just persist which dictionary is selected — __New() reads this setting directly on the
	; next launch and calls LoadHotstringsFromFile() itself, so there's no need to generate a
	; separate #Include shim file for it (the old userprofile\loadedhotstrings.ahk) anymore.
		selectedFile := this.HSFileDropDown.Text
		if !this.SaveSetting("Dictionary", "current_dict", selectedFile)
			return false
		this.currentHSFile  := selectedFile
		this.hotstringsFile := A_ScriptDir "\userprofile\hotstrings\" selectedFile
		this.ReloadHotstrings()
		return true
	}

	static OpenSettingsTab(*){	; Launch settings gui with a specific tab selected.
		LaunchSettings("Hotstrings")
	}
}
