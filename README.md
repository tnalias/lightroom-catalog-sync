# Lightroom Classic catalog sync between two PCs

**English** | [Français](README.fr.md)

Two ways to safely sync a Lightroom Classic catalog between two computers using a cloud sync tool (Synology Drive, kDrive, Dropbox, OneDrive, Google Drive...), without corrupting it. Pick the folder that matches how you actually work.

**Windows only.** Both scripts are Windows `.bat` files relying on Windows-specific tools (`robocopy`, `attrib`, PowerShell). There is no macOS or Linux version, though the underlying approach (relay folder, non-destructive pull, `.7z` transport) is not Windows-specific in principle and could be ported to shell scripts. Contributions welcome.

## Which one do you need?

| | [`At each start/`](At%20each%20start/README.md) | [`On demand/`](On%20demand/README.md) |
|---|---|---|
| **Best for** | You alternate between both PCs often | You work 90%+ of the time on a single PC |
| **How it runs** | Every time you launch Lightroom | Only when you decide to switch machines |
| **Daily friction** | A short pull/push around every session | None: launch Lightroom normally |
| **Script** | `start-lightroom.bat` | `sync-catalog.bat` |

Both share the same underlying safety design (relay folder, non-destructive pull, `.7z` archive transport, integrity checks, crash-safety backups) documented in full inside the [`At each start`](At%20each%20start/README.md) README. The [`On demand`](On%20demand/README.md) README only covers what is different about that variant, and assumes you have read the first one.

You can use both at once if it suits you: see the FAQ in the [`On demand`](On%20demand/README.md) README for the one caveat that comes with mixing them.

## Folder layout

```
Lightroom Sync/
  At each start/
    README.md, README.fr.md      <- full documentation (read this first)
    start-lightroom.bat          <- edit CATALOG before use, then place next to your catalog
  On demand/
    README.md, README.fr.md      <- documentation of what differs
    sync-catalog.bat             <- edit CATALOG before use, then place next to your catalog
```

Each script has its configurable variables grouped at the top: open it in a text editor, set `CATALOG` to your catalog's name, save, and place it in your Lightroom folder.

## License

MIT, see either README for the full text.
