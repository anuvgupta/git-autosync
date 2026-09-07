# git-autosync

Auto-commits and pushes any local git repo on a schedule via macOS launchd.

Every interval (default 5 min) it:
1. Commits any dirty changes with an auto-generated message
2. `git pull --rebase --autostash` to pick up remote changes
3. `git push`

Multiple repos can run independently — each gets its own launchd agent and lock file.

## Install

```sh
chmod +x install.sh uninstall.sh
./install.sh /path/to/your/repo
```

The agent loads immediately and runs every 300 seconds. Logs go to `~/Library/Logs/com.git-autosync.<repo-name>.log`.

### Options

```
./install.sh <repo-path> [options]

  --label LABEL      launchd label         (default: com.git-autosync.<repo-name>)
  --interval SECS    sync interval          (default: 300)
  --log PATH         log file path          (default: ~/Library/Logs/<label>.log)
  --python PATH      python3 interpreter    (default: /usr/bin/python3)
```

### Grant Full Disk Access (if repo is in ~/Documents)

macOS TCC protection blocks launchd-spawned Python from reading `~/Documents`, `~/Desktop`, etc. If your repo lives there:

1. System Settings → Privacy & Security → Full Disk Access
2. Click **+**, press **⌘⇧G**, enter `/usr/bin/python3`, select it
3. Enable the toggle

Or move the repo outside `~/Documents` (e.g. `~/Workspace/`) to avoid the FDA grant entirely.

## Test manually

```sh
python3 /path/to/git-autosync/sync.py /path/to/your/repo
tail -f ~/Library/Logs/com.git-autosync.<repo-name>.log
```

## Uninstall

Pass either the repo path or the launchd label:

```sh
./uninstall.sh /path/to/your/repo
# or
./uninstall.sh com.git-autosync.myrepo
```

## Update after editing install options

```sh
./uninstall.sh /path/to/your/repo
./install.sh /path/to/your/repo [new options]
```

## Notes

- The plist is copied (not symlinked) to `~/Library/LaunchAgents/`; re-run `install.sh` after changing options.
- `git push` uses your existing credential helper — make sure `git push` works from the terminal first.
- A per-repo lock file (keyed by repo path hash) prevents overlapping runs.
- `git pull --rebase --autostash` runs on every cycle, even with no local changes, so you pick up remote edits and recover from a previously failed push.

## Optional: sync on sleep (sleepwatcher)

The interval leaves a gap: closing the lid within 5 minutes of an edit leaves changes local until next wake. To flush on sleep:

```sh
brew install sleepwatcher
brew services start sleepwatcher
```

Create `~/.sleep`:

```sh
#!/bin/sh
/usr/bin/python3 /path/to/git-autosync/sync.py /path/to/your/repo
```

```sh
chmod +x ~/.sleep
```

Note: sleepwatcher gives pre-sleep scripts only a few seconds — a slow push may be cut short. The lock file prevents overlap with the next scheduled run, which will retry.
