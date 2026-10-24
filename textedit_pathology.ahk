;#########DESCRIPTION#######################################################################
; This module provides a gui for editing case by case, outputting to the clipboard and to files
; as well as having a small file manager for organizing cases and attachments.

;#########MENUS#############################################################################
TextEditorMenu := Menu() ;==File viewer ListView context menu===============================

;#########GUI CONTENTS######################################################################
BuildGui()
myGui.Show()
BuildGui(*)
{	
	global myGui := Gui()
	myGui.OnEvent("Close", GuiClose)
	myGui.OnEvent("DropFiles", GuiDropFiles)
	myGui.Opt("+OwnDialogs")
	SB := myGui.Add("StatusBar", , "Status Bar")
	TreeView := myGui.Add("TreeView", "x8 y38 w217 h421")
	myGui.Add("GroupBox", "x232 y32 w851 h58", "Datos del caso")
	DropDownList1 := myGui.Add("DropDownList", "x296 y56 w41 +Sort +Uppercase", ["DropDownList", "", ""])
	Edit1 := myGui.Add("Edit", "x344 y56 w65 h21 +Number")
	Edit2 := myGui.Add("Edit", "x416 y56 w25 h21")
	DateTime1 := myGui.Add("DateTime", "x528 y56 w100 h24")
	myGui.Add("Text", "x240 y56 w48 h23 +0x200", "ID Caso")
	myGui.Add("Text", "x472 y56 w48 h23 +0x200", "Fecha")
	myGui.Add("Text", "x456 y59 w2 h15 +0x1 +0x10")
	myGui.Add("GroupBox", "x232 y96 w849 h180", "Descripción macroscópica")
	myGui.Add("GroupBox", "x232 y280 w848 h180", "Descripción microscópica")
	myGui.Add("GroupBox", "x232 y464 w849 h208", "Diagnóstico")
	Edit3 := myGui.Add("Edit", "x232 y112 w848 h162")
	Edit4 := myGui.Add("Edit", "x232 y296 w848 h162")
	Edit5 := myGui.Add("Edit", "x232 y480 w848 h193")
	myGui.Add("GroupBox", "x8 y464 w217 h209", "Anexos")
	ListViewhLVItems := myGui.Add("ListView", "x8 y480 w216 h192 +Grid +LV0x4000 +LV0x10000 +Sort", ["ListView"])
	ListViewhLVItems.Add(,"Sample1")
	ListViewhLVItems.OnEvent("DoubleClick", LV_DoubleClick)
	DropDownList1.OnEvent("Change", OnEventHandler)
	Edit1.OnEvent("Change", OnEventHandler)
	Edit2.OnEvent("Change", OnEventHandler)
	DateTime1.OnEvent("Change", OnEventHandler)
	Edit3.OnEvent("Change", OnEventHandler)
	Edit4.OnEvent("Change", OnEventHandler)
	Edit5.OnEvent("Change", OnEventHandler)
	myGui.OnEvent('Close', (*) => ExitApp())
	myGui.Title := "Window"
	
LV_DoubleClick(LV, RowNum)
{
	if not RowNum
		return
	ToolTip("Test")
	SetTimer () => ToolTip(), -3000
}
hToolbar := CreateToolbar()

OnEventHandler(*) {
	ToolTip("Test")
	SetTimer () => ToolTip(), -3000
}

GuiDropFiles(thisGui, Ctrl, FileArray, *){
	ToolTip "Test"
	SetTimer () => ToolTip(), -500
	return
}

GuiClose(*) {
	ExitApp()
	}

CreateToolbar() {
	    ImageList := IL_Create(13)
	    IL_Add(ImageList, "shell32.dll", 1)
	    IL_Add(ImageList, "shell32.dll", 4)
	    IL_Add(ImageList, "shell32.dll", 235)
	    IL_Add(ImageList, "shell32.dll", 259)
	    IL_Add(ImageList, "shell32.dll", 296)
	    IL_Add(ImageList, "imageres.dll", 51)
	    IL_Add(ImageList, "shell32.dll", 55)
	    IL_Add(ImageList, "shell32.dll", 260)
	    IL_Add(ImageList, "shell32.dll", 134)
	    IL_Add(ImageList, "imageres.dll", 95)
	    Buttons := "
	    (LTrim
	        Nuevo
	        Abrir
	        Cerrar
	        -
	        Guardar
	        Descartar cambios
	        Eliminar
	        -
	        Copiar
	        Cortar
	        Seleccionar todo
	        -
	        Ayuda
	    )"
	    Return ;CreateToolbar("OnToolbar", Buttons, ImageList, "Flat List Tooltips Border")
	}
	OnToolbar(hWnd, Event, Text, Pos, Id) {
	    If (Event != "Click") {
	        Return
	    }
	    If (Text == "Nuevo") {
	    } Else If (Text == "Abrir") {
	    } Else If (Text == "Cerrar") {
	    } Else If (Text == "Guardar") {
	    } Else If (Text == "Descartar cambios") {
	    } Else If (Text == "Eliminar") {
	    } Else If (Text == "Copiar") {
	    } Else If (Text == "Cortar") {
	    } Else If (Text == "Seleccionar todo") {
	    } Else If (Text == "Ayuda") {
	    }
	}
	
	return myGui
}