;		=========================================================================
;		|||||					KeyBird — Plugin Base Class					|||||
;		=========================================================================
;
;	Addon classes should extend this class to get safe file I/O, settings
;	helpers, and translation support without reimplementing them from scratch.
;
;	Usage in an addon:
;
;		class PluginToDo extends PluginBase {
;			static PluginKey    := "todo"           ; stable key, matches lang\en_us.ini section
;			static settingsFile := A_WorkingDir "\userprofile\todo.ini"
;			...
;			static SaveTodo(*) {
;				this.SaveFile(this.todoFile, content)
;				this.SaveSetting("State", "last_sort", "asc")
;			}
;			static BuildTabContents() {
;				myMenu.Add(this.T("new_item"), ...)  ; looks up [todo] new_item in the lang file
;			}
;		}
;
;	All methods are static — addons are singletons, not instances.
;	settingsFile must be defined by the subclass if GetSetting/SaveSetting are used.
;	PluginKey must be defined by the subclass if T() is used.

class PluginBase {

	;## Translation ##################################################################
	;
	;	PluginBase.Strings holds the active language map, populated once at startup
	;	by LoadLanguage(). Addons never call LoadLanguage() themselves.
	;
	;	Lookup order for this.T("key"):
	;	  1. "<PluginKey>.<key>"  — plugin-scoped string         e.g. "snippets.new_snippet"
	;	  2. "core.<key>"         — shared string                 e.g. "core.ok"
	;	  3. The key itself       — visible fallback for dev/debug e.g. "new_snippet"
	;
	;	A missing key is intentionally ugly (shows the raw key name) so that
	;	translation gaps are caught during development rather than silently swallowed.

	static Strings := Map() ; Populated by LoadLanguage(). Keys are "section.key".

	static LoadLanguage(langCode := "en_us") {
	; Build the string map in three passes:
	;   1. lang\en_us.ini            — core English base
	;   2. addons\*\lang\en_us.ini   — each addon's English strings (Option B)
	;   3. If langCode != "en":
	;      lang\<code>.ini        — core overlay
	;      addons\*\lang\<code>.ini — each addon's overlay
	;
	; This means a partial translation only needs to cover strings that differ
	; from English. Missing keys silently fall back to English automatically.
	; The raw-key fallback in T() is reserved for strings absent from en_us.ini
	; entirely, which is always a bug in the lang file rather than a gap in a
	; translation.
	;
	; Safe to call multiple times — each call replaces the previous map.
		coreLangDir := A_WorkingDir "\lang"
		baseFile    := coreLangDir "\en_us.ini"
		if !FileExist(baseFile) {
			Log("Base language file not found: " baseFile " — UI strings will show raw keys.", "WARN", "PluginBase")
			return
		}

		; Pass 1: core English base.
		merged := PluginBase._ParseLangFile(baseFile)
		if !IsObject(merged)
			return
		Log("Loaded " merged.Count " strings from '" baseFile "'.", "INFO", "PluginBase")

		; Pass 2: each addon's English strings, merged on top of core.
		merged := PluginBase._MergeAddonLang(merged, "en_us")

		; Pass 3: if a non-English language was requested, overlay both
		;         the core translation and each addon's translation on top.
		if langCode != "en_us" {
			coreOverlay := coreLangDir "\" langCode ".ini"
			if !FileExist(coreOverlay) {
				Log("Language file not found for '" langCode "', using English only.", "WARN", "PluginBase")
			} else {
				overlay := PluginBase._ParseLangFile(coreOverlay)
				if IsObject(overlay) {
					for k, v in overlay
						merged[k] := v
					Log("Overlaid " overlay.Count " strings from '" coreOverlay "'.", "INFO", "PluginBase")
				}
			}
			merged := PluginBase._MergeAddonLang(merged, langCode)
		}

		PluginBase.Strings := merged
	}

	static _MergeAddonLang(base, langCode) {
	; Scan every addons\*\lang\<langCode>.ini and merge its strings into base.
	; Returns the merged map. Missing files are silently skipped.
	; A missing lang file for an addon is normal (addon not translated yet).
		addonsDir := A_WorkingDir "\addons"
		if !DirExist(addonsDir)
			return base
		loop Files addonsDir "\*", "D" {
			addonLangFile := addonsDir "\" A_LoopFileName "\lang\" langCode ".ini"
			if !FileExist(addonLangFile)
				continue
			parsed := PluginBase._ParseLangFile(addonLangFile)
			if !IsObject(parsed)
				continue
			for k, v in parsed
				base[k] := v
			Log("Loaded " parsed.Count " strings from '" addonLangFile "'.", "INFO", "PluginBase")
		}
		return base
	}

	static _ParseLangFile(path) {
	; Read one INI language file into a flat Map with "section.key" keys.
	; Returns the Map on success, empty string "" on any failure.
		newMap := Map()
		try {
			sections := IniRead(path) ; Returns all section names, one per line.
			loop parse, sections, "`n", "`r" {
				section := Trim(A_LoopField)
				if section = ""
					continue
				pairs := IniRead(path, section) ; Returns "key=value`nkey=value…"
				loop parse, pairs, "`n", "`r" {
					pair := Trim(A_LoopField)
					if pair = ""
						continue
					eqPos := InStr(pair, "=")
					if !eqPos
						continue
					k := Trim(SubStr(pair, 1, eqPos - 1))
					v := Trim(SubStr(pair, eqPos + 1))
					newMap[section "." k] := v
				}
			}
		} catch as Err {
			Log("Failed to parse language file '" path "': " Err.Message, "ERROR", "PluginBase")
			return ""
		}
		return newMap
	}

	static T(key, fallback := "") {
	; Translate a key using the active language map.
	; Looks up "<PluginKey>.<key>", then "core.<key>", then returns fallback or key.
	;
	; Subclasses must define:  static PluginKey := "my_plugin"
	; If PluginKey is missing the plugin-scoped lookup is skipped gracefully.
		pluginScoped := ""
		if this.HasProp("PluginKey") && this.PluginKey != ""
			pluginScoped := this.PluginKey "." key
		if pluginScoped != "" && PluginBase.Strings.Has(pluginScoped)
			return PluginBase.Strings[pluginScoped]
		coreScoped := "core." key
		if PluginBase.Strings.Has(coreScoped)
			return PluginBase.Strings[coreScoped]
		; Visible fallback: use the caller-supplied default, or the raw key name.
		; The raw key is intentionally noticeable so missing strings get fixed.
		return (fallback != "") ? fallback : key
	}

	;## File helpers #################################################################

	static SaveFile(path, content) {
	; Write content to path safely using a temp file, then rename.
	; Keeps a .bak of the previous version. Logs on failure.
		if !IsWorkingDirAccessible() {
			Log("Drive not accessible, cannot save file: " path, "WARN", this.__Class)
			return false
		}
		tempFile   := path ".tmp"
		backupFile := path ".bak"
		try {
			if FileExist(tempFile)
				FileDelete tempFile
			FileAppend content, tempFile
			if !FileExist(tempFile) || (content != "" && FileGetSize(tempFile) = 0) ; Valid file with empty content (e.g. an emptied note).
				throw Error("Temp file is missing or empty after write.")
			if FileExist(path)
				FileCopy path, backupFile, 1
			FileMove tempFile, path, 1
			return true
		} catch as Err {
			Log("Failed to save file '" path "': " Err.Message, "ERROR", this.__Class)
			try FileDelete tempFile
			return false
		}
	}

	static AppendToFile(path, line) {
	; Append a single line to a file. Checks drive accessibility first.
	; For cases where rewriting the whole file is unnecessary (e.g. adding one hotstring).
		if !IsWorkingDirAccessible() {
			Log("Drive not accessible, cannot append to file: " path, "WARN", this.__Class)
			return false
		}
		try {
			FileAppend line, path
			return true
		} catch as Err {
			Log("Failed to append to file '" path "': " Err.Message, "ERROR", this.__Class)
			return false
		}
	}

	static EnsureFolder(path) { ; Create folder if it doesn't exist. Returns true on success or if already present.
		if DirExist(path)
			return true
		try {
			DirCreate path
			return true
		} catch as Err {
			Log("Could not create folder '" path "': " Err.Message, "ERROR", this.__Class)
			return false
		}
	}

	static EnsureFile(path, defaultContent := "") { ; Create file with defaultContent if it doesn't exist.
		if FileExist(path) ; Ensures the parent folder exists first.
			return true ; Returns true if the file is ready to use.
		parentFolder := SubStr(path, 1, InStr(path, "\",, -1) - 1) ; Make sure the parent folder exists before trying to write.
		if !this.EnsureFolder(parentFolder)
			return false
		try {
			FileAppend defaultContent, path
			return true
		} catch as Err {
			Log("Could not create file '" path "': " Err.Message, "ERROR", this.__Class)
			return false
		}
	}

	;## Settings helpers ############################################################
	;
	; These use this.settingsFile, which the subclass must define as a static property.
	; If settingsFile is not set, both methods log an error and return a safe value.

	static GetSetting(section, key, default := "") { ; Read a setting from the addon's own settings file.
	; Returns default if the file, section, or key doesn't exist — never throws.
		if !this.HasProp("settingsFile") || this.settingsFile = "" {
			Log("GetSetting called but settingsFile is not defined.", "WARN", this.__Class)
			return default
		}
		try {
			return IniRead(this.settingsFile, section, key, default)
		} catch as Err {
			Log("Could not read setting [" section "] " key ": " Err.Message, "WARN", this.__Class)
			return default
		}
	}

	static SaveSetting(section, key, value) { ; Write a setting to the addon's own settings file. Logs on failure.
		if !this.HasProp("settingsFile") || this.settingsFile = "" {
			Log("SaveSetting called but settingsFile is not defined.", "WARN", this.__Class)
			return false
		}
		if !IsWorkingDirAccessible() {
			Log("Drive not accessible, cannot save setting [" section "] " key, "WARN", this.__Class)
			return false
		}
		try {
			IniWrite value, this.settingsFile, section, key
			return true
		} catch as Err {
			Log("Could not save setting [" section "] " key ": " Err.Message, "ERROR", this.__Class)
			return false
		}
	}
}

;## Global translation function #################################################
;
;	T(key, fallback?) — thin wrapper around PluginBase.T() for use in procedural
;	host code (menus.ahk, settings.ahk, hooks.ahk, Keybird.ahk).
;
;	Plugin classes should use  this.T()  instead, which adds a plugin-scoped
;	lookup first. This global version only checks "core.<key>" and then falls
;	back to the raw key, so it is intentionally for host/core strings only.
;
;	Both signatures are identical so the call site never needs to know which
;	it's using:  T("ok")  works in both procedural code and inside a class.

T(key, fallback := "") {
	coreScoped := "core." key
	if PluginBase.Strings.Has(coreScoped)
		return PluginBase.Strings[coreScoped]
	return (fallback != "") ? fallback : key
}
