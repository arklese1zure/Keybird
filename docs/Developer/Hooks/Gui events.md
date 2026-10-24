# Gui events
`Plugin_Main_LeftClick`
- Triggers an action when a GUI is left-clicked. This is monitored with `OnMessage 0x0201`.
- Each time a gui belonging to this script is left-clicked, the HWND for that gui is updated in the `leftclickguihwnd` global variable.
Syntax:
```
Plugin_Main_LeftClick(fn)
```
Parameters:
- **fn**: The name of the function you want to run.

`Plugin_Main_RightClick`
- Triggers an action when a GUI is right-clicked. This is monitored with OnMessage 0x204.
- Each time a gui belonging to this script is clicked, the HWND for that gui is updated in the leftclickguihwnd global variable.
Syntax:
```
Plugin_Main_RightClick(fn)
```
Parameters:
- **fn**: The name of the function you want to run.