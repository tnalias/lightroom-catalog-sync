# On-demand sync variant: `sync-catalog.bat`

**English** | [Français](README.fr.md)

This is a companion to the main project (see [README](../At%20each%20start/README.md) for the full context: the problem, why sync tools corrupt Lightroom catalogs, the relay folder architecture, and the `.7z` transport). Read that first if you have not.

## When to use this variant instead of `start-lightroom.bat`

`start-lightroom.bat` syncs on **every** Lightroom launch. That is the right choice when you alternate between machines often: the discipline is built in, you cannot forget.

`sync-catalog.bat` syncs **only when you ask**. That is the right choice when you work 90% of the time on a single machine: day to day you launch Lightroom normally (double-click, your usual shortcut, zero ritual, zero wait), and you run this script only on the day you actually switch machines. It works whichever machine is your main one, and both scripts can coexist in the same folder.

The trade-off: the protection is no longer systematic, it relies on you remembering to sync before switching. The script compensates with a divergence guard (below) that catches the dangerous case if you forget.

## How it works

Run `sync-catalog.bat` (Lightroom closed). It shows where things stand, then asks one situational question:

```
Where are you at?

  [1] I just FINISHED working on THIS PC
      -> Send my changes to the other PC

  [2] I am ABOUT TO work on THIS PC
      -> First retrieve the changes made on the other PC

  [3] Cancel (do nothing)
```

No push/pull jargon: you answer based on your situation, not on sync mechanics. After your choice, the script shows a one-line recap of exactly what it is about to do (which machine sends or receives, which version gets replaced, sent by whom and when) and waits for a final keypress before acting.

## Switching machines: the complete sequence

1. **On the PC you just worked on**: close Lightroom, run `sync-catalog.bat`, choose **[1] Send**.
2. **Wait** for your sync tool to propagate (icon shows "up to date" on both machines).
3. **On the PC you are moving to**: run `sync-catalog.bat`, choose **[2] Retrieve**, then open Lightroom normally.

That is all. Between two switches, no script, no ritual: just use Lightroom.

## The divergence guard

The real danger of on-demand mode is not technical, it is **forgetting**. Scenario: you work three weeks on PC B without syncing (normal, no need to), then grab PC A one day forgetting to send first. You work on PC A on top of an old version, you send from PC A... and now two diverged catalog versions exist. Lightroom cannot merge two diverged catalogs. This is the worst possible outcome, worse than corruption.

The guard: every successful send writes a witness file (`last-sync-state.txt`) into `_SyncedCopy`, recording which machine sent and when. Every machine also keeps a local trace of the last version it retrieved. Thanks to these:

- **On send**, if the relay's current version came from the other machine AND was never retrieved here, the script stops with an explicit blocking warning ("sending now would overwrite work done on [other PC]") and a deliberate yes/no choice, defaulting you toward canceling and retrieving first.
- **On retrieve**, the script always tells you who sent the relay's current version and when. If it came from this very PC (nothing new to fetch), it says so and asks whether you really want to proceed, instead of silently doing a no-op you might misread as a successful transfer.

State files are only written when an operation completes **without any error**: a partial send is never recorded as a valid relay version.

## Everything inherited from the main script

Same folder structure, same requirements (7-Zip, same catalog name everywhere), same installation as `start-lightroom.bat` (see the main [README](../At%20each%20start/README.md)), and the same safety mechanisms:

- Retrieve is never destructive: it never overwrites a newer local file and never deletes anything locally.
- Every archive is integrity-tested before extraction (retrieve) and before upload (send).
- A timestamped safety backup of `.lrcat` + `.lrcat-data` is taken before every retrieve (`_CrashBackups`, 2 most recent kept, adjustable via `BACKUPS_KEEP`).
- Aggregated error detection: any anomaly turns the final message into an explicit warning instead of a success message.
- Startup guards: refuses to run if Lightroom is open, the catalog is missing, or 7-Zip is absent.
- Pure ASCII, no `call :label` subroutines (only two simple `goto` statements for menu branching, executed before any disk activity).

## Installation

Same folders as `start-lightroom.bat` (`_NoSync_WorkingFiles` + `_SyncedCopy`), same principle, adapted to this script's send/retrieve menu instead of an automatic pull-then-push:

**On the first PC (the one that already has the catalog):**
1. Edit `CATALOG` in `sync-catalog.bat` (see [Adapting the script](#configuration) below).
2. Place `sync-catalog.bat` in your Lightroom folder. With Lightroom closed, create `_NoSync_WorkingFiles` and move the `.lrcat` and its 4 companion folders into it, exactly as described in the main README's installation steps 3-5.
3. Run `sync-catalog.bat`, choose **[1] Send** (this creates `_SyncedCopy` on first run and pushes into it).
4. In your sync tool, enable selective sync on **only** `_SyncedCopy`.
5. Wait for the sync to fully upload before moving to the next PC.

**On the next PC(s):**
1. Copy the same configured `sync-catalog.bat` into your Lightroom folder there.
2. Configure your sync tool on `_SyncedCopy`, and wait until the `.lrcat` and the 4 archives appear fully synced.
3. Create `_NoSync_WorkingFiles`, and manually copy just the `.lrcat` file into it (the script requires its presence as a guard; the 4 folders are extracted automatically on the first retrieve).
4. Run `sync-catalog.bat`, choose **[2] Retrieve**.
5. Open Lightroom via File > Open Catalog, pointing to the `.lrcat` in `_NoSync_WorkingFiles`. It opens automatically from then on.

## Configuration

Configuration is 2-3 variables at the top of `sync-catalog.bat`:

| Variable | Role | Change it? |
|---|---|---|
| `CATALOG` | Your catalog name, without `.lrcat` | **Yes, required** (once, same value on all PCs) |
| `ZIP7` | Path to `7z.exe` | Only if 7-Zip lives somewhere other than `C:\Program Files\7-Zip\` |
| `BACKUPS_KEEP` | Number of safety backups kept | Optional (2 by default) |

`LIGHTROOM_EXE` does not exist in this script: it is not needed, since `sync-catalog.bat` never launches Lightroom.

## Pinning the script

Same method as `start-lightroom.bat`: see [Pinning the script to the taskbar](../At%20each%20start/README.md#pinning-the-script-to-the-taskbar) in the main README. Only difference: point the shortcut's Target at `sync-catalog.bat` instead:
```
C:\Windows\System32\cmd.exe /c "C:\path\to\your\Lightroom\folder\sync-catalog.bat"
```

## FAQ

**The script blocked my send with a "RISK OF LOSING WORK" warning. What now?**
It means the relay holds a version from the other machine that you never retrieved on this PC. In almost every case the right move is: answer N, run **[2] Retrieve** first, check your catalog in Lightroom, then send. Only override with O if you are certain this PC's version is the one to keep and the other machine's version should be discarded.

**I chose Retrieve but nothing seemed to change.**
Check the message: if the relay's latest version was sent by this same PC, there was genuinely nothing new to fetch. Work done on the other machine only reaches the relay after you run **[1] Send** over there.

**Can I keep using `start-lightroom.bat` too?**
Yes, both scripts share the same folders and archives and can coexist. One caveat: `start-lightroom.bat` does not update the witness file (its systematic pull-then-push flow does not need one). If you push through `start-lightroom.bat`, the witness becomes stale, and the divergence guard may give a wrong verdict on the next manual send. Simplest safe rule: stick to one mode per period of time; if you do mix them, run **[2] Retrieve** on the other machine before trusting any send.

## License

Same MIT license as the main project (see [README](../At%20each%20start/README.md)).
