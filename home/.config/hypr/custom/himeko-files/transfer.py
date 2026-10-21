#!/usr/bin/env python3
"""Copies and moves for Himeko Files (ops.sh transfer copy|move|auto DEST SRC…), as JSON lines on stdout:
  {"scanning": n} … {"total": bytes, "files": n}, then {"progress": {"bytes", "file"}} at most every 150 ms
  {"made": [src, created]} | {"skipped": src} per source; {"failed": {"path", "error"}} per failed item
  {"undo": {"created": path}} | {"undo": {"moved": [from, to]}} as they happen (the app's Undo replays them)
  {"done": true, "failed": n} | {"error": msg} | {"cancelled": true} at the end
auto moves an item when it's on the destination's filesystem and copies it otherwise. Files are written as
.NAME.himeko-part next to their target and renamed when complete; SIGTERM stops after the current block and removes
the part file. Servers (gvfs FUSE) get the data only, no times or modes. HF_SLOW_COPY=SECONDS (tests) slows each block."""
import errno
import json
import os
import shutil
import signal
import stat
import sys
import time

GVFS = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}", "gvfs")
SLOW = float(os.environ.get("HF_SLOW_COPY") or 0)
BLOCK = 1 << 20


class Cancelled(Exception):
    pass


class NoSpace(Exception):
    pass


cancelled = False


def on_term(signum, frame):
    global cancelled
    cancelled = True


signal.signal(signal.SIGTERM, on_term)


def out(obj):
    print(json.dumps(obj, ensure_ascii=False), flush=True)


def remote(path):
    return path == GVFS or path.startswith(GVFS + "/")


def unique(folder, name):
    """A free path in FOLDER for NAME: "name (2).ext" (".tar.gz" kept whole), as ops.sh does."""
    path = os.path.join(folder, name)
    if not os.path.lexists(path):
        return path
    if name.startswith(".") or "." not in name:
        base, ext = name, ""
    else:
        base, ext = name.rsplit(".", 1)
        ext = "." + ext
        if base.endswith(".tar"):
            base, ext = base[:-4], ".tar" + ext
    n = 2
    while os.path.lexists(os.path.join(folder, f"{base} ({n}){ext}")):
        n += 1
    return os.path.join(folder, f"{base} ({n}){ext}")


def size_of(path):
    """(bytes, files) under PATH: regular files only, symlinks not followed."""
    st = os.lstat(path)
    if stat.S_ISDIR(st.st_mode):
        total, files = 0, 0
        for root, dirs, names in os.walk(path):
            for name in names:
                try:
                    s = os.lstat(os.path.join(root, name))
                except OSError:
                    continue
                if stat.S_ISREG(s.st_mode):
                    total += s.st_size
                    files += 1
            if cancelled:
                raise Cancelled
        return total, files
    return (st.st_size, 1) if stat.S_ISREG(st.st_mode) else (0, 0)


class Job:
    def __init__(self, dest):
        self.dest = dest
        self.done = 0
        self.last = 0.0
        self.failed = 0
        self.meta = not remote(dest)

    def tick(self, n, name):
        self.done += n
        now = time.monotonic()
        if now - self.last >= 0.15:
            self.last = now
            out({"progress": {"bytes": self.done, "file": name}})

    def fail(self, path, err):
        self.failed += 1
        out({"failed": {"path": path, "error": err}})


def copy_data(fi, fo, job, name):
    use_range = True
    while True:
        if cancelled:
            raise Cancelled
        try:
            if use_range:
                n = os.copy_file_range(fi.fileno(), fo.fileno(), BLOCK)
            else:
                block = fi.read(BLOCK)
                fo.write(block)
                n = len(block)
        except OSError as e:
            if e.errno == errno.ENOSPC:
                raise NoSpace from e
            if use_range and e.errno in (errno.EXDEV, errno.EINVAL, errno.ENOSYS, errno.EOPNOTSUPP, errno.EBADF):
                use_range = False   # FUSE and some filesystems can't: plain reads and writes
                continue
            raise
        if n == 0:
            return
        job.tick(n, name)
        if SLOW:
            time.sleep(SLOW)


def copy_file(src, dst, job):
    part = os.path.join(os.path.dirname(dst), "." + os.path.basename(dst) + ".himeko-part")
    try:
        with open(src, "rb") as fi, open(part, "wb") as fo:
            copy_data(fi, fo, job, os.path.basename(src))
        if job.meta and not remote(src):
            shutil.copystat(src, part)
        os.rename(part, dst)
    except BaseException:
        try:
            os.unlink(part)
        except OSError:
            pass
        raise


def copy_item(src, dst, job):
    """Copy SRC to DST (which doesn't exist). Returns True when everything under it was copied."""
    st = os.lstat(src)
    if stat.S_ISLNK(st.st_mode):
        os.symlink(os.readlink(src), dst)
        return True
    if stat.S_ISREG(st.st_mode):
        copy_file(src, dst, job)
        return True
    if not stat.S_ISDIR(st.st_mode):
        job.fail(src, "Not a regular file")
        return False
    os.mkdir(dst)
    complete = True
    for name in sorted(os.listdir(src)):
        if cancelled:
            raise Cancelled
        child = os.path.join(src, name)
        try:
            complete = copy_item(child, os.path.join(dst, name), job) and complete
        except (Cancelled, NoSpace):
            raise
        except OSError as e:
            job.fail(child, e.strerror or str(e))
            complete = False
    if job.meta and not remote(src):
        try:
            shutil.copystat(src, dst)
        except OSError:
            pass
    return complete


def remove(path):
    if os.path.isdir(path) and not os.path.islink(path):
        shutil.rmtree(path)
    else:
        os.unlink(path)


def target_for(src, dest, job):
    """Where SRC goes in DEST. Task 2 asks on a taken name; until then a taken name keeps both."""
    return unique(dest, os.path.basename(src))


def transfer(mode, dest, sources):
    dest = os.path.abspath(dest)
    job = Job(dest)
    sources = [os.path.abspath(s).rstrip("/") or "/" for s in sources]
    sizes, files = {}, 0
    for i, src in enumerate(sources):
        try:
            sizes[src] = size_of(src)
        except OSError:
            sizes[src] = (0, 0)
        files += sizes[src][1]
        out({"scanning": files})
    out({"total": sum(b for b, _ in sizes.values()), "files": files})
    dest_dev = os.stat(dest).st_dev
    for src in sources:
        if cancelled:
            raise Cancelled
        if not os.path.lexists(src):
            job.fail(src, "No such file or folder")
            continue
        real_src, real_dest = os.path.realpath(src), os.path.realpath(dest)
        if os.path.isdir(src) and not os.path.islink(src) and (real_dest == real_src or real_dest.startswith(real_src + "/")):
            job.fail(src, "Can't put a folder inside itself")
            continue
        same_folder = os.path.dirname(src) == dest
        move = mode == "move" or (mode == "auto" and os.lstat(src).st_dev == dest_dev)
        if same_folder and (move or mode == "auto"):
            out({"skipped": src})
            continue
        dst = target_for(src, dest, job)
        if dst is None:
            out({"skipped": src})
            continue
        try:
            if move and os.lstat(src).st_dev == dest_dev:
                os.rename(src, dst)
                job.tick(sizes[src][0], os.path.basename(src))
                out({"undo": {"moved": [src, dst]}})
            else:
                complete = copy_item(src, dst, job)
                if move and complete:
                    remove(src)   # only once its copy is whole
                    out({"undo": {"moved": [src, dst]}})
                else:
                    out({"undo": {"created": dst}})
            out({"made": [src, dst]})
        except (Cancelled, NoSpace):
            if os.path.lexists(dst):
                out({"undo": {"created": dst}})   # the part of it that got there
            raise
        except OSError as e:
            job.fail(src, e.strerror or str(e))
    out({"done": True, "failed": job.failed})


def main(argv):
    if len(argv) < 3 or argv[0] not in ("copy", "move", "auto"):
        print("transfer.py: usage: copy|move|auto DEST SRC…", file=sys.stderr)
        sys.exit(1)
    try:
        transfer(argv[0], argv[1], argv[2:])
    except Cancelled:
        out({"cancelled": True})
    except NoSpace:
        out({"error": f"Not enough free space in “{os.path.basename(os.path.abspath(argv[1])) or '/'}”"})
        sys.exit(1)


if __name__ == "__main__":
    main(sys.argv[1:])
