# Menus
> **Rationale**
> AHK identifies menu items by their current display text. For example, `A_TrayMenu.ToggleCheck("foo")` will only work if the item's label is still exactly `"foo"` at the moment you call it.
> It's still OK if the menu value won't be changed, and Keybird will still work with it. However, if the name is modified, such as with `T()`/`this.T()` (see Localization), the value changes with the active language, and any code that checks for static names won't work.
> Using these menu helper functions also solves a potential need for hot-swapping languages (which isn't something Keybird natively does at the moment), or dynamically-changing menu text.

**MenuAdd**
- Adds a menu item and remembers the exact label you gave it, filed under a stable key you choose.
Syntax:
```
MenuAdd(menuObj, itemKey, displayText, callback, options := "")
```
Parameters:
- **menuObj**: The `Menu` object to add to (e.g. `A_TrayMenu`, `AddonsMenu`, or any submenu you've created).
- **itemKey**: A string that will work as a unique ID for you menu. Scoped per-`menuObj` internally, so different menus can reuse the same key without conflicting.
- **displayText**: Same as `Menu.Add()`'s first parameter, but supports dynamically-changing text, such as translation (e.g. `T("...")` or `this.T("...")`).
- **callback**: Same as `Menu.Add()`'s second parameter.
- **options**: Same as `Menu.Add()`'s third parameter (e.g. `"Check"` to start checked). Optional.

**MenuLabel**
- Resolves a key back to the item's *current* label, so you never have to re-derive it yourself.
Syntax:
```
MenuLabel(menuObj, itemKey)
```
Parameters:
- **menuObj**: Returns the label most recently passed to `MenuAdd()` for that `(menuObj, itemKey)` pair.
- **itemKey**: See `MenuAdd`. This is the unique ID string you previously chose for your menu. In case of error, returns `""` and logs a `WARN` if the key was never registered.

---

**Explanation and examples**:
**When to use `MenuAdd()` and `MenuLabel` vs. AutoHotKey's `Menu.Add()`**
	- Translatable items that will need to be referenced (e.g. checkable items, the menu's `Default`, elements that will change status, like `Enable`/`Disable`/`Rename`/`Delete`).
	- Simple menu entries (e.g. just run a function and don't need translation) can be added using `Menu.Add()` directly. `MenuAdd()` is not obligatory.
**Example**:
```ahk
; When building the menu:
MenuAdd(AddonsMenu, "myaddon_notify", this.T("menu_toggle_notifications"), ObjBindMethod(this, "ToggleNotify"), "Check")

; Later, anywhere, once the menu exists:
static ToggleNotify(*) {
this.notifyEnabled := !this.notifyEnabled
AddonsMenu.ToggleCheck(MenuLabel(AddonsMenu, "myaddon_notify"))
}
```

**Usage with `Plugin_AddMainMenuItem`**
If your addon is inserting a new entry in the Main menu, you can still translate and reference it.
`MenuLabel`'s first parameter (`menuObj`) will need to be "`AddonsMenu`". (e.g. `MenuLabel("AddonsMenu", "your_itemkey")`).