# git-autosync

Auto-commits and pushes any local git repo on a schedule. Each interval (default 5 min) it:

1. Commits any dirty changes with an auto-generated message
2. `git pull --rebase --autostash` to pick up remote changes
3. `git push`

Multiple repos can run independently — each gets its own scheduler unit and lock file.

## Install

```sh
./install.sh /path/to/your/repo
```

The top-level `install.sh` detects the OS and dispatches to the platform implementation under
`platforms/`. Same for `uninstall.sh`. To skip detection, run the platform script directly.

On Windows the dispatcher works from Git Bash (it detects `MINGW*`/`MSYS*`/`CYGWIN*` and hands off
to PowerShell). From PowerShell directly, call `platforms\windows\install.ps1`, which takes
PowerShell-style flags (`-Interval`, `-Label`, ...) rather than the `--flag` form.

### Options (both platforms)

```
./install.sh <repo-path> [options]

  --backend {cron|systemd}   Linux only; default: cron. See platforms/linux/README.md.
  --label LABEL              scheduler unit label
                             macOS default:  com.git-autosync.<repo-name>
                             Linux default:  git-autosync-<repo-name>
  --interval SECS            sync interval          (default: 300)
  --log PATH                 log file path          (see platform README for default)
                             Windows passes this through to `sync.py --log` so the
                             interpreter can run without a shell wrapper; see
                             platforms/windows/README.md.
  --python PATH              python3 interpreter    (default: /usr/bin/python3 on macOS,
                                                     $(command -v python3) on Linux,
                                                     first python.exe on PATH on Windows)
```

## Layout

```
git-autosync/
├── install.sh            <- OS-detecting dispatcher
├── uninstall.sh          <- OS-detecting dispatcher
├── sync.py               <- shared sync logic
└── platforms/
    ├── macos/            <- launchd agent + plist template
    ├── linux/            <- systemd user service + timer templates
    └── windows/          <- Task Scheduler task + XML template (PowerShell)
```

Platform-specific setup notes (Full Disk Access on macOS, `loginctl enable-linger` on Linux, etc.)
live in each platform's own README.

- [platforms/macos/README.md](platforms/macos/README.md)
- [platforms/linux/README.md](platforms/linux/README.md)
- [platforms/windows/README.md](platforms/windows/README.md)

## Test manually

```sh
python3 sync.py /path/to/your/repo
```

## Notes

- `git push` uses your existing credential helper — make sure `git push` works from the terminal first.
- A per-repo lock file (keyed by repo path hash) prevents overlapping runs.
- `git pull --rebase --autostash` runs every cycle, even with no local changes, to pick up remote
  edits and recover from a previously failed push.
