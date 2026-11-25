#Requires AutoHotkey v2.0

;		=========================================================================
;		|||||			RichEdit - IRichEditOleCallback (pictures)				|||||
;		=========================================================================
; A RichEdit control only keeps a picture that arrives inside an RTF stream
; ({\pict\pngblip ...}) if its host supplies an IRichEditOleCallback whose
; GetNewStorage() hands the control somewhere to store the picture. Without one,
; the control reserves the space for the picture and then draws nothing - no
; error, just a blank gap.
;
; RichEdit_EnableImages(RE) installs a minimal callback on a RichEdit object
; (lib\RichEdit.ahk). Call it once, right after creating the control and before
; the first SetText(). It returns true if the control accepted the callback.
;
; The callback is deliberately minimal: it provides storage and politely declines
; everything else (no in-place activation, no drag and drop, default context menu).
; One COM object is shared by all controls.
;
; Interface order (richole.h), after the three IUnknown methods:
;   GetNewStorage, GetInPlaceContext, ShowContainerUI, QueryInsertObject, DeleteObject,
;   QueryAcceptData, ContextSensitiveHelp, GetClipboardData, GetDragDropEffect, GetContextMenu

RichEdit_EnableImages(RE) {
	static vtbl := 0, obj := 0, handles := []
	if !obj {
		; [function, parameter count including "this"]
		table := [[REOle_QueryInterface, 3], [REOle_AddRef, 1], [REOle_Release, 1]
			, [REOle_GetNewStorage, 2], [REOle_GetInPlaceContext, 4], [REOle_ShowContainerUI, 2]
			, [REOle_QueryInsertObject, 4], [REOle_DeleteObject, 2], [REOle_QueryAcceptData, 6]
			, [REOle_ContextSensitiveHelp, 2], [REOle_GetClipboardData, 4], [REOle_GetDragDropEffect, 4]
			, [REOle_GetContextMenu, 5]]
		vtbl := Buffer(A_PtrSize * table.Length, 0)
		for i, entry in table {
			cb := CallbackCreate(entry[1], "F", entry[2])
			handles.Push(cb)	; keep them alive for the life of the script
			NumPut("Ptr", cb, vtbl, (i - 1) * A_PtrSize)
		}
		obj := Buffer(A_PtrSize, 0)
		NumPut("Ptr", vtbl.Ptr, obj)
	}
	; EM_SETOLECALLBACK = 0x0446
	return SendMessage(0x0446, 0, obj.Ptr, RE.HWND) != 0
}

REOle_QueryInterface(this, riid, ppv) {
	; IID_IUnknown {00000000-0000-0000-C000-000000000046} or IID_IRichEditOleCallback {00020D03-0000-0000-C000-000000000046}
	a := NumGet(riid, 0, "Int64")
	b := NumGet(riid, 8, "Int64")
	if (b = 0x46000000000000C0 && (a = 0 || a = 0x20D03)) {
		NumPut("Ptr", this, ppv)
		return 0
	}
	NumPut("Ptr", 0, ppv)
	return 0x80004002	; E_NOINTERFACE
}

REOle_AddRef(this) {
	return 1	; the object lives as long as the script
}

REOle_Release(this) {
	return 1
}

REOle_GetNewStorage(this, ppstg) {	; the one method that matters: storage for a picture / object
	NumPut("Ptr", 0, ppstg)
	try {
		lockBytes := 0
		hr := DllCall("ole32\CreateILockBytesOnHGlobal", "Ptr", 0, "Int", 1, "Ptr*", &lockBytes, "UInt")
		if (hr != 0)
			return hr
		stg := 0
		; STGM_READWRITE | STGM_SHARE_EXCLUSIVE | STGM_CREATE
		hr := DllCall("ole32\StgCreateDocfileOnILockBytes", "Ptr", lockBytes, "UInt", 0x1012, "UInt", 0, "Ptr*", &stg, "UInt")
		ObjRelease(lockBytes)
		if (hr != 0)
			return hr
		NumPut("Ptr", stg, ppstg)
		return 0
	} catch {
		return 0x80004005	; E_FAIL
	}
}

REOle_GetInPlaceContext(this, ppFrame, ppDoc, pFrameInfo) {
	return 0x80004001	; E_NOTIMPL
}

REOle_ShowContainerUI(this, fShow) {
	return 0x80004001
}

REOle_QueryInsertObject(this, pclsid, pstg, cp) {
	return 0	; S_OK: allow
}

REOle_DeleteObject(this, poleobj) {
	return 0
}

REOle_QueryAcceptData(this, pdataobj, pcfFormat, reco, fReally, hMetaPict) {
	return 0x80004001	; E_NOTIMPL: let the control use its default handling
}

REOle_ContextSensitiveHelp(this, fEnterMode) {
	return 0
}

REOle_GetClipboardData(this, pchrg, reco, ppdataobj) {
	return 0x80004001
}

REOle_GetDragDropEffect(this, fDrag, grfKeyState, pdwEffect) {
	return 0x80004001
}

REOle_GetContextMenu(this, seltype, poleobj, pchrg, phmenu) {
	return 0x80004001
}
