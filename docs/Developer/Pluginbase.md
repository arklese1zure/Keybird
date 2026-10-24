# Developer documentation
## Index
| **Topic**       | **Section**	 |
| --------------- | ------------ |
| Addons    | [Addons](#Addons)     |
| Preface | Prominente   |
| Basic structure         | Ausentes     |
| Pluginbase        | Ausente      |
| Helper functions    | Ausente      |
| Localization         | [Translation](##Translation) |

# PluginBase Class Reference

`PluginBase` is the base class all Keybird addons should extend. It provides safe file I/O, INI settings helpers, and translation support so addon authors don't have to reimplement them from scratch.

All methods are **static** — addons are singletons, not instances. You never call `new MyAddon()`.

---

## Minimal addon skeleton

```ahk
class PluginMyAddon extends PluginBase {
    static PluginKey    := "myaddon"
    static settingsFile := A_WorkingDir "\userprofile\myaddon.ini"

    static BuildTab() {
        ; Add GUI controls here.
        ; this.T("my_string") looks up [myaddon] my_string in the lang file.
    }

    static SaveSettings(*) {
        this.SaveSetting("State", "last_value", myControl.Value)
    }
}
```

Two static properties must be defined by the subclass:

- **`PluginKey`** — a short, stable, snake_case identifier. Must match the section name in your lang file. Required if you use `this.T()`. Never change it after release; it is the key that maps your class to your strings and settings.
- **`settingsFile`** — full path to your addon's INI file. Required if you use `GetSetting()` or `SaveSetting()`.

Neither property is required if you don't use the corresponding feature, but omitting `PluginKey` means `this.T()` will only find `core.*` strings.

---

## Translation

### How strings are loaded

`PluginBase.LoadLanguage()` is called once at startup by the host script. Addons never call it themselves. It loads strings into `PluginBase.Strings`, a flat `Map` with `"section.key"` keys. After that, `T()` and `this.T()` are O(1) lookups — no file I/O at call time.

The load is a two-pass merge:

1. `lang\en.ini` is always loaded first as the base.
2. If a non-English language is active, its file is loaded and overlaid on top — any key present in both takes the translated value; missing keys silently remain English.

This means a partial translation is safe. You only need to cover the strings that differ from English.

### `this.T(key, fallback := "")`

Looks up a translated string. The lookup order is:

1. `<PluginKey>.<key>` — your plugin's own string.
2. `core.<key>` — a shared Keybird string (ok, cancel, save, delete, etc.).
3. `fallback` if supplied, otherwise the raw `key` itself.

The raw-key fallback is intentionally visible — if you see a bare key name in the UI, it means the string is missing from `en.ini` and needs to be added.

```ahk
; In a class that has PluginKey := "snippets":
myButton.Text := this.T("new_snippet")      ; → [snippets] new_snippet
okButton.Text := this.T("ok")               ; → [core] ok
label.Text    := this.T("missing_key")      ; → "missing_key"  (visible bug signal)
label.Text    := this.T("missing", "—")     ; → "—"  (silent fallback for optional strings)
```

### Global `T(key, fallback := "")`

A thin wrapper around `PluginBase.T()` usable from anywhere — host scripts, menus, procedural code — without needing a class reference. Because it has no `PluginKey` context, it only reaches `core.*` strings. Use `this.T()` inside a class for plugin-scoped strings.

```ahk
; In procedural host code (menus.ahk, hooks.ahk, etc.):
myMenu.Add(T("settings"), LaunchSettings)
myMenu.Add(T("exit"), GUIExit)
```

### Framework-resolved keys

Most of your lang file is keys you invented and look up yourself via `this.T("my_key")`. A
small handful of keys are different: you still have to define them in your lang file, but you
never call `this.T()` for them yourself — the framework resolves them for you, at the exact
moment it needs to display something, using your `PluginKey`.

| Key | Looked up as | Resolved by | When it runs |
|---|---|---|---|
| `tab_name` | `<PluginKey>.tab_name` | `_ResolveTabName()` (hooks.ahk) | Every `BuildAddonTabs()` call, for tabs registered via `Plugin_Main_AddTab(..., pluginKey)` |
| `menu_item_name` | `<PluginKey>.menu_item_name` | `_ResolveMenuItemName()` (hooks.ahk) | Every `BuildMainMenuItems()` call, for entries registered via `Plugin_AddMainMenuItem(..., pluginKey)` |
| `settings_tab_name` | `<PluginKey>.settings_tab_name` | **Not automatic** — call `this.T("settings_tab_name")` yourself inside `BuildSettingsTab()` | Whenever your settings tab builds |

`tab_name` and `menu_item_name` are resolved automatically because the framework itself owns the
moment the tab/menu item actually gets built (`BuildAddonTabs()`, `BuildMainMenuItems()`) — it
already knows exactly when `PluginBase.Strings` is safely populated, so it can translate on your
behalf without you needing to think about load order at all. `settings_tab_name` isn't automatic
because your addon's `Plugin_Settings_AddTab` callback builds its own tab contents directly —
there's no equivalent framework-owned build step to hook the lookup into, so you call `this.T()`
yourself, same as any other string in your addon.

Why this matters in practice: `Plugin_Main_AddTab` and `Plugin_AddMainMenuItem` are typically
called from your addon's `static __New()`, which runs *before* `PluginBase.LoadLanguage()` has
loaded any strings. If you called `this.T()` right there to compute a tab name or menu label,
it would freeze on the untranslated fallback (or the raw key) forever, no matter what language
is actually active — `PluginBase.Strings` is still an empty `Map()` at that point. Passing
`pluginKey` instead defers the actual string lookup to build time, which happens safely after
`LoadLanguage()`. This is why both hooks accept a `pluginKey` parameter: it's not just an
identifier, it's what lets the translated label be resolved fresh, every time the tab/menu is
rebuilt, instead of being captured once during registration and locked in.

Both keys require passing `pluginKey` to the registration call. Without it, there's no key to
look up and the framework falls back to whatever fallback string you supplied as `tabName` /
`entryName` — safe, but permanently unlocalized for that tab or menu item.

```ini
; addons\myaddon\lang\en.ini
[myaddon]
tab_name          = My Addon
menu_item_name    = Open My Addon
settings_tab_name = My Addon
```

Nothing stops a future framework feature from adding another resolved key in the same style —
if you add one, document it in this table so the convention stays discoverable in one place
rather than scattered across hook comments.

### Lang file structure

Your addon ships a `lang\` subfolder inside its own folder:

```
addons\
  myaddon\
    myaddon.ahk
    lang\
      en.ini       ← required
      es.ini       ← optional
```

Each file has one section named after your `PluginKey`:

```ini
[myaddon]
my_string   = My label
other_label = Another label
```

A translation file only needs to include the keys that differ from English. Missing keys fall back to English automatically.

---

## File helpers

All file helpers check drive accessibility before writing and log errors rather than throwing. They return `true` on success and `false` on failure, so callers can check the result if needed.

### `this.SaveFile(path, content)`

Writes `content` to `path` using a temp-file-then-rename pattern. Keeps a `.bak` of the previous version. Use this for any file that gets fully rewritten (e.g. saving a list of items, replacing a config file).

```ahk
this.SaveFile(this.dataFile, serializedContent)
```

- Writes to `path.tmp` first.
- Copies the current `path` to `path.bak` before replacing it.
- Moves `path.tmp` to `path` atomically.
- Deletes the temp file and returns `false` on any failure.

### `this.AppendToFile(path, line)`

Appends a single line to a file without rewriting the whole thing. Useful when adding one record to a log or one hotstring to a file.

```ahk
this.AppendToFile(this.logFile, timestamp . "`t" . entry . "`n")
```

### `this.EnsureFolder(path)`

Creates the folder at `path` if it doesn't already exist. Returns `true` if the folder is ready to use (whether it was just created or already existed). Returns `false` and logs on failure.

```ahk
; Typical use in __New or a static initializer:
this.EnsureFolder(A_WorkingDir "\userstorage\myaddon")
```

### `this.EnsureFile(path, defaultContent := "")`

Creates the file at `path` if it doesn't exist, writing `defaultContent` into it. Also calls `EnsureFolder()` on the parent directory first, so you don't need to call both manually. Returns `true` if the file is ready to use.

```ahk
this.EnsureFile(this.settingsFile, "[State]`nfirst_run=1`n")
```

---

## Settings helpers

Both helpers read and write from `this.settingsFile`. If the subclass hasn't defined `settingsFile`, they log a warning and return a safe value rather than crashing.

### `this.GetSetting(section, key, default := "")`

Reads one value from the addon's INI file. Returns `default` if the file, section, or key doesn't exist. Never throws.

```ahk
lastSort := this.GetSetting("State", "last_sort", "asc")
maxItems := this.GetSetting("Options", "max_items", 50)
```

### `this.SaveSetting(section, key, value)`

Writes one value to the addon's INI file. Returns `true` on success, `false` on failure (also logs the error). Checks drive accessibility before writing.

```ahk
this.SaveSetting("State", "last_sort", "desc")
this.SaveSetting("Options", "max_items", mySpinner.Value)
```

---

## What PluginBase does not cover

These are intentionally outside PluginBase's scope:

- **Hook registration** — use the `Plugin_*` functions in `hooks.ahk` (`Plugin_Main_AddTab`, `Plugin_Main_OnStartUp`, etc.).
- **GUI construction** — build controls directly against `mainGui` or `SettingsGui` inside your hook callbacks.
- **Drive accessibility** — the underlying `IsWorkingDirAccessible()` check used by file/settings helpers is a host-level function, not part of the class. You can call it directly if you need it before calling a PluginBase method.
