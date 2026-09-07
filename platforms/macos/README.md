# git-autosync — macOS

Runs `sync.py` under a launchd user agent. Logs go to `~/Library/Logs/<label>.log`.

## Install

```sh
../../install.sh /path/to/your/repo        # dispatched from repo root
# or, explicit:
./install.sh /path/to/your/repo
```

Loads the agent immediately (`RunAtLoad`) and runs every 300s.

## Grant Full Disk Access (if repo is in ~/Documents)

macOS TCC blocks launchd-spawned Python from reading `~/Documents`, `~/Desktop`, etc. If your repo
lives there:

1. System Settings → Privacy & Security → Full Disk Access
2. Click **+**, press **⌘⇧G**, enter `/usr/bin/python3`, select it
3. Enable the toggle

Or move the repo outside `~/Documents` (e.g. `~/Workspace/`) to skip the FDA grant.

## Uninstall

```sh
./uninstall.sh /path/to/your/repo
# or by label:
./uninstall.sh com.git-autosync.myrepo
```

## Update after changing options

```sh
./uninstall.sh /path/to/your/repo
./install.sh /path/to/your/repo [new options]
```

The plist is copied (not symlinked) to `~/Library/LaunchAgents/`, so re-run to pick up changes.

## Optional: sync on sleep (sleepwatcher)

The interval leaves a gap: closing the lid within 5 min of an edit leaves changes local until next
wake. To flush on sleep:

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

Note: sleepwatcher gives pre-sleep scripts only a few seconds — a slow push may be cut short. The
lock file prevents overlap with the next scheduled run, which will retry.
