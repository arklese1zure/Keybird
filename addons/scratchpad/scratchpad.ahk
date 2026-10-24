
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
		this.ScratchpadMainEdit := mainGui.Add("Edit", "h283 w248 x+0 y+0", "Write your notes here.")
			this.ScratchpadMainEdit.OnEvent("Change", ObjBindMethod(this, "NoteChanged"))
		this.NotesDDL := mainGui.Add("DropDownList", "w160 h35 xp+2 y312 r6", [])
			this.NotesDDL.OnEvent("Change", ObjBindMethod(this, "LoadNote"))
		ScratchPadButton1 := mainGui.Add("Button", "w25 h25 x+2 yp-2")
			GuiButtonIcon(ScratchPadButton1, iconsDir "\actions\document-save.ico", 1, "s16")
			ScratchPadButton1.OnEvent("Click", ObjBindMethod(this, "SaveCurrentNote"))
		ScratchPadButton2 := mainGui.Add("Button", "w25 h25 x+1")
			GuiButtonIcon(ScratchPadButton2, iconsDir "\actions\list-add.ico", 1, "s16")
			ScratchPadButton2.OnEvent("Click", ObjBindMethod(this, "NewNote"))
		ScratchPadButton3 := mainGui.Add("Button", "w25 h25 x+1")
			GuiButtonIcon(ScratchPadButton3, iconsDir "\actions\list-remove.ico", 1, "s16")
			ScratchPadButton3.OnEvent("Click", ObjBindMethod(this, "DeleteNote"))
		this.LoadNotesList()
		this.LoadLastNote()
	}

	;## Gui functions ###################################################################
	static LoadNotesList(*) { ; Fills the dropdown with all the stored text files.
		if !DirExist(this.scratchpadFolder)
			return
		; Ensure no trailing backslash before appending "\*".
		folder := SubStr(this.scratchpadFolder, -1, 1) = "\" ? SubStr(this.scratchpadFolder, 1, -1) : this.scratchpadFolder
		Loop Files folder "\*" {
			this.NotesDDL.Add([A_LoopFileName])
		}
	}

	static LoadLastNote(*) { ; Read last opened note from the settings ini and load the file.
		if !FileExist(this.currentNote) { ; If there's no file with the stored filename, create a new file instead.
			this.SaveSetting("Notes", "current_note", "New note.txt")
			this.NotesDDL.Add(["New note.txt"])
			this.NotesDDL.Choose("New note.txt")
			this.ScratchpadMainEdit.Value := "Write your notes here..."
			this.currentNoteHasChanged := TRUE
			this.LastLoadedNote := this.NotesDDL.Text
			return
		} else {
			this.ScratchpadMainEdit.Value := FileRead(this.currentNote)
			this.currentNoteName := this.GetSetting("Notes", "current_note", "New note.txt")
			this.NotesDDL.Choose(this.currentNoteName)
			this.currentNoteHasChanged := FALSE
			this.LastLoadedNote := this.NotesDDL.Text
		}
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
	
	static DeleteNote(*) { ; Deletes the currently loaded note.
		index := this.ScratchPadDDL.Value ; 0 if nothing is selected.
		if !index
			return
		noteName     := this.ScratchPadDDL.Text
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
		this.ScratchPadDDL.Delete(index)
		; Neither flag may refer to the deleted note anymore. Resetting them first stops LoadNote()
		; from offering to save changes to a file that no longer exists.
		this.currentNoteHasChanged := FALSE
		this.LastLoadedNote := ""
		remaining := ControlGetItems(this.ScratchPadDDL).Length
		if (remaining = 0) {
			this.ScratchpadMainEdit.Value := ""
			this.SaveSetting("Notes", "current_note", "New note.txt")
			return
		}
		this.ScratchPadDDL.Choose(Min(index, remaining)) ; Select the neighbour that took its place.
		this.LoadNote()
		this.SaveSetting("Notes", "current_note", this.ScratchPadDDL.Text)
	}
	
	static LoadNote(*) { ; Load a new file whenever it's chosen on the DropDownList.
		currentNote := this.NotesDDL.text
		CurrentNoteLocation := this.scratchpadFolder "\" this.NotesDDL.text
		LastLoadedNoteLocation := this.scratchpadFolder "\" this.LastLoadedNote
		if (this.currentNoteHasChanged == TRUE) {
			result := MsgBox("The current note has been modified. Save changes before switching?", programinfo.name, "YesNo")
			if Result = "Yes" {
				this.currentNoteHasChanged := FALSE
				if !FileExist(LastLoadedNoteLocation) {
					this.LoadNoteError(LastLoadedNoteLocation)
					return
				}
				this.SaveNote(LastLoadedNoteLocation)
				this.currentNoteHasChanged := FALSE
			}
		}
		if !FileExist(CurrentNoteLocation) {
			this.LoadNoteError(CurrentNoteLocation)
			return
		}
		this.ScratchpadMainEdit.Value := FileRead(CurrentNoteLocation)
		this.currentNoteHasChanged := FALSE
		this.LastLoadedNote := this.NotesDDL.Text
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

	static SaveNote(file) { ; File saving routine.
		this.SaveFile(file, this.ScratchpadMainEdit.Value)
	}
}