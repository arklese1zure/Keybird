<p align="center">
  <img src="docs/images/logo.svg" width="128" alt="Keybird logo">
</p>

<h1 align="center">Keybird</h1>

<p align="center">A small, modular AutoHotkey companion for day-to-day report writing.</p>

<p align="center">
  <img src="docs/images/main.png" alt="Keybird main window">
</p>

Keybird is a small, modular utility program that aims to aid the user in day-to-day report writing by providing text expansion, boilerplate text snippets and other tools via an extensible plugin interface.
The program leverages AutoHotkey's powerful automation scripting while providing an easily understandable and always-present interface.

## Functions
### Hotkey manager
Keybird and its addons can register hotkeys, which are keyboard key combinations that can be pressed to perform a variety of tasks. These are all listed in their respective settings panel, and can also be configured and turned on/off (see *settings* section).

### The main window
Keybird's main window (pictured above) consists of a simple, tabbed interface, with a menu bar.

> [!NOTE]
> **Special window properties**
>
> The main window can be configured to stay always on top, and to be transparent when not in focus. It can also be set to hide/unhide using a hotkey or another trigger, or it can be minimized to the taskbar if you prefer that method (see *settings* section).

#### Tab switcher
The tab switcher contains all functions that can be quickly accessed in the main window. Most of these are provided via addons, and have varied functions, such as a to-do list, a notepad, or other utilities.
The "tabs" (represented by the icons), can also be right-clicked for extra options and for performing quick tasks.
The tab switcher can be customized. You can add a background image in settings (see *settings* section).

### System tray
The system tray \[pending]

### System functions
#### Stay awake
A toggleable function that prevents the system from suspending or going to the lockscreen. This function can be triggered from the main menu, or from the system tray menu.

## Credits
### GUI functions
- [Keep gui over the taskbar](https://tinyurl.com/plankoe-did-this), by plankoe-did-this

### Libraries
- [RichEdit.ahk / RichEditDlgs.ahk](http://www.autohotkey.com/board/topic/17869-crichedit-standard-richedit-control-for-autohotkey-scripts/), by just me
	- HE_Print by [jballi](http://www.autohotkey.com/board/topic/45513-function-he-print-wysiwyg-print-for-the-hiedit-control/)
	- Dlg 5.01 by [majkinetor](http://www.autohotkey.com/board/topic/15836-module-dlg-501/)
	- Modified for Keybird: __Delete() garbage collection after gui destruction.
- [ListViewExtensions.ahk](https://www.autohotkey.com/boards/), by just me
	- GuiControl_Ex concept by [TheArkive](https://www.autohotkey.com/boards/viewtopic.php?f=83&t=86124)
	- Tile-view functions: idea by segalion, based on code by Fabio Lucarelli
- [GuiButtonIcon.ahk](https://www.autohotkey.com/boards/), by Fanatic Guru
- [String.ahk](https://github.com/Descolada/AHK-v2-libraries), by Descolada
	- Based in part on "String Things" by tidbit
	- Contributors: Axlefublr, neogna2
- [Gdip_All.ahk](https://www.autohotkey.com/boards/) — AutoHotkey GDI+ wrapper, community-maintained
	- Version maintained by Rseding91
	- v2 port by guest3456
	- MDMF monitor functions by just me
	- WinGetRect based on work by dd900 and Frosti

### Resources
- [Tango Desktop Project, Icons for Everyone](https://tekeye.uk/free_resources/tango_desktop_project/index)

## AI disclosure
Parts of Keybird's code were written and debugged with the assistance of Claude (Anthropic).
All AI-assisted code was reviewed, tested, and edited by the maintainer.
