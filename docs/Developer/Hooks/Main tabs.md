# Main Gui tabs
`Plugin_Main_AddTab`
- Add a tab to the main Gui and assign a name, icon and optional functions.
Syntax:
```
Plugin_Main_AddTab(fn, [tabName, tabIcon, leftclickfn, rightclickfn, pluginKey])
```
Parameters:
- **fn**: The name of the function you want to run.
- **tabName**: The name of the tab you'll be adding. There's two ways to use this:
	a) You can use it on its own if you don't want to supply a translation file. (See Localization.md).
	b) If you localize your addon, leave it blank (""). If you still add this, it'll work as a fallback.
- **tabIcon**: Path of any custom icon you want for your tab.
- **onSelectFn** (optional): Trigger a function when left-clicking the tab's icon.
- **onRightClickFn** (optional): Trigger a function when right-clicking the tab's icon.
- **pluginKey**: Unique identifier for you addon. Required by `leftclickfn` and `rightclickfn`.