# Lightroom Classic catalog sync between two PCs

**English** | [Français](README.fr.md)

Two ways to safely sync a Lightroom Classic catalog between two computers using a cloud sync tool (Synology Drive, kDrive, Dropbox, OneDrive, Google Drive...), without corrupting it. Pick the folder that matches how you actually work.

**Windows only.** Both scripts are Windows `.bat` files relying on Windows-specific tools (`robocopy`, `attrib`, PowerShell). There is no macOS or Linux version, though the underlying approach (relay folder, non-destructive pull, `.7z` transport) is not Windows-specific in principle and could be ported to shell scripts. Contributions welcome.

This document covers everything that applies to **both** scripts. Each variant's own README only covers what makes it different: see [Which one do you need?](#which-one-do-you-need) to pick one, then read that one too before installing.

## Table of contents

- [The problem](#the-problem)
- [What others have tried (and why it fails)](#what-others-have-tried-and-why-it-fails)
- [Why .7z archives](#why-7z-archives)
- [Compatibility with other tools](#compatibility-with-other-tools)
- [Requirements](#requirements)
- [Which one do you need?](#which-one-do-you-need)
- [Folder layout](#folder-layout)
- [Pinning a script to the taskbar](#pinning-a-script-to-the-taskbar)
- [Safety: what the scripts do to protect your data](#safety-what-the-scripts-do-to-protect-your-data)
- [Field report: a real incident](#field-report-a-real-incident)
- [Limitations and test conditions](#limitations-and-test-conditions)
- [Approaches that were rejected](#approaches-that-were-rejected)
- [License](#license)

## The problem

Since Lightroom Classic 11 (late 2021), the catalog is no longer just the `.lrcat` file. Several data folders live alongside it:

| Item | Contents |
|---|---|
| `CatalogName.lrcat` | The catalog itself (SQLite database): metadata, edits, keywords |
| `CatalogName.lrcat-data` | AI data: Denoise, generated selections, masks |
| `CatalogName Previews.lrdata` | Previews (regenerable, but slow to rebuild) |
| `CatalogName Helper.lrdata` | Face recognition |
| `CatalogName Sync.lrdata` | Adobe cloud sync data |

**Observed symptom**: the `.lrcat` file syncs normally through Synology Drive Client, but the 4 companion folders never sync, silently, with no error message.

**Identified cause**: Lightroom applies the Windows **System (S)** attribute to these folders every time the catalog is opened. Synology Drive Client refuses by design to sync any file or folder carrying that attribute.

Reproducible check:
```
attrib "CatalogName.lrcat-data"
```
confirms the `S` attribute is present. Running `attrib -S "CatalogName.lrcat-data" /D /S` removes it temporarily, but Lightroom reapplies it the next time the catalog is opened. So it is not a durable fix.

This problem often goes unnoticed at first: as long as these folders are empty or barely used (no AI edits, no face recognition), their missing sync is invisible. It becomes critical as soon as you actually use AI Denoise, generated selections, or face recognition. The data stored there stops being mere cache and becomes lost work if it never reaches the other machine.

And beyond that attribute: even if the sync worked, letting a sync tool read a catalog **while** Lightroom is writing to it (it is a live SQLite database) is the classic corruption scenario. Two distinct problems, then, that the solution must address together.

## What others have tried (and why it fails)

This is not an isolated Synology bug: the same wall is documented across every mainstream sync tool.

- **Adobe** explicitly states it does not support cloud sync, network drives, or external drives for its catalogs. The official recommendation is an external drive you physically move between machines, not continuous sync.
- **Infomaniak kDrive** officially documents the same class of issue for Adobe applications (Illustrator, Photoshop, Lightroom): save errors, duplicated files. Their official recommendation is to exclude these files from sync.
- **Dropbox**: several users on the Lightroom Queen forums report corrupted catalogs after Dropbox client updates, despite years of previously stable use. The workaround they found empirically: pause sync before opening Lightroom, resume it only after closing. That is exactly the manual principle these scripts automate.
- **OneDrive**: numerous threads on the Adobe and Lightroom Queen forums describe `.lrcat-data`/`.lrdata` files that refuse to sync while Lightroom has them open, corrupted previews, or renames that never propagate to the cloud. A sneaky trap: **Windows redirects the "Pictures" folder (and therefore the Lightroom catalog, which installs there by default) to OneDrive at setup**, often without the user realizing it.
- **Google Drive**: same cautionary reports. Works as long as a local copy exists and the sync has finished before every opening, but no native guarantee against concurrent writes.

The unanimous lesson across all these discussions, whatever the tool: never store the live catalog directly inside a synced folder, and never open Lightroom before the previous sync has fully completed. The blocking mechanism differs from tool to tool (System attribute, file locking, duplication...), but the underlying risk is identical everywhere: a sync tool never coordinates its access with the application lock of a program actively writing to a file.

**A note on Adobe's position.** It is fair to wonder whether Adobe's "unsupported" stance is purely technical or also commercially convenient. Adobe sells its own cloud offering (Creative Cloud, and a cloud-native Lightroom distinct from Classic) as the "officially supported" multi-device alternative: there is a clear incentive not to invest in better support for third-party sync tools. That said, the underlying technical risk is real and independently corroborated: the corruption incidents reported by the communities exist outside any Adobe marketing narrative, and the same class of problem affects other software built on embedded databases (QuickBooks, Access...) with no connection to Adobe. Both things can be true at once: a real risk, which Adobe is simply in no hurry to solve given where it leads commercially.

## Why .7z archives

The 4 companion folders can hold tens of thousands of small files (`Previews.lrdata` easily exceeds 25,000 files on a real catalog). Each individual file carries a fixed cost for a sync tool: verification, network request, antivirus scan. That cost adds up regardless of data size. Bottom line: syncing 25,000 small files takes far longer than syncing a single archive of the same total size.

Both scripts therefore pack each folder into a `.7z` archive in "store" mode (`-mx0`, no actual compression: Lightroom data is already internally compressed, the goal is packing speed, not space savings). The sync tool now only sees 5 files instead of tens of thousands.

An important side benefit: the archives are created from scratch by 7-Zip and never inherit the System attribute Lightroom stamps on the original folders. The whole attribute problem described above becomes moot for these 4 folders.

## Compatibility with other tools

Neither script talks directly to the sync tool: they only manipulate local folders and files (robocopy and 7-Zip between two paths on disk). The sync tool only steps in downstream, to propagate `_SyncedCopy` to the other machine. **Any cloud sync tool therefore works**, provided you can restrict it to the single `_SyncedCopy` folder.

| Tool | Equivalent setting |
|---|---|
| Synology Drive Client | Selective sync (per folder) |
| Infomaniak kDrive | Manage synced folders (desktop client) |
| Dropbox | Selective Sync |
| OneDrive | Choose folders |
| Google Drive (Drive for desktop) | Sync only these folders / mirror mode |

In every case the rule stays the same: check/sync only `_SyncedCopy`, never `_NoSync_WorkingFiles`, never the whole Lightroom folder.

## Requirements

- Windows 10 or 11
- Lightroom Classic (tested with 14.4)
- [7-Zip](https://www.7-zip.org/) installed (both scripts check for it at startup and guide you if it is missing)
- A sync tool configurable per folder (see table above)
- The same catalog name on all machines

## Which one do you need?

| | [`At each start/`](At%20each%20start/README.md) | [`On demand/`](On%20demand/README.md) |
|---|---|---|
| **Best for** | You alternate between both PCs often | You work 90%+ of the time on a single PC |
| **How it runs** | Every time you launch Lightroom | Only when you decide to switch machines |
| **Daily friction** | A short pull/push around every session | None: launch Lightroom normally |
| **Script** | `start-lightroom.bat` | `sync-catalog.bat` |

Both share everything on this page, plus the same underlying safety design detailed further down (non-destructive pull, `.7z` archive transport, integrity checks, crash-safety backups). The [`At each start`](At%20each%20start/README.md) and [`On demand`](On%20demand/README.md) READMEs only cover what is specific to each: how it runs day to day, its exact installation steps, and its own configuration table.

You can use both at once if it suits you: see the FAQ in the [`On demand`](On%20demand/README.md) README for the one caveat that comes with mixing them.

## Folder layout

```
Lightroom Sync/
  At each start/
    README.md, README.fr.md      <- what is specific to this variant
    start-lightroom.bat          <- edit CATALOG before use, then place next to your catalog
  On demand/
    README.md, README.fr.md      <- what is specific to this variant
    sync-catalog.bat             <- edit CATALOG before use, then place next to your catalog
```

Each script has its configurable variables grouped at the top: open it in a text editor, set `CATALOG` to your catalog's name, save, and place it in your Lightroom folder.

## Pinning a script to the taskbar

Windows blocks pinning a `.bat` file directly to the taskbar (a security restriction since Windows 10). The standard workaround goes through a shortcut that calls `cmd.exe`, since Windows allows pinning a real `.exe`. Same method for either script, only the filename in the Target changes.

**Recommended method**, so no shortcut ever lingers on the Desktop:

1. `Win + R`, type `shell:programs`, Enter (opens the real Start Menu folder).
2. Right-click inside that folder, **New > Shortcut**, and enter (use `start-lightroom.bat` or `sync-catalog.bat`, whichever you use):
   ```
   C:\Windows\System32\cmd.exe /c "C:\path\to\your\Lightroom\folder\start-lightroom.bat"
   ```
3. *(Optional)* Right-click the created shortcut, **Properties > Change Icon**, browse to `Lightroom.exe` for a recognizable icon instead of the `cmd.exe` one.
4. The shortcut automatically appears in the Start Menu app list. Right-click it, **Pin to Start** and/or **Pin to taskbar**.

The `/c` runs the script in that `cmd` window and closes it once finished; the script's `pause` prompts keep working normally since they run in that same session.

If a shortcut was already created on the Desktop and pinned: deleting it from the Desktop does not break the taskbar pin (Windows keeps its own reference at pin time). For the Start Menu it is less reliable across Windows 11 builds; to be safe, move the Desktop shortcut into `shell:programs` instead of deleting it.

Do this once per PC, with each machine's own path in the Target field.

## Safety: what the scripts do to protect your data

Each mechanism below answers a real risk encountered during development, and is implemented identically in both scripts:

- **Pull is never destructive.** The pull merges (`/E` + `/XO`): it adds and updates, but never overwrites a newer local file and never deletes anything locally. If Lightroom wrote fresh data during your last session, a pull cannot destroy it.
- **Push is a full mirror.** The push (`/MIR` through the archives) makes `_SyncedCopy` an exact reflection of your local state: intentional, since legitimate deletions made by Lightroom must propagate.
- **Integrity test of every archive, in both directions.** On pull, an archive is tested (`7z t`) before any extraction: if it is corrupted (an incomplete transfer, say), the script stops for that folder and your local version stays intact. On push, the freshly created archive is tested before being sent: no questionable archive ever enters the pipeline.
- **Safety backup before every pull.** The `.lrcat` and `.lrcat-data` (the catalog and its most tightly coupled data folder) are copied into `_NoSync_WorkingFiles\_CrashBackups\` with a timestamp, before the pull touches anything. Covered scenario: Lightroom crashes on PC A before the push, you then work on PC B, then return to PC A; the pull would overwrite your unpushed work, but the timestamped backup lets you recover it. The 2 most recent backups are kept (adjustable via `BACKUPS_KEEP`), older ones are purged automatically.
- **Aggregated problem detection.** Every anomaly (failed copy, corrupted archive, impossible backup...) raises an internal flag. Before opening Lightroom, if a problem occurred during the pull, the script warns you and lets you choose to stop. At the end of the cycle, if a problem occurred anywhere, the final message becomes an explicit warning ("DO NOT ASSUME EVERYTHING IS UP TO DATE") instead of the success message.
- **Post-push verification.** After the push, the script checks that the `.lrcat` is actually present in `_SyncedCopy`.
- **Safety pause before compressing.** 8 seconds before the push starts compressing, letting background writes (previews, AI cache) finish after Lightroom closes.
- **Startup guards.** Both scripts refuse to run if Lightroom is already open, if the catalog is not in `_NoSync_WorkingFiles`, or if 7-Zip is missing, each time with a message explaining what to do.

What the scripts cannot do: verify by themselves that the network sync has finished (no reliable API/CLI found across mainstream sync tools). That check remains visual and human, the single piece of discipline left to you.

## Field report: a real incident

During development, an early version used `/MIR` (mirror with deletion) for the pull as well. Concrete result: after a local work session, Lightroom had created fresh files inside `.lrcat-data`; the next pull, mirroring, deleted those local files because they did not exist yet in the relay folder. The catalog (protected by `/XO`, so never replaced) then referenced data the pull had just erased: Lightroom refused to open with a generic error that was very hard to diagnose.

Lessons baked into both scripts:

- The pull never uses `/MIR` anymore: it deletes nothing, no matter what.
- Archives are tested before any extraction: an incomplete transfer gets detected instead of producing an inconsistent local state.
- The `_CrashBackups` safety net keeps the `.lrcat` and `.lrcat-data` together, because restoring one without the other can recreate exactly that inconsistency.

If you adapt these scripts, remember the principle: **the relay-to-local direction must never delete anything**. That is the property guaranteeing a failed transfer is recoverable rather than destructive.

## Limitations and test conditions

- **Tested on**: Windows 11, Lightroom Classic 14.4, Synology Drive Client (desktop), 7-Zip, a catalog actively using AI Denoise, generated selections, face recognition and Adobe cloud sync.
- **Manual discipline required**: nothing technically prevents opening Lightroom on both machines at once if you ignore the scripts' messages. The protection relies on following the pull/retrieve → work → push/send flow.
- **No automatic end-of-sync verification**: no official CLI or API found in Synology Drive Client to query sync status from a script. The check remains visual (system tray icon), an accepted friction point.
- **Not officially supported by Adobe**: this method remains a community workaround. The `_CrashBackups` are a short-term net (2 versions), not a replacement for real backups: keep Lightroom's native backup (on close) and/or an external backup in parallel.
- **`.lrcat-shm` / `.lrcat-wal` / `.lrcat.lock`**: temporary SQLite files, intentionally excluded from copying. Never back them up or sync them.
- **Scripts intentionally accent-free (pure ASCII)**: a `.bat` containing accented characters depends on its save encoding. Depending on the editor used to modify it, the file can silently corrupt and throw `is not recognized as a command` errors at runtime. Staying pure ASCII eliminates that risk durably.
- **Scripts intentionally free of subroutines (`call :label`)**: that batch mechanism proved fragile in real use (intermittent "the system cannot find the batch label" failures, likely tied to the `.bat` being briefly locked by antivirus or the sync tool while `cmd.exe` re-reads the file to locate the label). Everything is written inline: more verbose, but without that failure point. `sync-catalog.bat`'s menu uses simple `goto` statements instead, executed before any disk activity.

## Approaches that were rejected

- **Switching sync tools (kDrive, Dropbox, OneDrive, Google Drive...) without a relay folder**: same class of problem whatever the tool (see [What others have tried](#what-others-have-tried-and-why-it-fails) above). Changing providers alone solves nothing at the root.
- **Symlinks to bypass the System attribute**: mentioned on some forums, mixed results depending on configuration. Rejected for lack of demonstrated reliability.
- **Automatic sync verification**: no official API/CLI; some community reports even note the status icon can freeze without reflecting the real state. A false sense of security would have been worse than a manual check.
- **File-count verification on pull**: implemented then removed. A mismatch on pull is normal and frequent (the pull never deletes anything locally, so stale files legitimately accumulate there): that check produced noise without signal. Moving to archives made the question moot anyway.
- **Virtual drive (`subst`) to unify photo paths**: works, but adds per-machine configuration to maintain (the command does not survive a reboot). Not used here; keeping the same photo folder structure on both PCs is simpler.

## License

MIT License: free use and modification, including commercial use, on the sole condition of keeping the copyright and license notice below in any redistribution: that is what guarantees this repository stays credited as the source.

```
MIT License

Copyright (c) 2026 tnalias

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

Also place this in a separate `LICENSE` file at the repository root (GitHub convention).
