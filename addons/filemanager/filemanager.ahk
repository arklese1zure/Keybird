
;				=========================================================================
;				|||||						File manager							|||||
;				=========================================================================

class PluginFileManager extends PluginBase {

	static PluginKey    := "file_manager"           ; internal plugin name, used to match it with several elements.
	
	static settingsFile := A_WorkingDir "\userprofile\filemanager.ini"

	static __New() { ;## Startup ########################################################
		;== Hooks =======================================================================
		Plugin_Main_AddTab(
			ObjBindMethod(this, "BuildTabContents"),			; Tab contents.
			"File manager",										; Tab name. This works as a fallback.
			"\addons\filemanager\res\tabicon.ico",				; Tab icon.
			ObjBindMethod(this, "RefreshFilesLV"),				; Tab left-click action.
			,													; Tab right-click action.
			"file_manager"										; PluginKey (internal name).
		)
		Plugin_Settings_AddTab(ObjBindMethod(this, "BuildSettingsTab"), "File manager", "file_manager") ; Second argument is optional if you're providing a translation file.
		Plugin_Settings_SaveSettings(ObjBindMethod(this, "SaveSettings"), "File manager")

		;== Settings ====================================================================
		; Write default settings file if not present.
		if !FileExist(this.settingsFile)
			this.SaveSetting("Settings", "root_folder", A_WorkingDir "\userstorage")
		; Read root folder; fall back to script directory if saved path is gone.
		this.rootFolder := this.GetSetting("Settings", "root_folder", A_WorkingDir "\userstorage")
		if !FileExist(this.rootFolder)
			this.rootFolder := A_WorkingDir

		;== Drop folder =================================================================
		this.dropFolder := A_WorkingDir "\userprofile\droppedfiles"
		if !this.EnsureFolder(this.dropFolder) {
			Log("Could not create drop folder, falling back to script root.", "WARN", "PluginFileManager")
			this.dropFolder := A_WorkingDir
		}

		;== Variables ===================================================================
		this.PathMap		:= Map()	; Maps TreeView item handles to their full paths.
		this.IconMap		:= Map()	; Caches extension → ImageList icon index.
		this.dropFolderItem	:= 0		; TreeView handle for the drop folder node.
	}

	static BuildTabContents() { ;## Gui tab contents ####################################
		;== Gui menus ===================================================================
		this.ContextMenu := Menu()
		this.ContextMenu.Add(this.T("contextmenu_open"),		ObjBindMethod(this, "HandleMenuAction", "FileOpen"))
			this.ContextMenu.Default := this.T("contextmenu_open")
		this.ContextMenu.Add()
		this.ContextMenu.Add(this.T("contextmenu_rename"),		ObjBindMethod(this, "HandleMenuAction", "FileRename"))
		this.ContextMenu.Add(this.T("contextmenu_delete"),		ObjBindMethod(this, "HandleMenuAction", "FileDelete"))
		this.ContextMenu.Add()
		this.ContextMenu.Add(this.T("contextmenu_properties"),	ObjBindMethod(this, "HandleMenuAction", "FileProperties"))

		;== Gui components ==============================================================
		ImageListID := IL_Create(1)
			IL_Add(ImageListID, iconsDir "\places\folder.ico")

		;-- Folder TreeView -------------------------------------------------------------
		;this.FolderTree := mainGui.Add("TreeView", "h100 w248 x+0 y+0 ImageList" ImageListID)
		this.FolderTree := mainGui.Add("TreeView", "h100 w" main_tab_w " x" main_tab_x0 " y"  main_tab_y0  " ImageList" ImageListID)		
			this.FolderTree.OnEvent("ItemSelect", ObjBindMethod(this, "OnFolderSelected"))
		; Root node is labelled with the folder name.
		rootLabel := SubStr(this.rootFolder, InStr(this.rootFolder, "\",, -1) + 1)
		rootItem := this.FolderTree.Add(rootLabel, 0, "Icon1")
		this.PathMap[rootItem] := this.rootFolder "\"
		; Drop folder node
		this.dropFolderItem := this.FolderTree.Add(this.T("tv_foldername_droppedfiles"), 0, "Icon1")
		this.PathMap[this.dropFolderItem] := this.dropFolder
		; Subfolders of root
		this.AddSubfolders(this.rootFolder)

		;-- Files ListView --------------------------------------------------------------
		;this.FilesLV := mainGui.Add("ListView", "h177 w" main_tab_w " y+3", [this.T("lv_header_col1")])
		lv_height := main_tab_h_bar - 100
		this.FilesLV := mainGui.Add("ListView", "h" lv_height " w" main_tab_w " y+3", [this.T("lv_header_col1")])
		this.ImageListID1 := IL_Create(10)
		this.FilesLV.SetImageList(this.ImageListID1)
		this.FilesLV.OnEvent("DoubleClick", ObjBindMethod(this, "OpenFile"))
		this.FilesLV.OnEvent("ContextMenu", ObjBindMethod(this, "ShowContextMenu"))
		this.SelectFirstFolder()

		;-- Bottom bar ------------------------------------------------------------------
		BtnContextMenu := mainGui.Add("Button", "w25 h" main_bar_h " xp+2 y312")
			GuiButtonIcon(BtnContextMenu, iconsDir "\categories\applications-system.ico", 1, "s16")
			BtnContextMenu.OnEvent("Click", ObjBindMethod(this, "ShowContextMenuFromButton"))
		BtnRefresh := mainGui.Add("Button", "w25 h"  main_bar_h  " x+1")
			GuiButtonIcon(BtnRefresh, iconsDir "\actions\view-refresh.ico", 1, "s16")
			BtnRefresh.OnEvent("Click", ObjBindMethod(this, "RefreshFilesLV"))

		;-- Drop target -----------------------------------------------------------------
		mainGui.OnEvent("DropFiles", ObjBindMethod(this, "OnFilesDropped"))
	}

	static BuildSettingsTab(*) { ;## Settings tab contents ##############################
		;settingsGuiTabs.Add(["File manager"])
		;settingsGuiTabs.UseTab("File manager") ; This name is used as a fallback.
		;-- Directory selection ---------------------------------------------------------
		SettingsGui.Add("GroupBox",							"x" settings_tab_x0 " y" settings_tab_y0 " w" settings_tab_w " h45",	this.T("settings_gbox_rootfolder"))
		this.currentFolderBox := SettingsGui.Add("Edit",	"xp+6 yp+16 w306 r1",	this.rootFolder)
		BtnSelectFolder := SettingsGui.Add("Button",		"x+5",				this.T("settings_btn_select_folder"))
			BtnSelectFolder.OnEvent("Click", ObjBindMethod(this, "ChangeFolder"))
	}

	;## Gui functions ###################################################################
	;== TreeView ========================================================================
	static AddSubfolders(folder, parentItem := 0, currentDepth := 1, maxDepth := 3) {
		; Prevent recursing into the script's own directory.
		if SubStr(folder, 1, StrLen(A_WorkingDir)) = A_WorkingDir
			return
		if (currentDepth > maxDepth)
			return
		try {
			loop Files folder "\*", "D" {
				if InStr(A_LoopFileAttrib, "H") || InStr(A_LoopFileAttrib, "S")
					continue
				item := this.FolderTree.Add(A_LoopFileName, parentItem, "Icon1")
				this.PathMap[item] := A_LoopFileFullPath
				this.AddSubfolders(A_LoopFileFullPath, item, currentDepth + 1, maxDepth)
			}
		} catch as Err {
			Log("Could not read subfolders of '" folder "': " Err.Message, "WARN", "PluginFileManager")
		}
	}

	static OnFolderSelected(ctrl, info) {
		selectedItem := ctrl.GetSelection()
		; Show a hint tooltip when the user selects the drop folder for the first time.
		if (selectedItem = this.dropFolderItem) {
			ToolTip this.T("tv_tooltip_dragndrophint")
			SetTimer () => ToolTip(), -3000
		}
		this.FilesLV.Delete()
		if this.PathMap.Has(selectedItem)
			this.LoadFolder(this.PathMap[selectedItem])
	}

	static SelectFirstFolder(*) { ; Select and load the first root node on launch.
		firstItem := this.FolderTree.GetChild(0)
		if this.PathMap.Has(firstItem)
			this.LoadFolder(this.PathMap[firstItem])
	}

	;== Files ListView ==================================================================
	static LoadFolder(folderPath) { ; Load a folder's files into FilesLV with system icons.
		if !folderPath
			return
		if SubStr(folderPath, -1, 1) = "\"
			folderPath := SubStr(folderPath, 1, -1)
		sfi_size := A_PtrSize + 688
		sfi := Buffer(sfi_size)
		this.FilesLV.Opt("-Redraw")
		Loop Files, folderPath "\*.*" {
			FileName := A_LoopFilePath
			SplitPath(FileName,,, &FileExt)
			; EXE/ICO/ANI/CUR each get a unique icon regardless of extension matching.
			if FileExt ~= "i)\A(EXE|ICO|ANI|CUR)\z" {
				ExtID := FileExt
				IconNumber := 0
			} else {
				; Build a numeric ID from up to 7 extension characters for fast cache lookup.
				ExtID := 0
				Loop 7 {
					ExtChar := SubStr(FileExt, A_Index, 1)
					if !ExtChar
						break
					ExtID := ExtID | (Ord(ExtChar) << (8 * (A_Index - 1)))
				}
				IconNumber := this.IconMap.Has(ExtID) ? this.IconMap[ExtID] : 0
			}
			if !IconNumber {
				if !DllCall("Shell32\SHGetFileInfoW", "Str", FileName, "Uint", 0, "Ptr", sfi, "UInt", sfi_size, "UInt", 0x101)
					IconNumber := 9999999 ; Out of bounds → blank icon.
				else {
					hIcon := NumGet(sfi, 0, "Ptr")
					IconNumber := DllCall("ImageList_ReplaceIcon", "Ptr", this.ImageListID1, "Int", -1, "Ptr", hIcon) + 1
					DllCall("DestroyIcon", "Ptr", hIcon)
					this.IconMap[ExtID] := IconNumber
				}
			}
			this.FilesLV.Add("Icon" IconNumber, A_LoopFileName)
		}
		this.FilesLV.ModifyCol(1,, folderPath)
		this.FilesLV.Opt("+Redraw")
	}

	static OpenFile(*) { ; Open the focused file with its default application.
		fullPath := this.GetSelectedFolderPath()
		if !fullPath
			return
		focusedRow := this.FilesLV.GetNext(0, "F")
		if !focusedRow
			return
		fileName := this.FilesLV.GetText(focusedRow, 1)
		try
			Run(fullPath "\" fileName)
		catch
			MsgBox(this.T("msgbox_fileactionerror"))
	}

	static ShowContextMenu(LV, Item, IsRightClick, X, Y) {
		this.ContextMenu.Show(X, Y)
	}

	static ShowContextMenuFromButton(*) {
		this.ContextMenu.Show()
	}

	static HandleMenuAction(action, *) { ; Dispatcher for all file context menu actions.
		fullPath := this.GetSelectedFolderPath()
		if !fullPath
			return
		focusedRow := this.FilesLV.GetNext(0, "F")
		if !focusedRow
			return
		fileName := this.FilesLV.GetText(focusedRow, 1)
		filePath  := fullPath "\" fileName
		try {
			if (action = "FileOpen")
				Run(filePath)
			if (action = "FileProperties")
				Run("properties " filePath)
			if (action = "FileDelete") {
				result := MsgBox(this.T("msgbox_confirmdelete") "`n" fileName,, "YesNo")
				if (result = "Yes") {
					FileRecycle filePath
					this.RefreshFilesLV()
				}
			}
			if (action = "FileRename") {
				newName := InputBox(this.T("inputbox_filerename") "`n '" fileName "'", "Rename")
				if (newName.Result = "Cancel" || newName.Value = "")
					return
				newPath := fullPath "\" newName.Value
				if FileExist(newPath) {
					MsgBox(this.T("msgbox_dupefilename"), "Rename", 16)
					return
				}
				FileMove(filePath, newPath)
				this.RefreshFilesLV()
			}
		} catch as Err {
			Log("File action '" action "' failed on '" filePath "': " Err.Message, "WARN", "PluginFileManager")
			MsgBox(this.T("msgbox_fileactionerror"))
		}
	}

	static RefreshFilesLV(*) { ; Reload the files ListView for the currently selected folder.
		selectedItem := this.FolderTree.GetSelection()
		if this.PathMap.Has(selectedItem) {
			this.FilesLV.Delete()
			this.LoadFolder(this.PathMap[selectedItem])
		}
	}

	static GetSelectedFolderPath() { ; Returns the full path of the selected TreeView folder, or "" on failure.
		selectedItem := this.FolderTree.GetSelection()
		if selectedItem = 0
			selectedItem := this.FolderTree.GetChild(0)
		if this.PathMap.Has(selectedItem)
			return this.PathMap[selectedItem]
		MsgBox(this.T("msgbox_nofolderselected"))
		return ""
	}

	;== Settings tab ====================================================================
	static ChangeFolder(*) {
		chosen := FileSelect("D",, this.T("folrderselect_prompt"))
		if chosen != ""
			this.currentFolderBox.Text := chosen
	}

	static SaveSettings(*) {
		if this.currentFolderBox.Text = ""
			return
		this.SaveSetting("Settings", "root_folder", this.currentFolderBox.Text)
	}

	;== Drop handler ====================================================================
	static OnFilesDropped(GuiObj, GuiCtrlObj, FileArray, X, Y) {
		for i, droppedFile in FileArray {
			try
				FileCopy droppedFile, this.dropFolder
			catch as Err
				Log("Could not copy dropped file '" droppedFile "': " Err.Message, "WARN", "PluginFileManager")
		}
	}
}
