# Main menu
`Plugin_AddMainMenuItem` 
- Adds an entry to the main menu, with an assigned name and function.
Syntax:
```
Plugin_AddMainMenuItem(fn, entryName := "", pluginKey := "")
```
Parameters:
- **fn**: Name of the function that the menu entry will run.
- **entryName**: String with the entry's name. If you don't want a translation file, leave it blank (""). If you supply a translation and add text here, it'll work as a fallback.
- **pluginKey**: Unique identifier for you addon. Required if you want the entry's label translated (see `PluginBase > menu_item_name`).

