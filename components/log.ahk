
;				=========================================================================
;				|||||						KeyBird - Logging						|||||
;				=========================================================================

;## Setup #######################################################################
global logFile			:= A_WorkingDir "\userprofile\keybird.log"
global logMaxSizeBytes	:= 1024 * 1024 ; 1 MB. Past this, the log rotates instead of growing forever.
global warnShownThisSession := FALSE ; Tracks whether a WARN-level MsgBox has already been shown this run.

;## Core logging function #######################################################
Log(message, level := "ERROR", source := "") {
	; level: "INFO", "WARN", "ERROR", "FATAL"
	; source: optional context, e.g. an addon name or function name.
	global logFile, logMaxSizeBytes, warnShownThisSession

	timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
	sourceTag := source != "" ? " [" source "]" : ""
	line := timestamp " | " level sourceTag " | " message "`n"

	; Writing to the log must never itself throw and break the caller's error handling.
	writeSucceeded := true
	try {
		LogRotateIfNeeded()
		FileAppend line, logFile
	} catch {
		; If the drive is gone, the userprofile folder doesn't exist, or the file is locked,
		; fall back to OutputDebug so a debugger can still see it, and don't claim a log file exists.
		writeSucceeded := false
		try OutputDebug("KeyBird log write failed: " line)
	}
	logFootnote := writeSucceeded ? "`nLog file: " logFile : "`n(Could not write to the log file for this message.)"

	; Decide whether the user needs to see something right now.
	switch level {
		case "WARN":
			if !warnShownThisSession {
				warnShownThisSession := TRUE
				MsgBox(message (source != "" ? "`n`nSource: " source : "") "`n`nFurther warnings this session will be written to the log only." logFootnote,
					programinfo.name " — Warning", "48")
			}
		case "ERROR":
			MsgBox(message (source != "" ? "`n`nSource: " source : "") logFootnote,
				programinfo.name " — Error", "16")
		case "FATAL":
			MsgBox(message (source != "" ? "`n`nSource: " source : "") "`n`nKeyBird will now exit." logFootnote,
				programinfo.name " — Fatal Error", "16")
			ExitApp
	}
}

;## Rotation ######################################################################
LogRotateIfNeeded(*) {
	global logFile, logMaxSizeBytes
	if !FileExist(logFile)
		return
	if FileGetSize(logFile) < logMaxSizeBytes
		return
	oldLogFile := logFile ".old"
	try {
		if FileExist(oldLogFile)
			FileDelete oldLogFile
		FileMove logFile, oldLogFile, 1
	} catch {
		; If rotation itself fails (e.g. file locked), just let the current log keep growing rather than losing logs entirely.
	}
}

;## Convenience wrappers #########################################################
LogInfo(message, source := "")  => Log(message, "INFO", source)
LogWarn(message, source := "")  => Log(message, "WARN", source)
LogError(message, source := "") => Log(message, "ERROR", source)
LogFatal(message, source := "") => Log(message, "FATAL", source)

;## Viewing the log ##############################################################
OpenLogFile(*) {
	global logFile
	if !FileExist(logFile) {
		MsgBox "No log file exists yet. Nothing has been logged this session.", programinfo.name, "64"
		return
	}
	try Run(logFile)
	catch as Err
		MsgBox "Could not open the log file: " Err.Message "`nPath: " logFile, programinfo.name " — Error", "16"
}
