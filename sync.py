#!/usr/bin/env python3
"""Auto-commit & push any git repo. Designed to run on a schedule via launchd."""

import argparse
import fcntl
import hashlib
import os
import socket
import subprocess
import sys
from datetime import datetime
from pathlib import Path


def log(msg: str) -> None:
    print(f"[{datetime.now().isoformat(timespec='seconds')}] {msg}", flush=True)


def run(cmd: list[str], cwd: Path, check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, check=check)


def has_changes(repo: Path) -> bool:
    return bool(run(["git", "status", "--porcelain"], cwd=repo).stdout.strip())


def main() -> int:
    parser = argparse.ArgumentParser(description="Auto-sync a git repo")
    parser.add_argument(
        "repo",
        nargs="?",
        default=os.environ.get("GIT_AUTOSYNC_REPO"),
        help="Path to the git repo (or set GIT_AUTOSYNC_REPO env var)",
    )
    args = parser.parse_args()

    if not args.repo:
        print("error: repo path required (positional arg or GIT_AUTOSYNC_REPO)", file=sys.stderr)
        return 1

    repo = Path(args.repo).expanduser().resolve()
    if not (repo / ".git").exists():
        print(f"error: {repo} is not a git repository", file=sys.stderr)
        return 1

    repo_hash = hashlib.sha1(str(repo).encode()).hexdigest()[:8]
    lock_path = Path(f"/tmp/git-autosync-{repo_hash}.lock")

    lock = open(lock_path, "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        log("another sync is already running; skipping")
        return 0

    try:
        changed = has_changes(repo)
        if changed:
            log("local changes detected; committing")
            run(["git", "add", "-A"], cwd=repo)
            msg = f"auto-sync {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} ({socket.gethostname()})"
            run(["git", "commit", "-m", msg], cwd=repo)

        try:
            run(["git", "pull", "--rebase", "--autostash"], cwd=repo)
        except subprocess.CalledProcessError as e:
            log(f"pull failed: {e.stderr.strip()}")
            return 1

        try:
            push = run(["git", "push"], cwd=repo)
            if push.stdout.strip() or push.stderr.strip():
                log(f"push: {(push.stdout + push.stderr).strip()}")
            elif changed:
                log("pushed")
        except subprocess.CalledProcessError as e:
            log(f"push failed: {e.stderr.strip()}")
            return 1

        return 0
    finally:
        fcntl.flock(lock, fcntl.LOCK_UN)
        lock.close()


if __name__ == "__main__":
    sys.exit(main())
