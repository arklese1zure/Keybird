
;				=========================================================================
;				|||||							To-Do list							|||||
;				=========================================================================

class PluginToDo extends PluginBase {

	static PluginKey    := "todo"

	static __New() { ;## Startup ########################################################
		;== Hooks =======================================================================
		Plugin_Main_AddTab(
			ObjBindMethod(this, "BuildTabContents"),		; Tab contents
			"To-Do",										; Tab name
			"\addons\todo\res\tab.ico",						; Tab icon
			,												; Function when tab is selected
			ObjBindMethod(this, "ShowTabMenu"),				; Function when tab is right-clicked
			"todo"											; PluginKey
		)
		Plugin_Main_OnExit(ObjBindMethod(this, "SaveTodo"), "To-Do")
		Plugin_AddMainMenuItem(ObjBindMethod(this, "AddToDoEntry"), "New to-do task", "todo")
		
		;== Setup =======================================================================
		this.todoFile := A_WorkingDir "\userprofile\todo.md"
		this.EnsureFile(this.todoFile) ; Create an empty file if not present; logs on failure.
	}
	
	static BuildTabContents() { ;## Gui tab contents ####################################
		;== Gui menus ===================================================================
		;-- Main menu -------------------------------------------------------------------
		this.ToDoLVMenu := Menu()
			this.ToDoLVMenu.Add(this.T("lvmenu_newentry"), ObjBindMethod(PluginToDo, "AddToDoEntry"))
			this.ToDoLVMenu.Add(this.T("lvmenu_removeentry"), ObjBindMethod(PluginToDo, "RemoveToDoEntry"))
			this.ToDoLVMenu.Add()
			this.ToDoLVMenu.Add(this.T("lvmenu_removechecked"), ObjBindMethod(PluginToDo, "CleanUpToDo"))
			this.ToDoLVMenu.Add()
			this.ToDoLVMenu.Add(this.T("lvmenu_save"), ObjBindMethod(PluginToDo, "SaveTodo"))
			
		;-- Quick access menu -----------------------------------------------------------
		this.ToDoQuickMenu := Menu()
			this.ToDoQuickMenu.Add(this.T("lvmenu_newentry"), ObjBindMethod(PluginToDo, "AddToDoEntry"))
			this.ToDoQuickMenu.Add()
			this.ToDoQuickMenu.Add(this.T("lvmenu_save"), ObjBindMethod(PluginToDo, "SaveTodo"))
		
		;== Gui components ==============================================================
		this.LV_todo := mainGui.Add("ListView", "h283 w248 x+0 y+0 Checked", [this.T("lv_column1")])
		this.FillToDoLV()
		this.LV_todo.ModifyCol()
		BtnShowMenu := mainGui.Add("Button", "w25 h25 xp+2 y312")
			GuiButtonIcon(BtnShowMenu, iconsDir "\categories\applications-system.ico", 1, "s16")
			BtnShowMenu.OnEvent("Click", (*) => this.ToDoLVMenu.Show())
		BtnSave := mainGui.Add("Button", "w25 h25 x+1")
			GuiButtonIcon(BtnSave, iconsDir "\actions\document-save.ico", 1, "s16")
			BtnSave.OnEvent("Click", ObjBindMethod(this, "SaveTodo"))
		BtnAddEntry := mainGui.Add("Button", "w25 h25 x+1")
			GuiButtonIcon(BtnAddEntry, iconsDir "\actions\list-add.ico", 1, "s16")
			BtnAddEntry.OnEvent("Click", ObjBindMethod(this, "AddToDoEntry"))
		BtnRemoveEntry := mainGui.Add("Button", "w25 h25 x+1")
			GuiButtonIcon(BtnRemoveEntry, iconsDir "\actions\list-remove.ico", 1, "s16")
			BtnRemoveEntry.OnEvent("Click", ObjBindMethod(this, "RemoveToDoEntry"))
		BtnRemoveChecked := mainGui.Add("Button", "w25 h25 x+1")
			GuiButtonIcon(BtnRemoveChecked, iconsDir "\actions\edit-clear.ico", 1, "s16")
			BtnRemoveChecked.OnEvent("Click", ObjBindMethod(this, "CleanUpToDo"))
	}

	;## Gui functions ###################################################################
	static FillToDoLV(*) { ; Fill the to-do listview from the markdown file.
		this.LV_todo.Opt("-Redraw")
		Loop read, this.todoFile {
			line := Trim(A_LoopReadLine)
			if (line = "" || SubStr(line, 1, 1) = ";")
				continue
			; Parse markdown checkbox format: "- [x] Task text" or "- [ ] Task text".
			; Also accepts "*" and "+" bullets; they're normalized to "-" on the next save.
			if !RegExMatch(line, "i)^[-*+]\s+\[([ x])\]\s+(.+)$", &m)
				continue ; Skip malformed lines.
			if (m[1] = " ")
				this.LV_todo.Add(, m[2])
			else
				this.LV_todo.Add("Check", m[2])
		}
		this.LV_todo.Opt("+Redraw")
	}

	static AddToDoEntry(*) {
		newToDoEntryName := InputBox(this.T("inputbox_entryname"), programinfo.name " - " this.T("tab_name"))
		if newToDoEntryName.Result = "Cancel"
			return
		this.LV_todo.Add(,newToDoEntryName.Value) ; Create a new row in the ListView and assign the text to it.
		this.LV_todo.ModifyCol()
		}

	static RemoveToDoEntry(*) {
		selectedRow := this.LV_todo.GetNext() ; Get the text of the first field.
		if selectedRow = 0
			return
		this.LV_todo.Delete(selectedRow)
		this.LV_todo.ModifyCol()
	}

	static CleanUpToDo(*) { ; Clean checked items.
		; Iterate backward so that deleting a row doesn't shift the indices of rows not yet visited.
		RowCount := this.LV_todo.GetCount()
		Loop RowCount {
			row := RowCount - A_Index + 1 ; Count down from the last row.
			if this.IsRowChecked(this.LV_todo, row)
				this.LV_todo.Delete(row)
		}
		this.LV_todo.ModifyCol()
	}

	static SaveTodo(*) { ; Export to-do listview as a markdown-formatted file.
		content := ""
		RowCount := this.LV_todo.GetCount()
		Loop RowCount {
			RowChecked := this.IsRowChecked(this.LV_todo, A_Index) ? "x" : " "
			content .= "- [" RowChecked "] " this.LV_todo.GetText(A_Index) "`n"
		}
		this.SaveFile(this.todoFile, content)
	}

	;## General functions ###############################################################
	static IsRowChecked(LV, Row) {
		; Usage: LV is the variable that contains the ListView to evaluate, Row is the row to evaluate.
		RowState := SendMessage(0x102C, Row - 1, 0xF000, LV) ; 0x102C is LVM_GETITEMSTATE. 0xF000 is LVIS_STATEIMAGEMASK.
		if (RowState == 8192) ; In the documentation, 8192 means "checked".
			ItemState := TRUE
		else
			ItemState := FALSE
		return ItemState
	}
	
	static ShowTabMenu(*) { ; Helper function to show the tab's menu.
		this.ToDoQuickMenu.Show()
	}
}