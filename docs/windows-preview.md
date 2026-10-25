# Trying the interface on Windows (WSLg)

You do not need to flash a card to test the first-boot wizard, focus rings,
remote/keyboard navigation or Settings. The production Qt/QML launcher can run
inside WSL2 and WSLg shows its window on the Windows desktop.

This is a **UI and input preview**, not a Raspberry Pi emulator. It is the right
place to catch a trapped focus ring before touching a card; it cannot prove
HDMI, Wi-Fi, audio, DRM, boot time or physical remote behaviour.

## Requirements

- Windows 10 21H2+ or Windows 11 with WSLg (the default WSL2 graphics support).
- A WSL2 distribution named `Ubuntu` (use `-Distro <name>` if yours differs).
- Qt 6 development packages inside WSL:

```bash
wsl -d Ubuntu -u root -- apt-get update
wsl -d Ubuntu -u root -- apt-get install -y qt6-base-dev qt6-declarative-dev \
  cmake g++ pkg-config
```

## Run it

From the repository root in PowerShell:

```powershell
.\tools\windows-preview.ps1
```

Or double-click `tools\preview-windows.cmd`. The first run builds the launcher;
later runs reuse `build/launcher-wsl-preview/`.

The preview has its own settings directory (`build/preview-home/`), so it never
reads or writes a real Pi configuration. To see the **first-boot wizard again**:

```powershell
.\tools\windows-preview.ps1 -Reset
```

The window opens at 1280x720 by default. For the 1080p layout:

```powershell
$env:PIVISTA_UI_WIDTH = "1920"
$env:PIVISTA_UI_HEIGHT = "1080"
.\tools\windows-preview.ps1
```

## What to test

1. **Wizard first page:** Down moves from **Continue** to **Back**, Up moves
   back, Enter selects, Escape goes back.
2. **Language/time zone:** Up and Down stay inside the focused list; at the
   edges, focus moves to the adjacent list or the navigation buttons.
3. **Network:** this page will fail without the control service. Confirm the
   error is readable and that **Continue** still works.
4. **Display and audio:** confirm empty/error states do not remove the focus
   ring, and that the wizard can continue.
5. **Finish:** setup completes with warnings for the actions that need the
   missing service; it must not dead-end.
6. **Home navigation:** from the featured banner, press Down (a content row),
   Up (banner), Up again (**header**). This last step is the one that used to
   trap the remote between the banner and the first row.
7. **Header:** Right moves through Home, Apps, Games, Media, Search and
   Settings; Enter opens the highlighted section. Down returns to content.
8. **Settings:** navigate sections and pages, then Escape/Up returns to the
   header. A setting that needs the daemon reports an error instead of silently
   pretending to apply.
9. **Home/Back:** Escape from a top-level section returns Home. F10 or the Menu
   key opens quick settings.

Useful keys: arrows, Enter/OK, Escape/Backspace, F10/Menu, Home. WSLg and
Windows may reserve a few laptop function keys; use the application's documented
alternatives if one does not arrive.

## Expected limitations

- There is **no `pivistad` control service** in the preview. On start, the
  orange message **“The PiVista control service is not running.”** is expected.
  Network scanning, display mode changes, audio routing, power actions and
  package updates will report failures. The wizard still lets you continue.
- Launching a web shortcut or a native app is not a preview feature; it needs
  Chromium, the launcher's kiosk session and the PiVista daemon.
- The preview does not emulate sway/libinput, a USB receiver, Bluetooth or
  HDMI-CEC. It proves the QML focus graph and key handling under WSLg, **not**
  that a particular remote works on a Pi.
- It is not a native Windows build and not a substitute for the image tests or
  the hardware checklist in [hardware-test.md](hardware-test.md).

## If the preview will not start

| Symptom | Fix |
|---|---|
| `WSL distro 'Ubuntu' is not available` | Install WSL2 Ubuntu, or run `.\tools\windows-preview.ps1 -Distro <name>` |
| `Qt 6 development packages are not installed` | Run the `apt-get install` command above inside WSL |
| `no WSLg display` | Update Windows/WSL (`wsl --update`) and run from a Windows desktop session, not a remote shell without WSLg |
| A blank or oversized window | Try `-Reset`; set `PIVISTA_UI_WIDTH=1280` and `PIVISTA_UI_HEIGHT=720` |
| The build cache complains about a different path | Remove `build/launcher-wsl-preview/` and run again |
