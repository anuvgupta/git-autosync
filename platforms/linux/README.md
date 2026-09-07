# git-autosync — Linux

Two backends: **cron** (default) or **systemd user timer** (opt-in with `--backend systemd`).
Logs go to `~/.local/state/git-autosync/<label>.log` in both cases.

## Install

```sh
./install.sh /path/to/your/repo                       # cron (default)
./install.sh /path/to/your/repo --backend systemd     # systemd user timer
```

Default label: `git-autosync-<repo-name>`.

## Which backend?

|                             | cron                       | systemd user timer                                      |
| --------------------------- | -------------------------- | ------------------------------------------------------- |
| Runs when logged out        | yes                        | only if `sudo loginctl enable-linger $USER`             |
| Requires                    | `cron`/`crond`             | `systemd`                                               |
| Log rotation                | you manage the file        | journald handles (also writes to the log file)          |
| Status query                | grep the log               | `systemctl --user status <label>.timer`                 |
| Interval granularity        | 1 min, must divide 60      | any seconds value                                       |
| Ships on Unraid?            | yes (dcron)                | no                                                      |

**Default is cron** because it's simpler and doesn't need lingering. Use systemd if you want
`journalctl`, per-unit status, or an interval that isn't a clean divisor of 60 minutes.

## cron gotchas

- **Minimal environment.** cron runs jobs with a bare `PATH` and no `SSH_AUTH_SOCK`. If `git push`
  relies on ssh-agent (passphrase-protected key), the cron job will fail silently. Use a
  passphraseless SSH deploy key, or a credential helper that doesn't need a live agent.
- **Interval must divide 60.** cron's `*/N` expression only fires cleanly for N ∈
  {1, 2, 3, 4, 5, 6, 10, 12, 15, 20, 30}, plus 60. Anything else double-fires at the hour boundary.
  The installer rejects other values — use `--backend systemd` if you need arbitrary seconds.

## systemd user gotchas

- **Timers stop at logout** unless you enable lingering:

  ```sh
  sudo loginctl enable-linger $USER
  ```

- **Requires systemd.** Rules out Unraid, minimal Alpine containers, etc. — those need cron.

## Operate

**cron:**

```sh
crontab -l | grep git-autosync
tail -f ~/.local/state/git-autosync/git-autosync-<repo>.log

# fire once by hand
python3 /path/to/git-autosync/sync.py /path/to/your/repo
```

**systemd:**

```sh
systemctl --user list-timers | grep git-autosync
systemctl --user status git-autosync-<repo>.timer
journalctl --user -u git-autosync-<repo>.service -f

# fire once by hand
systemctl --user start git-autosync-<repo>.service
```

## Uninstall

```sh
./uninstall.sh /path/to/your/repo
# or by label:
./uninstall.sh git-autosync-myrepo
```

Removes whichever backend is installed (cron entry, systemd units, or both).

## Update after changing options

```sh
./uninstall.sh /path/to/your/repo
./install.sh /path/to/your/repo [new options]
```
