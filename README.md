# Inspect Draw

A plugin for the [Ballest plugin manager](https://github.com/AnythingGoes-ballest/ballest-plugin-manager): draw 3D
lines on the map while looking around in inspect mode (**T** on a track).

- **Pencil** (top left of the menu): hold the **left mouse button** to draw a tube that follows the cursor. A line
  keeps to the surface it starts on (something passing in front of it doesn't take it), stays in the air over gaps,
  and only carries on to another surface that continues it, such as the next piece of track or the far side of a
  jump.
- **Eraser**: takes away the parts of lines it passes over; a line erased through its middle leaves both halves.
- Click the lit tool again to turn it off and turn the camera with the mouse as usual. While a tool is on, the camera
  stays still as you draw or erase.
- **Brush size** / **eraser size** (each tool keeps its own): the slider, or **[** and **]**. A ring at the cursor
  shows the size.
- **Ctrl+Z** undoes and **Ctrl+Y** (or Ctrl+Shift+Z) redoes: lines, erases and **clear all**. **1** to **0** pick a
  colour.
- The menu shows only in inspect mode and steps aside while the game's pause menu is up. Drag it wherever you like
  (**reset position** in the plugin's settings puts it back). It also has **draw on surfaces** (off: lines go in the
  air at the set distance), **show lines** and **show while driving** (off by default).
- Lines are saved per map and come back the next time you play it.

Needs Draw Core (installed with it) and host 0.31.0 (`Camera::Inspecting`, `Camera::Deproject`, `Camera::Pick`,
`Camera::PickOn`, `Window.hovered`, picture icon buttons).
