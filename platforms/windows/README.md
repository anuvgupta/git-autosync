# Windows (Task Scheduler)

Registers a scheduled task that runs `sync.py` on an interval. Task Scheduler is
Windows' cron equivalent; this is the counterpart to the macOS LaunchAgent and
the Linux systemd timer.

## Install

From PowerShell:

```powershell
.\platforms\windows\install.ps1 C:\path\to\repo -Interval 300
```

From Git Bash, the top-level dispatcher detects MSYS and hands off to PowerShell:

```sh
./install.sh /c/path/to/repo --interval 300
```

## Options

```
-Label LABEL      scheduled task name   (default: git-autosync-<repo-name>)
-Interval SECS    sync interval         (default: 300; minimum 60)
-Log PATH         log file path         (default: %LOCALAPPDATA%\git-autosync\<label>.log)
-Python PATH      python interpreter    (default: first python.exe on PATH)
```

## Scope: runs while logged in

The task uses a **logon trigger with repetition**, running as the installing user
with `InteractiveToken`. It fires at logon and repeats on the interval for as long
as the session lasts — the same scope as a macOS LaunchAgent, and deliberately so:
the interactive token is what gives the job access to your credential helper and
`ssh-agent`.

It does **not** run while logged out. Making it do so means storing credentials
with `-LogonType Password`, which is left out on purpose.

`StartWhenAvailable` is set, so a missed run fires once the machine is back.

## Logging, and no console window

Task Scheduler cannot redirect output, so an obvious implementation wraps the
command in `cmd.exe /c "... >> log 2>&1"`. That works but gives `cmd` a console,
and a black window flashes on every run. The task's `Hidden` setting does not
help — it only hides the task in the Task Scheduler UI, not the window.

Instead the action invokes the interpreter directly and lets `sync.py --log`
open the log file itself:

```
<Command>C:\...\pythonw.exe</Command>
<Arguments>"...\sync.py" "...\repo" --log "...\repo.log"</Arguments>
```

`pythonw.exe` has no console at all, so there is nothing to show — and because
the logging moved into the script, nothing is lost by having no stdout. The
installer defaults to `pythonw.exe` and warns if you override `-Python` with an
interpreter that has a console.

## Verify

```powershell
Get-ScheduledTask -TaskName git-autosync-<repo> | Get-ScheduledTaskInfo
Get-Content -Wait $env:LOCALAPPDATA\git-autosync\git-autosync-<repo>.log
Start-ScheduledTask -TaskName git-autosync-<repo>     # force a run now
```

## Uninstall

```powershell
.\platforms\windows\uninstall.ps1 C:\path\to\repo      # or -Label <name>
```

Add `-KeepLog` to leave the log file behind.

## Notes

- **Python**: the Microsoft Store shim under `WindowsApps` is rejected — it cannot
  be launched by Task Scheduler. Install python.org Python or pass `-Python`.
- **WSL repos**: a repo on `/mnt/c` is reachable from both sides. Install this on
  the Windows side *or* use the Linux backend inside WSL — not both, or the two
  schedulers will race (the lock file prevents corruption but the commits interleave).
- **Credentials**: `git push` uses your credential helper. Confirm `git push` works
  from a plain terminal before installing.
