#!/usr/bin/env python3
"""Auto-commit & push any git repo. Designed to run on a schedule via launchd."""

import argparse
import hashlib
import os
import socket
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path

try:
    from filelock import FileLock, Timeout as _FileLockTimeout
    _LOCK_BACKEND = "filelock"
except ImportError:
    _LOCK_BACKEND = "msvcrt" if sys.platform == "win32" else "fcntl"
    if sys.platform == "win32":
        import msvcrt
    else:
        import fcntl


class ProcessLock:
    """Non-blocking cross-process file lock.

    Uses `filelock` if installed (works everywhere, one import); otherwise falls back to
    stdlib `fcntl` on Unix or `msvcrt` on Windows.
    """

    def __init__(self, path: Path):
        self.path = path
        self._fh = None
        self._flock = None

    def try_acquire(self) -> bool:
        if _LOCK_BACKEND == "filelock":
            self._flock = FileLock(str(self.path))
            try:
                self._flock.acquire(timeout=0)
                return True
            except _FileLockTimeout:
                self._flock = None
                return False

        # Open inside the try: on Windows, writing to a file another process has
        # locked raises PermissionError, which must mean "busy", not "crash".
        # "a+b" rather than "wb" so we never truncate a file someone else holds.
        try:
            self._fh = open(self.path, "a+b")
            self._fh.seek(0)
            if _LOCK_BACKEND == "msvcrt":
                msvcrt.locking(self._fh.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                fcntl.flock(self._fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return True
        except (OSError, BlockingIOError):
            if self._fh is not None:
                self._fh.close()
                self._fh = None
            return False

    def release(self) -> None:
        if self._flock is not None:
            self._flock.release()
            self._flock = None
            return
        if self._fh is not None:
            try:
                if _LOCK_BACKEND == "msvcrt":
                    msvcrt.locking(self._fh.fileno(), msvcrt.LK_UNLCK, 1)
                else:
                    fcntl.flock(self._fh, fcntl.LOCK_UN)
            except OSError:
                pass
            self._fh.close()
            self._fh = None


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
    parser.add_argument(
        "--log",
        default=os.environ.get("GIT_AUTOSYNC_LOG"),
        help=(
            "Append output to this file instead of stdout (or set GIT_AUTOSYNC_LOG). "
            "Lets the scheduler invoke the interpreter directly rather than wrapping "
            "it in a shell for redirection -- on Windows that is what avoids a console "
            "window flashing on every run, since pythonw.exe has no stdout to redirect."
        ),
    )
    args = parser.parse_args()

    if args.log:
        log_path = Path(args.log).expanduser()
        log_path.parent.mkdir(parents=True, exist_ok=True)
        # Line-buffered so a crash still leaves the preceding lines on disk.
        handle = open(log_path, "a", encoding="utf-8", buffering=1)
        sys.stdout = handle
        sys.stderr = handle

    if not args.repo:
        print("error: repo path required (positional arg or GIT_AUTOSYNC_REPO)", file=sys.stderr)
        return 1

    repo = Path(args.repo).expanduser().resolve()
    if not (repo / ".git").exists():
        print(f"error: {repo} is not a git repository", file=sys.stderr)
        return 1

    repo_hash = hashlib.sha1(str(repo).encode()).hexdigest()[:8]
    lock_path = Path(tempfile.gettempdir()) / f"git-autosync-{repo_hash}.lock"

    lock = ProcessLock(lock_path)
    if not lock.try_acquire():
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
        lock.release()


if __name__ == "__main__":
    sys.exit(main())
