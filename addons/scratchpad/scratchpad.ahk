
;				=========================================================================
;				|||||						Scratchpad								|||||
;				=========================================================================

class PluginScratchPad extends PluginBase {
	
	static PluginKey    := "scratchpad"
	
	static settingsFile := A_WorkingDir "\userprofile\scratchpad.ini"

	static __New() { ;## Startup ########################################################
		;== Hooks =======================================================================
		;Plugin_Main_AddTab(ObjBindMethod(this, "BuildTabContents"), "Scratchpad", "\addons\scratchpad\res\tabicon.ico")
		Plugin_Main_AddTab(
			ObjBindMethod(this, "BuildTabContents"),		; Tab contents
			"Scratchpad",									; Tab name
			"\addons\scratchpad\res\tabicon.ico",			; Tab icon
			,												; Function when tab is selected
			,												; Function when tab is right-clicked
			"scratchpad"									; PluginKey
		)
		Plugin_Main_OnExit(ObjBindMethod(this, "SaveCurrentNote"), "Scratchpad")
		;== Variables ===================================================================
		this.currentNoteHasChanged := FALSE
		;== Files =======================================================================
		this.scratchpadFolder := userProfile "\scratchpad"
		if !this.EnsureFolder(this.scratchpadFolder)
			return ; Can't continue safely without the folder; error already logged.
		if !FileExist(this.settingsFile)
			this.SaveSetting("Notes", "current_note", "New note.txt")
		this.currentNote := this.scratchpadFolder "\" this.GetSetting("Notes", "current_note", "New note.txt")
	}
	
	static BuildTabContents(*) { ;## Gui tab contents ###################################
		;== Gui menus ===================================================================
		;-- Text tools submenu: each one works on the selection, or the whole note if nothing is selected.
		this.TextToolsMenu := Menu()
			this.TextToolsMenu.Add(this.T("menu_removeblanklines", "Remove blank lines"), ObjBindMethod(this, "TransformText", "blanklines"))
			this.TextToolsMenu.Add(this.T("menu_trimspaces", "Trim spaces"), ObjBindMethod(this, "TransformText", "trim"))
			this.TextToolsMenu.Add()
			this.TextToolsMenu.Add(this.T("menu_uppercase", "UPPERCASE"), ObjBindMethod(this, "TransformText", "upper"))
			this.TextToolsMenu.Add(this.T("menu_lowercase", "lowercase"), ObjBindMethod(this, "TransformText", "lower"))
			this.TextToolsMenu.Add(this.T("menu_sentencecase", "Sentence case"), ObjBindMethod(this, "TransformText", "sentence"))
		;-- Options menu: less-used note actions, kept off the main buttons.
		this.NoteOptionsMenu := Menu()
			this.NoteOptionsMenu.Add(this.T("menu_renamenote", "Rename note"), ObjBindMethod(this, "RenameNote"))
			this.NoteOptionsMenu.Add(this.T("menu_deletenote", "Delete note"), ObjBindMethod(this, "DeleteNote"))
			this.NoteOptionsMenu.Add()
			this.NoteOptionsMenu.Add(this.T("menu_texttools", "Text"), this.TextToolsMenu)
		;== Gui components ==============================================================
		this.ScratchpadMainEdit := mainGui.Add("Edit", "h283 w248 x+0 y+0", "Write your notes here.")
			this.ScratchpadMainEdit.OnEvent("Change", ObjBindMethod(this, "NoteChanged"))
		this.NotesDDL := mainGui.Add("DropDownList", "w160 h35 xp+2 y312 r6", [])
			this.NotesDDL.OnEvent("Change", ObjBindMethod(this, "LoadNote"))
		ScratchPadButton1 := mainGui.Add("Button", "w25 h25 x+2 yp-2") ; To-Do: Rename these buttons to something less generic.
			GuiButtonIcon(ScratchPadButton1, iconsDir "\actions\document-save.ico", 1, "s16")
			ScratchPadButton1.OnEvent("Click", ObjBindMethod(this, "SaveCurrentNote"))
		ScratchPadButton2 := mainGui.Add("Button", "w25 h25 x+1")
			GuiButtonIcon(ScratchPadButton2, iconsDir "\actions\list-add.ico", 1, "s16")
			ScratchPadButton2.OnEvent("Click", ObjBindMethod(this, "NewNote"))
		ScratchPadButton3 := mainGui.Add("Button", "w25 h25 x+1")
			GuiButtonIcon(ScratchPadButton3, iconsDir "\categories\applications-system.ico", 1, "s16")
			ScratchPadButton3.OnEvent("Click", (*) => this.NoteOptionsMenu.Show())
		this.LoadNotesList()
		this.LoadLastNote()
	}

	;## Gui functions ###################################################################
	static LoadNotesList(*) { ; Fills the dropdown with all the stored text files.
		if !DirExist(this.scratchpadFolder)
			return
		; Ensure no trailing backslash before appending "\*".
		folder := SubStr(this.scratchpadFolder, -1, 1) = "\" ? SubStr(this.scratchpadFolder, 1, -1) : this.scratchpadFolder
		Loop Files folder "\*.txt" {
			this.NotesDDL.Add([A_LoopFileName])
		}
	}

	static LoadLastNote(*) { ; Read last opened note from the settings ini and load the file.
		if !FileExist(this.currentNote) { ; If there's no file with the stored filename, create a new file instead.
			this.StartDefaultNote()
			return
		} else {
			this.ScratchpadMainEdit.Value := FileRead(this.currentNote)
			this.currentNoteName := this.GetSetting("Notes", "current_note", "New note.txt")
			this.NotesDDL.Choose(this.currentNoteName)
			this.currentNoteHasChanged := FALSE
			this.LastLoadedNote := this.NotesDDL.Text
		}
	}

	static StartDefaultNote() { ; Adds and selects a blank "New note.txt", so there's always a note to write into.
		; Like NewNote(), the file isn't created until it's saved.
		this.SaveSetting("Notes", "current_note", "New note.txt")
		this.NotesDDL.Add(["New note.txt"])
		this.NotesDDL.Choose("New note.txt")
		this.ScratchpadMainEdit.Value := "Write your notes here..."
		this.currentNoteHasChanged := TRUE
		this.LastLoadedNote := this.NotesDDL.Text
	}

	static ListIndexOf(noteName) { ; Exact-match lookup. Choose(String) matches by prefix, so it can pick the wrong note.
		for i, item in ControlGetItems(this.NotesDDL)
			if (item = noteName)
				return i
		return 0
	}

	static RemoveFromList(noteName) { ; Removes an entry from the dropdown and keeps the current selection.
		if !(index := this.ListIndexOf(noteName))
			return
		selected := this.NotesDDL.Text
		this.NotesDDL.Delete(index)
		if (selectedIndex := this.ListIndexOf(selected))
			this.NotesDDL.Choose(selectedIndex)
	}

	static LoadNoteError(filePath) { ; Error handler for file-not-found situations.
		MsgBox("Could not load `"" filePath "`".`nThe file might have been deleted, renamed or moved.", programinfo.name, "48")
	}

	;== File operations =================================================================
	static NewNote(*) {
		; Blank the edit control and add a new filename. File won't be created unless the save button is clicked.
		; This is intentional, for maximum scratch-padiness.
		this.newNoteName := InputBox("Name your new note:", programinfo.name " - " "Scratchpad") ; Ask for a filename.
		if this.newNoteName.Result = "Cancel" ; Return if user cancels or no input is received.
			return
		else if this.newNoteName.Value = "" { ; Check if filename is not blank.
			MsgBox("Please name your file and try again.","Error", 16)
			return
		}
		newNoteFile := this.newNoteName.Value . ".txt" ; Append extension to filename.
		if FileExist(this.scratchpadFolder . "\" . newNoteFile) { ; Check if there's not a file named like that already.
			MsgBox("A file named `"" newNoteFile "`" Already exists. Try again.","Error", 16)
			return
		}
		this.ScratchpadMainEdit.Value := "Write your notes here..." ; Prepare the gui for the new note.
		this.NotesDDL.Add([newNoteFile])
		this.NotesDDL.Choose(newNoteFile)
		this.currentNoteHasChanged := TRUE
		this.LastLoadedNote := this.NotesDDL.Text
	}
	
	static RenameNote(*) { ; Renames the currently loaded note, along with its file and backup if they exist.
		oldName := this.NotesDDL.Text
		if (oldName = "")
			return
		input := InputBox("Rename `"" oldName "`" to:", programinfo.name " - " "Scratchpad",, RegExReplace(oldName, "i)\.txt$"))
		if (input.Result = "Cancel")
			return
		newBase := Trim(input.Value)
		if (newBase = "") {
			MsgBox("Please name your file and try again.", "Error", 16)
			return
		}
		if RegExMatch(newBase, '[\\/:*?"<>|]') {
			MsgBox('Note names can`'t contain any of these characters: \ / : * ? " < > |', "Error", 16)
			return
		}
		newName := newBase ".txt"
		if (newName == oldName) ; Case-sensitive: a case-only change is still a rename.
			return
		oldPath := this.scratchpadFolder "\" oldName
		newPath := this.scratchpadFolder "\" newName
		; "!=" ignores case, so a case-only rename doesn't count as colliding with itself.
		; The list check also catches unsaved notes, which have no file yet.
		if (newName != oldName && (FileExist(newPath) || this.ListIndexOf(newName))) {
			MsgBox("A file named `"" newName "`" already exists. Try again.", "Error", 16)
			return
		}
		try {
			if FileExist(oldPath) ; Unsaved notes have no file; only their list entry changes.
				FileMove oldPath, newPath
		} catch as Err {
			Log("Could not rename note '" oldPath "' to '" newPath "': " Err.Message, "WARN", "PluginScratchPad")
			MsgBox("Could not rename `"" oldName "`".", programinfo.name, 48)
			return
		}
		; The backup follows the note. Overwrite any orphaned .bak left under the new name.
		; A failure here isn't fatal: the note itself has already been renamed.
		try {
			if FileExist(oldPath ".bak")
				FileMove oldPath ".bak", newPath ".bak", 1
		} catch as Err {
			Log("Could not rename note backup '" oldPath ".bak': " Err.Message, "WARN", "PluginScratchPad")
		}
		this.NotesDDL.Delete(this.ListIndexOf(oldName))
		this.NotesDDL.Add([newName])
		this.NotesDDL.Choose(this.ListIndexOf(newName))
		this.LastLoadedNote := newName ; Unsaved edits now belong to the new name.
		this.SaveSetting("Notes", "current_note", newName)
	}

	static DeleteNote(*) { ; Deletes the currently loaded note.
		index := this.NotesDDL.Value ; 0 if nothing is selected.
		if !index
			return
		noteName     := this.NotesDDL.Text
		noteLocation := this.scratchpadFolder "\" noteName
		if MsgBox("Delete current note?", programinfo.name, "OKCancel") != "OK"
			return
		try {
			if FileExist(noteLocation) ; Unsaved new notes have no file yet; they still get removed from the list.
				FileDelete noteLocation
		} catch as Err {
			Log("Could not delete note '" noteLocation "': " Err.Message, "WARN", "PluginScratchPad")
			MsgBox("Could not delete `"" noteName "`".", programinfo.name, 48)
			return
		}
		; SaveFile() leaves a "<note>.bak" next to each saved note. It's hidden from the list, so remove it too.
		; A failure here isn't fatal: the note itself is already gone, so just log it and carry on.
		backupLocation := noteLocation ".bak"
		try {
			if FileExist(backupLocation)
				FileDelete backupLocation
		} catch as Err {
			Log("Could not delete note backup '" backupLocation "': " Err.Message, "WARN", "PluginScratchPad")
		}
		this.NotesDDL.Delete(index)
		; Neither flag may refer to the deleted note anymore. Resetting them first stops LoadNote()
		; from offering to save changes to a file that no longer exists.
		this.currentNoteHasChanged := FALSE
		this.LastLoadedNote := ""
		remaining := ControlGetItems(this.NotesDDL).Length
		if (remaining = 0) { ; Last note deleted: start a fresh one so whatever gets typed next has somewhere to be saved.
			this.StartDefaultNote()
			return
		}
		this.NotesDDL.Choose(Min(index, remaining)) ; Select the neighbour that took its place.
		this.LoadNote()
		this.SaveSetting("Notes", "current_note", this.NotesDDL.Text)
	}
	
	static LoadNote(*) { ; Load a new file whenever it's chosen on the DropDownList.
		currentNote := this.NotesDDL.text
		CurrentNoteLocation := this.scratchpadFolder "\" this.NotesDDL.text
		LastLoadedNoteLocation := this.scratchpadFolder "\" this.LastLoadedNote
		if (this.currentNoteHasChanged == TRUE) {
			result := MsgBox("The current note has been modified. Save changes before switching?", programinfo.name, "YesNo")
			if Result = "Yes" {
				; No existence check: notes from NewNote()/StartDefaultNote() have no file until their first save,
				; and SaveFile() creates it.
				if !this.SaveNote(LastLoadedNoteLocation) {
					; Stay on the unsaved note rather than discarding its contents by loading another one.
					MsgBox("Could not save `"" this.LastLoadedNote "`".", programinfo.name, 48)
					this.NotesDDL.Choose(this.LastLoadedNote)
					return
				}
				this.currentNoteHasChanged := FALSE
			}
		}
		; A new note that was left without saving has no file, so it would only show a load error if picked again.
		; Drop it from the list.
		if (this.LastLoadedNote != "" && this.LastLoadedNote != currentNote && !FileExist(LastLoadedNoteLocation))
			this.RemoveFromList(this.LastLoadedNote)
		if !FileExist(CurrentNoteLocation) {
			this.LoadNoteError(CurrentNoteLocation)
			return
		}
		this.ScratchpadMainEdit.Value := FileRead(CurrentNoteLocation)
		this.currentNoteHasChanged := FALSE
		this.LastLoadedNote := this.NotesDDL.Text
	}

	;== Text tools ======================================================================
	static TransformText(operation, *) { ; Applies a text tool to the selection, or the whole note if there's none.
		static EM_GETSEL := 0xB0, EM_SETSEL := 0xB1, EM_REPLACESEL := 0xC2
		edit := this.ScratchpadMainEdit
		selStart := Buffer(4), selEnd := Buffer(4)
		SendMessage(EM_GETSEL, selStart.Ptr, selEnd.Ptr, edit)
		startPos := NumGet(selStart, "UInt"), endPos := NumGet(selEnd, "UInt")
		; Use the control's raw text, not edit.Value: Value turns `r`n into `n, which throws the selection
		; offsets off by one character for every line break before them.
		rawText := ControlGetText(edit)
		if (startPos = endPos) { ; Nothing selected: work on the whole note.
			startPos := 0
			endPos := StrLen(rawText)
		}
		oldText := SubStr(rawText, startPos + 1, endPos - startPos)
		; Edit controls use `r`n. Work on `n only so the line operations and regexes stay simple.
		text := StrReplace(oldText, "`r`n", "`n")
		switch operation {
			case "blanklines": ; Whitespace-only lines count as blank.
				; "m`n)" = ^ and $ work per line, with `n as the only line break.
				text := RegExReplace(text, "m`n)^[ \t]*\n", "") ; Blank lines followed by a line break...
				text := RegExReplace(text, "\n[ \t]*\z", "")    ; ...and a trailing blank last line.
			case "trim":
				text := RegExReplace(text, "m`n)^[ \t]+|[ \t]+$", "")
			case "upper":
				text := StrUpper(text)
			case "lower":
				text := StrLower(text)
			case "sentence": ; Capitalise the first letter of each line and after . ! ?
				; Group 2 skips non-letters before it on the same line, so "- item" and "(note" work too.
				text := RegExReplace(StrLower(text), "(^|\n|[.!?][ \t\n]+)([^\p{L}\n.!?]*?)(\p{L})", "$1$2$U3")
		}
		text := StrReplace(text, "`n", "`r`n")
		if (text == oldText)
			return ; Nothing to change; don't mark the note as modified.
		SendMessage(EM_SETSEL, startPos, endPos, edit)
		SendMessage(EM_REPLACESEL, TRUE, StrPtr(text), edit) ; TRUE = can be undone with Ctrl+Z.
		SendMessage(EM_SETSEL, startPos, startPos + StrLen(text), edit) ; Keep the result selected.
		this.currentNoteHasChanged := TRUE
	}

	static NoteChanged(*) { ; Triggers whenever the edit control is modified.
		this.currentNoteHasChanged := TRUE
	}

	static SaveCurrentNote(*){
		if (this.NotesDDL.Text = "")
			return ; No note is loaded, nothing to save.
		currentNote := this.scratchpadFolder "\" this.NotesDDL.text
		this.SaveNote(currentNote)
		this.currentNoteHasChanged := FALSE
		this.SaveSetting("Notes", "current_note", this.NotesDDL.text)
	}

	static SaveNote(file) { ; File saving routine. Returns true on success.
		return this.SaveFile(file, this.ScratchpadMainEdit.Value)
	}
}