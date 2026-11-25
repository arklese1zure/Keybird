
;		=========================================================================
;		|||||						Keybird	- Help viewer					|||||
;		=========================================================================
;
;	Renders help topics (docs\*.md) with a RichEdit control.
;	Markdown is converted to RTF with MarkdownToRTF and placed into the control.
;
;	Topic navigation is a TreeView built from docsFolder. Each subfolder
;	becomes an expandable node.
;
;	Addons can contribute their own documentation by adding a docs folder (addons\<name>\docs\*.md).
;	These are grouped under the "Addon Documentation" node.
;
;	Window layout: Resizable window. The tree pane is fixed and the RichEdit
;	pane is resized.

;== Include scripts and libraries ===============================================
#Include %A_ScriptDir%\lib\RichEdit.ahk
#Include %A_ScriptDir%\lib\markdown_rtf.ahk
#Include %A_ScriptDir%\lib\RichEditOleCallback.ahk

;## Setup #######################################################################
global docsFolder			:= A_WorkingDir "\docs" ; Folder containing help topic markdown files.
global addonDocsSubfolder	:= "docs" ; Looked for as <addon folder>\docs\*.md.
global helpViewerHwnd		:= "" ; Tracks the currently open help viewer window, if any.
global docTreeFiles			:= Map() ; TreeView item ID -> absolute file path, for file nodes.
global helpViewerTreeWidth	:= 240 ; Fixed width of the tree pane.
global helpViewerMargin		:= 3 ; Gap between the content and the window edges.
global helpViewerMinWidth	:= 846 ; Narrowest the window can get. Also decides how wide pictures may be, so they never get clipped.

;## Build gui ###################################################################
BuildHelpViewer(selectedHelpFile := "Credits.md") {
	global mainGui, helpViewerHwnd, helpTopicRE, helpViewerTreeWidth, helpViewerMargin

	if (helpViewerHwnd != "" && WinExist("ahk_id " helpViewerHwnd)) {	; If a viewer is already open
		WinActivate("ahk_id " helpViewerHwnd)							; bring it forward and switch topics
		OpenDocFile(selectedHelpFile)
		return
	}
	
	global HelpViewerGui := Gui("+Resize")
	global helpTopicsTV := HelpViewerGui.Add("TreeView", "x" helpViewerMargin " y" helpViewerMargin " h479 w" helpViewerTreeWidth)
		helpTopicsTV.OnEvent("ItemSelect", DocTreeItemSelected)
	LoadDocsTree()
	;-- RichEdit control --------------------------------------------------------
	helpTopicRE := RichEdit(HelpViewerGui, "x+" helpViewerMargin " y" helpViewerMargin " h479 w597")
	helpTopicRE.SetOptions(["READONLY"], "SET")
	if !RichEdit_EnableImages(helpTopicRE) ; lets the control keep pictures; must happen before the first SetText.
		Log("RichEdit rejected the OLE callback; pictures in help topics will be blank.", "WARN", "BuildHelpViewer")
	helpTopicRE.SetEventMask(["LINK"])
	helpTopicRE.OnNotify(0x070B, HelpTopicLinkClicked)
	helpTopicRE.WordWrap(True) ; wrap to the control's width instead of scrolling sideways.
	;-- Event handlers ----------------------------------------------------------
	HelpViewerGui.OnEvent("Close", HelpViewerGuiClose)
	HelpViewerGui.OnEvent("Escape", HelpViewerGuiEscape)
	HelpViewerGui.OnEvent("Size", HelpViewerGuiSize)
	;-- Gui options -------------------------------------------------------------
	HelpViewerGui.Title := programinfo.name " — " T("title_helpviewer")
	HelpViewerGui.Opt("+MinSize" helpViewerMinWidth "x300")
	HelpViewerGui.Show("h485 w846")
	;-- Post-build actions ------------------------------------------------------
	helpViewerHwnd := HelpViewerGui.Hwnd
	OpenDocFile(selectedHelpFile)
}	

HelpViewerGuiSize(GuiObj, MinMax, Width, Height) { ; HelpViewerGuiSize() is used for tracking size and text-wrapping.
	global helpTopicsTV, helpTopicRE, helpViewerTreeWidth, helpViewerMargin
	if (MinMax = -1) ; Minimized, don't resize.
		return
	
	paneHeight := Height - (helpViewerMargin * 2) ; Tree pane keeps a fixed width and just grows/shrinks vertically.
	contentX := helpViewerTreeWidth + (helpViewerMargin * 2) ; RichEdit pane absorbs all the extra width and height.
	contentWidth := Width - contentX - helpViewerMargin
	if (contentWidth < 1) ; Prevent handing Move() a negative size.
		return
	helpTopicsTV.Move(, , , paneHeight)
	helpTopicRE.Move(, , contentWidth, paneHeight)
	; RichEdit doesn't auto-track the window resize the way the control does
	; Without this, the text area stays pinned to whatever size it was at construction.
	helpTopicRE.SetRect(6, 2, contentWidth, paneHeight)
}

DocTreeItemSelected(Ctrl, ItemID) { ; Check if clicked element is a file before attempting to load.
	global docTreeFiles
	if docTreeFiles.Has(ItemID)
		OpenDocFile(docTreeFiles[ItemID])
}
	
;## Functions ###################################################################
;== Gui =========================================================================
LoadDocsTree(*) { ; Rebuild the tree from docsFolder's (and addons') layout.
	global helpTopicsTV, docsFolder, docTreeFiles
	helpTopicsTV.Opt("-Redraw")
	helpTopicsTV.Delete() ; clear any existing nodes first
	docTreeFiles := Map()
	BuildDocsTreeLevel(docsFolder, 0)
	BuildAddonDocsTree()
	helpTopicsTV.Opt("+Redraw")
}

BuildDocsTreeLevel(folderPath, parentItemID) { ; Build TreeView from the main script's documentation folders. Returns how many entries were added.
	global helpTopicsTV, docTreeFiles

	added := 0
	subfolders := []
	loop Files folderPath "\*", "D"
		subfolders.Push(A_LoopFileName)
	for _, folderName in SortedArray(subfolders) { ; Recurses one folder at a time. Subfolders become expandable parent nodes.
		nodeID := helpTopicsTV.Add(folderName, parentItemID)
		if BuildDocsTreeLevel(folderPath "\" folderName, nodeID)
			added++
		else
			helpTopicsTV.Delete(nodeID) ; No topics inside (e.g. an images folder): don't show an empty node.
	}

	files := []
	loop Files folderPath "\*.md"
		files.Push(A_LoopFileName)
	for _, fileName in SortedArray(files) {
		displayName := RegExReplace(fileName, "\.md$", "") ; users don't need to see the extension
		itemID := helpTopicsTV.Add(displayName, parentItemID)
		docTreeFiles[itemID] := folderPath "\" fileName
		added++
	}
	return added
}

BuildAddonDocsTree() { ; Add any addon's documentation folders to a node in the help topics treeview.
	global helpTopicsTV, addonsFolder, addonDocsSubfolder

	addonFolders := []
	loop Files addonsFolder "\*", "D"
		addonFolders.Push(A_LoopFileName)
	qualifying := [] ; Only addons that actually have a docs folder will be added to this array.
	for _, addonFolder in SortedArray(addonFolders)
		if DirExist(addonsFolder "\" addonFolder "\" addonDocsSubfolder)
			qualifying.Push(addonFolder)
		if !qualifying.Length
			return

	umbrellaID := helpTopicsTV.Add(T("addon_docs_category"), 0)
	for _, addonFolder in qualifying {
		addonNodeID := helpTopicsTV.Add(_ResolveAddonDisplayName(addonFolder), umbrellaID)
		if !BuildDocsTreeLevel(addonsFolder "\" addonFolder "\" addonDocsSubfolder, addonNodeID)
			helpTopicsTV.Delete(addonNodeID) ; Docs folder without topics.
	}
	if !helpTopicsTV.GetChild(umbrellaID) ; Every addon docs folder was empty.
		helpTopicsTV.Delete(umbrellaID)
}

HelpViewerImageMaxWidth() { ; Widest a picture may be, in twips (1440 per inch): the content pane at its narrowest, minus margins and the scrollbar.
	global helpViewerMinWidth, helpViewerTreeWidth, helpViewerMargin
	contentPx := helpViewerMinWidth - helpViewerTreeWidth - (helpViewerMargin * 3)
	return Floor((contentPx - 45) * 1440 / 96) ; Gui sizes are DPI-scaled (96 dpi units), so divide by 96, not A_ScreenDPI.
}

OpenDocFile(file) { ; Load a markdown file's contents and hand them to the renderer.
	global docsFolder, helpTopicRE
	fileName := (SubStr(file, 2, 1) = ":") ? file : docsFolder . "\" . file
	if !FileExist(fileName) {
		Log("Help topic file not found: " fileName, "WARN", "OpenDocFile")
		return
	}
	try {
		content := FileRead(fileName, "UTF-8")
	} catch as Err {
		Log("Could not read help topic '" fileName "': " Err.Message, "WARN", "OpenDocFile")
		return
	}

SplitPath(fileName, , &docDir)
	imageOpts := {baseDir: docDir ; ![](images/x.png) is relative to the topic's own folder
		, imageDirs: [docDir "\images", docsFolder "\images"] ; a bare ![[x.png]] is also looked for here
		, maxWidth: HelpViewerImageMaxWidth()
		, warn: (msg) => Log(msg, "WARN", "OpenDocFile")} ; images that can't be shown are logged
	helpTopicRE.SetText(MarkdownToRTF(content, false, imageOpts)) ; Send the converted text to the RichEdit control.
	helpTopicRE.AutoURL(True) ; Detect and properly format URLs.
}

;-- Event handlers ---------------------------------------------------------------
HelpTopicLinkClicked(Ctrl, L) { ; Make clicked links actually open a webpage.
	; OnNotify's first arg (Ctrl) is the raw Gui.Custom control, not the RichEdit wrapper.
	; For GetTextRange to work, it has to be called with helpTopicRE instead.
	global helpTopicRE
	if (NumGet(L, A_PtrSize * 3, "Int") != 0x0202) ; WM_LBUTTONUP
		return
	cpMin := NumGet(L, (A_PtrSize * 5) + 4, "Int")
	cpMax := NumGet(L, (A_PtrSize * 5) + 8, "Int")
	Run(helpTopicRE.GetTextRange(cpMin, cpMax))
}

HelpViewerGuiClose(*) { ; Things to do when GUI is closed.
	global helpViewerHwnd
	HelpViewerGui.Destroy()
	helpViewerHwnd := ""
}

HelpViewerGuiEscape(*) { ; Exit the gui when Esc is pressed.
	global helpViewerHwnd
	HelpViewerGui.Destroy()
	helpViewerHwnd := ""
}