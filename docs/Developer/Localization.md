- **Translation timing, if you're wondering why `pluginKey` exists at all:**
`Plugin_AddMainMenuItem` is normally called from an addon's `static __New()`,
which runs before `PluginBase.LoadLanguage()` has loaded any strings. Calling
`this.T()` directly at that point would freeze on the untranslated fallback
forever. Passing `pluginKey` instead defers the actual lookup to
`BuildMainMenuItems()`, which runs later — safely after `LoadLanguage()` — so
the label is resolved fresh, every time the menu is (re)built, against
whatever language is active. The same fix, for the same reason, was already
applied to tab names (`Plugin_Main_AddTab`'s `pluginKey` param;
`_ResolveTabName()` in hooks.ahk) — `_ResolveMenuItemName()` in hooks.ahk is
the menu-item equivalent.

; Key naming rules:
;   - Section  = plugin key (matches the static PluginKey property on the class)
;               OR "core" for strings owned by Keybird itself.
;               OR "meta" for file-level metadata (not used as UI strings).
;   - Key name = short snake_case label for the string.
;   - Never put display strings in code. Every user-visible string lives here.
;
; Fallback chain:  lang\<active>.ini  →  lang\en.ini  →  key itself
; The key-itself fallback is intentionally ugly so missing keys are visible
; during development. A partial translation only needs to cover the strings
; that differ from English — missing keys fall back to English automatically.


; -------------------------------------------------------------------------------
; File metadata (not surfaced as UI strings)
; -------------------------------------------------------------------------------
[meta]
display_name        = English (United States)