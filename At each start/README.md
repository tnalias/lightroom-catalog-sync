# Sync a Lightroom Classic catalog between two PCs using a cloud sync tool (Synology Drive, kDrive, Dropbox, OneDrive, Google Drive...)

**English** | [Français](README.fr.md)

## TL;DR

You want to work on the same Lightroom Classic catalog from two computers (a desktop and a laptop, say), using your usual sync tool to move the data around. Problem: cloud sync tools and Lightroom catalogs do not mix, and it ends in corrupted catalogs or silently missing data.

This repository provides a single script, `start-lightroom.bat`, that replaces your usual Lightroom shortcut. Every time you launch it, it does three things:

1. It **pulls** the latest version of the catalog (in case you worked on the other PC).
2. It **launches Lightroom** and waits for you to close it.
3. It **pushes** your changes so they travel back to the other PC.

Your sync tool never touches the files Lightroom actually uses: it only ever sees a relay folder, which is manipulated exclusively while Lightroom is closed. That is what makes the method safe.

This document only covers what is specific to this `start-lightroom.bat` variant: the exact steps below assume you have already read the [top-level README](../README.md), which covers everything shared by both scripts (the problem, why sync tools corrupt Lightroom catalogs, requirements, folder layout, safety mechanisms, limitations, and more).

**Two usage modes are available**: `start-lightroom.bat` syncs automatically on every Lightroom launch (this document), while `sync-catalog.bat` syncs only on demand, for people who work 90% of the time on a single machine: see [the on-demand variant](../On%20demand/README.md).

## Table of contents

- [How it works](#how-it-works)
- [Installation](#installation)
- [Adapting the script to your setup](#adapting-the-script-to-your-setup)
- [Daily usage](#daily-usage)

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

### What it looks like once set up

By default, Lightroom Classic creates its catalog inside your Windows user's Pictures folder. The `Lightroom\` folder below is typically:
```
C:\Users\<YourUsername>\Pictures\Lightroom\
```
(On a French-language Windows, this folder displays as "Images" in Explorer, but its underlying name stays `Pictures`.) If your catalog lives somewhere else, that is fine too: the script does not care where this folder is, only that everything below sits inside it.

Concrete example, with a catalog named `CatalogName`:

```
Lightroom\
  start-lightroom.bat
  _NoSync_WorkingFiles\
    CatalogName.lrcat
    CatalogName.lrcat-data\
    CatalogName Previews.lrdata\
    CatalogName Helper.lrdata\
    CatalogName Sync.lrdata\
    _CrashBackups\                    <- created automatically, safety copies
  _SyncedCopy\
    CatalogName.lrcat
    CatalogName.lrcat-data.7z
    CatalogName Previews.lrdata.7z
    CatalogName Helper.lrdata.7z
    CatalogName Sync.lrdata.7z
```

`_NoSync_WorkingFiles` holds the real, loose files Lightroom uses directly: this is where your actual catalog and its 4 companion folders live day to day. `_SyncedCopy` is the only folder your sync tool watches: same `.lrcat`, but the 4 companion folders travel as `.7z` archives instead (see [Why .7z archives](../README.md#why-7z-archives) for the reason). `_CrashBackups` appears on its own inside `_NoSync_WorkingFiles` after the first pull: nothing to create manually there.

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
