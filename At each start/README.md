# Sync a Lightroom Classic catalog between two PCs using a cloud sync tool (Synology Drive, kDrive, Dropbox, OneDrive, Google Drive...)

**English** | [Français](README.fr.md)

## TL;DR

You want to work on the same Lightroom Classic catalog from two computers (a desktop and a laptop, say), using your usual sync tool to move the data around. Problem: cloud sync tools and Lightroom catalogs do not mix, and it ends in corrupted catalogs or silently missing data.

This repository provides a single script, `start-lightroom.bat`, that replaces your usual Lightroom shortcut. Every time you launch it, it does three things:

1. It **pulls** the latest version of the catalog (in case you worked on the other PC).
2. It **launches Lightroom** and waits for you to close it.
3. It **pushes** your changes so they travel back to the other PC.

Your sync tool never touches the files Lightroom actually uses: it only ever sees a relay folder, which is manipulated exclusively while Lightroom is closed. That is what makes the method safe.

Developed and tested with Synology Drive Client, but the problem and the solution do not depend on the sync tool you use: see [Compatibility with other tools](#compatibility-with-other-tools).

**Two usage modes are available**: `start-lightroom.bat` syncs automatically on every Lightroom launch (this document), while `sync-catalog.bat` syncs only on demand, for people who work 90% of the time on a single machine: see [the on-demand variant](../On%20demand/README.md).

## Table of contents

- [The problem](#the-problem)
- [What others have tried (and why it fails)](#what-others-have-tried-and-why-it-fails)
- [How it works](#how-it-works)
- [Why .7z archives](#why-7z-archives)
- [Compatibility with other tools](#compatibility-with-other-tools)
- [Requirements](#requirements)
- [Installation](#installation)
- [Adapting the script to your setup](#adapting-the-script-to-your-setup)
- [Daily usage](#daily-usage)
- [Pinning the script to the taskbar](#pinning-the-script-to-the-taskbar)
- [Safety: what the script does to protect your data](#safety-what-the-script-does-to-protect-your-data)
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
- **Dropbox**: several users on the Lightroom Queen forums report corrupted catalogs after Dropbox client updates, despite years of previously stable use. The workaround they found empirically: pause sync before opening Lightroom, resume it only after closing. That is exactly the manual principle this repository automates.
- **OneDrive**: numerous threads on the Adobe and Lightroom Queen forums describe `.lrcat-data`/`.lrdata` files that refuse to sync while Lightroom has them open, corrupted previews, or renames that never propagate to the cloud. A sneaky trap: **Windows redirects the "Pictures" folder (and therefore the Lightroom catalog, which installs there by default) to OneDrive at setup**, often without the user realizing it.
- **Google Drive**: same cautionary reports. Works as long as a local copy exists and the sync has finished before every opening, but no native guarantee against concurrent writes.

The unanimous lesson across all these discussions, whatever the tool: never store the live catalog directly inside a synced folder, and never open Lightroom before the previous sync has fully completed. The blocking mechanism differs from tool to tool (System attribute, file locking, duplication...), but the underlying risk is identical everywhere: a sync tool never coordinates its access with the application lock of a program actively writing to a file.

**A note on Adobe's position.** It is fair to wonder whether Adobe's "unsupported" stance is purely technical or also commercially convenient. Adobe sells its own cloud offering (Creative Cloud, and a cloud-native Lightroom distinct from Classic) as the "officially supported" multi-device alternative: there is a clear incentive not to invest in better support for third-party sync tools. That said, the underlying technical risk is real and independently corroborated: the corruption incidents reported by the communities exist outside any Adobe marketing narrative, and the same class of problem affects other software built on embedded databases (QuickBooks, Access...) with no connection to Adobe. Both things can be true at once: a real risk, which Adobe is simply in no hurry to solve given where it leads commercially.

## How it works

Principle: never let the sync tool touch the catalog's live files. Instead, a relay folder acts as intermediary, and is only manipulated while Lightroom is closed, therefore never mid-write.

```
Lightroom\
  ├── start-lightroom.bat     <- the script (replaces your usual shortcut)
  ├── _NoSync_WorkingFiles\   <- live files, used by Lightroom
  │                              NEVER synced
  └── _SyncedCopy\            <- relay folder
                                 the ONLY synced folder
                                 contains: the .lrcat + 4 .7z archives
```

On every launch, the script runs 4 steps:

1. **Check**: Lightroom must not already be running on this machine (otherwise the script stops).
2. **Pull**: the script asks you to visually confirm your sync tool shows "up to date", then fetches the `.lrcat` and the 4 archives from `_SyncedCopy`, tests each archive's integrity, extracts them, and merges the contents into `_NoSync_WorkingFiles`. This merge never overwrites a newer local file and never deletes anything: if something goes wrong, your local version stays intact.
3. **Lightroom**: the script launches Lightroom and waits in the background for you to close it. You work normally.
4. **Push**: after a safety pause (giving Lightroom time to finish background writes), the script compresses each of the 4 folders into a `.7z` archive, tests the integrity of each freshly created archive, then copies them along with the `.lrcat` into `_SyncedCopy`. Your sync tool takes over and propagates everything to the other PC.

The script is self-locating (`%~dp0`: it derives its own location) and identical on every machine: a single file to copy, no path editing needed, only the catalog name to configure once.

## Why .7z archives

The 4 companion folders can hold tens of thousands of small files (`Previews.lrdata` easily exceeds 25,000 files on a real catalog). Each individual file carries a fixed cost for a sync tool: verification, network request, antivirus scan. That cost adds up regardless of data size. Bottom line: syncing 25,000 small files takes far longer than syncing a single archive of the same total size.

The script therefore packs each folder into a `.7z` archive in "store" mode (`-mx0`, no actual compression: Lightroom data is already internally compressed, we want packing speed, not space savings). The sync tool now only sees 5 files instead of tens of thousands.

An important side benefit: the archives are created from scratch by 7-Zip and never inherit the System attribute Lightroom stamps on the original folders. The whole attribute problem described above becomes moot for these 4 folders.

## Compatibility with other tools

The script never talks directly to the sync tool: it only manipulates local folders and files (robocopy and 7-Zip between two paths on disk). The sync tool only steps in downstream, to propagate `_SyncedCopy` to the other machine. **Any cloud sync tool therefore works**, provided you can restrict it to the single `_SyncedCopy` folder.

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
- [7-Zip](https://www.7-zip.org/) installed (the script checks for it at startup and guides you if it is missing)
- A sync tool configurable per folder (see table above)
- The same catalog name on all machines

## Installation

### On the first PC (the one that already has the catalog)

1. Open `start-lightroom.bat` in a text editor and replace `NomCatalogue` in the line `set "CATALOG=NomCatalogue"` with your actual catalog name, without the `.lrcat` extension (see [Adapting the script to your setup](#adapting-the-script-to-your-setup) for the other settings).
2. Place `start-lightroom.bat` directly inside your Lightroom folder.
3. With Lightroom closed, create the `_NoSync_WorkingFiles` folder in that same folder.
4. Move the `.lrcat` and its 4 companion folders (`.lrcat-data`, `Previews.lrdata`, `Helper.lrdata`, `Sync.lrdata`) into it.
5. Open Lightroom once by double-clicking the `.lrcat` directly at its new location (so Lightroom memorizes the new path), then close it.
6. Run `start-lightroom.bat`: on first launch it automatically creates `_SyncedCopy` and reminds you of the next step. Let it run one full cycle (empty pull, Lightroom, push): when you close Lightroom, it fills `_SyncedCopy` with the `.lrcat` and the 4 archives.
7. In your sync tool, enable selective sync on **only** `_SyncedCopy`.
8. Wait for the sync to fully upload the 5 files to the cloud/NAS before moving on to the next PC.

### On the next PC(s)

This PC does not have the catalog yet: it will receive it through sync.

1. Copy the same `start-lightroom.bat` (already configured) into your Lightroom folder on this machine.
2. Configure your sync tool to sync only `_SyncedCopy`, and wait until the 5 files (the `.lrcat` plus the 4 `.7z` archives) appear fully synced there.
3. Create the `_NoSync_WorkingFiles` folder next to it.
4. Manually copy just the `.lrcat` file from `_SyncedCopy` into `_NoSync_WorkingFiles` (the script requires its presence as a guard before running; the 4 folders will be extracted automatically from the archives on the first pull).
5. Run `start-lightroom.bat`: the pull extracts the 4 archives into `_NoSync_WorkingFiles`, then Lightroom launches. On this very first opening on this machine, Lightroom does not know this catalog yet: open it through File > Open Catalog, pointing to the `.lrcat` inside `_NoSync_WorkingFiles`. From then on it opens automatically.

## Adapting the script to your setup

All customizable variables sit together at the top of the script:

| Variable | Role | Change it? |
|---|---|---|
| `CATALOG` | Your catalog name, without `.lrcat` | **Yes, required** (once, same value on all PCs) |
| `LIGHTROOM_EXE` | Path to `Lightroom.exe` | Only for non-standard installs (right-click your Lightroom shortcut > Properties > Target to find it) |
| `ZIP7` | Path to `7z.exe` | Only if 7-Zip lives somewhere other than `C:\Program Files\7-Zip\` |
| `BACKUPS_KEEP` | Number of safety backups kept | Optional (2 by default) |

Everything else adapts automatically: the script detects its own location (`%~dp0`), so the folder paths never need editing, even if your Lightroom folder is on `C:` on one machine and `D:` on the other.

If your Lightroom folder lives at different locations across PCs, the catalog handles it fine. However, if your **photos** also live at different paths, Lightroom will mark them "missing" when switching machines: keep the same photo folder structure on both PCs to avoid that.

## Daily usage

- Always launch Lightroom through `start-lightroom.bat`, never directly.
- Never open Lightroom on both PCs at the same time.
- Before opening Lightroom on the other PC, visually check that your sync tool shows "up to date" (no sync in progress).
- If the script prints WARNING lines, read them: it will explicitly warn you at the end of the cycle and advise against switching to the other PC until the problem is understood.

## Pinning the script to the taskbar

Windows blocks pinning a `.bat` file directly to the taskbar (a security restriction since Windows 10). The standard workaround goes through a shortcut that calls `cmd.exe`, since Windows allows pinning a real `.exe`.

**Recommended method**, so no shortcut ever lingers on the Desktop:

1. `Win + R`, type `shell:programs`, Enter (opens the real Start Menu folder).
2. Right-click inside that folder, **New > Shortcut**, and enter:
   ```
   C:\Windows\System32\cmd.exe /c "C:\path\to\your\Lightroom\folder\start-lightroom.bat"
   ```
3. *(Optional)* Right-click the created shortcut, **Properties > Change Icon**, browse to `Lightroom.exe` for a recognizable icon instead of the `cmd.exe` one.
4. The shortcut automatically appears in the Start Menu app list. Right-click it, **Pin to Start** and/or **Pin to taskbar**.

The `/c` runs the script in that `cmd` window and closes it once finished; the script's `pause` prompts keep working normally since they run in that same session.

If a shortcut was already created on the Desktop and pinned: deleting it from the Desktop does not break the taskbar pin (Windows keeps its own reference at pin time). For the Start Menu it is less reliable across Windows 11 builds; to be safe, move the Desktop shortcut into `shell:programs` instead of deleting it.

Do this once per PC, with each machine's own path in the Target field.

## Safety: what the script does to protect your data

Each mechanism below answers a real risk encountered during development:

- **Pull is never destructive.** The pull merges (`/E` + `/XO`): it adds and updates, but never overwrites a newer local file and never deletes anything locally. If Lightroom wrote fresh data during your last session, a pull cannot destroy it.
- **Push is a full mirror.** The push (`/MIR` through the archives) makes `_SyncedCopy` an exact reflection of your local state: intentional, since legitimate deletions made by Lightroom must propagate.
- **Integrity test of every archive, in both directions.** On pull, an archive is tested (`7z t`) before any extraction: if it is corrupted (an incomplete transfer, say), the script stops for that folder and your local version stays intact. On push, the freshly created archive is tested before being sent: no questionable archive ever enters the pipeline.
- **Safety backup before every pull.** The `.lrcat` and `.lrcat-data` (the catalog and its most tightly coupled data folder) are copied into `_NoSync_WorkingFiles\_CrashBackups\` with a timestamp, before the pull touches anything. Covered scenario: Lightroom crashes on PC A before the push, you then work on PC B, then return to PC A; the pull would overwrite your unpushed work, but the timestamped backup lets you recover it. The 2 most recent backups are kept (adjustable via `BACKUPS_KEEP`), older ones are purged automatically.
- **Aggregated problem detection.** Every anomaly (failed copy, corrupted archive, impossible backup...) raises an internal flag. Before opening Lightroom, if a problem occurred during the pull, the script warns you and lets you choose to stop. At the end of the cycle, if a problem occurred anywhere, the final message becomes an explicit warning ("DO NOT ASSUME EVERYTHING IS UP TO DATE") instead of the success message.
- **Post-push verification.** After the push, the script checks that the `.lrcat` is actually present in `_SyncedCopy`.
- **Safety pause on close.** 8 seconds between Lightroom closing and the push starting, letting background writes (previews, AI cache) finish.
- **Startup guards.** The script refuses to run if Lightroom is already open, if the catalog is not in `_NoSync_WorkingFiles`, or if 7-Zip is missing, each time with a message explaining what to do.

What the script cannot do: verify by itself that the network sync has finished (no reliable API/CLI found across mainstream sync tools). That check remains visual and human, the single piece of discipline left to you.

## Field report: a real incident

During development, an early version of the script used `/MIR` (mirror with deletion) for the pull as well. Concrete result: after a local work session, Lightroom had created fresh files inside `.lrcat-data`; the next pull, mirroring, deleted those local files because they did not exist yet in the relay folder. The catalog (protected by `/XO`, so never replaced) then referenced data the pull had just erased: Lightroom refused to open with a generic error that was very hard to diagnose.

Lessons baked into the current script:

- The pull never uses `/MIR` anymore: it deletes nothing, no matter what.
- Archives are tested before any extraction: an incomplete transfer gets detected instead of producing an inconsistent local state.
- The `_CrashBackups` safety net keeps the `.lrcat` and `.lrcat-data` together, because restoring one without the other can recreate exactly that inconsistency.

If you adapt this script, remember the principle: **the relay-to-local direction must never delete anything**. That is the property guaranteeing a failed transfer is recoverable rather than destructive.

## Limitations and test conditions

- **Tested on**: Windows 11, Lightroom Classic 14.4, Synology Drive Client (desktop), 7-Zip, a catalog actively using AI Denoise, generated selections, face recognition and Adobe cloud sync.
- **Manual discipline required**: nothing technically prevents opening Lightroom on both machines at once if you ignore the script's messages. The protection relies on following the pull → work → push flow.
- **No automatic end-of-sync verification**: no official CLI or API found in Synology Drive Client to query sync status from a script. The check remains visual (system tray icon), an accepted friction point.
- **Not officially supported by Adobe**: this method remains a community workaround. The script's `_CrashBackups` are a short-term net (2 versions), not a replacement for real backups: keep Lightroom's native backup (on close) and/or an external backup in parallel.
- **`.lrcat-shm` / `.lrcat-wal` / `.lrcat.lock`**: temporary SQLite files, intentionally excluded from copying. Never back them up or sync them.
- **Script intentionally accent-free (pure ASCII)**: a `.bat` containing accented characters depends on its save encoding. Depending on the editor used to modify it, the file can silently corrupt and throw `is not recognized as a command` errors at runtime. Staying pure ASCII eliminates that risk durably.
- **Script intentionally free of subroutines (`call :label`)**: that batch mechanism proved fragile in real use (intermittent "the system cannot find the batch label" failures, likely tied to the `.bat` being briefly locked by antivirus or the sync tool while `cmd.exe` re-reads the file to locate the label). Everything is written inline: more verbose, but without that failure point.

## Approaches that were rejected

- **Switching sync tools (kDrive, Dropbox, OneDrive, Google Drive...) without a relay folder**: same class of problem whatever the tool (see [What others have tried](#what-others-have-tried-and-why-it-fails)). Changing providers alone solves nothing at the root.
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
