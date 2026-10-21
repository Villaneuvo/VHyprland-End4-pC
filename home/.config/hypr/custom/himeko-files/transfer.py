#!/usr/bin/env python3
"""Copies and moves for Himeko Files (ops.sh transfer copy|move|auto DEST SRC…), as JSON lines on stdout:
  {"scanning": n} … {"total": bytes, "files": n, "allFiles", "move"}, then {"progress": {"bytes", "file"}} at most every 150 ms
  {"ask": "conflict", name, dest, isDir, canTrash, old: {size, mtime}, new: {size, mtime}, more} on a taken name,
    answered by one line on stdin: {"choice": "skip"|"keep"|"replace"|"merge", "all": bool} or {"cancel": true}
  {"made": [src, created]} | {"skipped": src} per source; {"failed": {"path", "error"}} per failed item
  {"undo": {"created": path}} | {"undo": {"moved": [from, to]}} | {"undo": {"replaced": path, "trash": [dir, name]}}
    as they happen (the app's Undo replays them; replaced originals went to that Trash)
  {"done": true, "failed": n} | {"error": msg} | {"cancelled": true} at the end
auto moves an item when it's on the destination's filesystem and copies it otherwise. Files are written as
.NAME.himeko-part next to their target and renamed when complete; SIGTERM stops after the current block and removes
the part file. Replace sends the old item to Trash where there is one, and overwrites where there isn't (servers).
Servers (gvfs FUSE) get the data only, no times or modes. HF_SLOW_COPY=SECONDS (tests) slows each block.
  transfer.py untrash TRASHDIR NAME  -> puts a trashed item back where it came from (Undo of a Replace)"""
import errno
import json
import os
import shutil
import signal
import stat
import sys
import time
from urllib.parse import unquote

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
            if SLOW:
                time.sleep(SLOW)   # tests: a big tree's walk
        return total, files
    return (st.st_size, 1) if stat.S_ISREG(st.st_mode) else (0, 0)


def answer():
    """One JSON line from the app; end of input or garbage counts as Cancel."""
    line = sys.stdin.readline()
    try:
        return json.loads(line) if line.strip() else {"cancel": True}
    except ValueError:
        return {"cancel": True}


def can_trash(path):
    try:
        from gi.repository import Gio
        info = Gio.File.new_for_path(path).query_info("access::can-trash", Gio.FileQueryInfoFlags.NOFOLLOW_SYMLINKS, None)
        return info.get_attribute_boolean("access::can-trash")
    except Exception:
        return False


def dev_of(path):
    """The filesystem PATH is (or would be) on: its nearest existing ancestor's."""
    while not os.path.lexists(path):
        path = os.path.dirname(path)
    return os.stat(path).st_dev


def trash_dir_for(path):
    """The Trash GLib uses for PATH: the home one on its filesystem, else $topdir/.Trash-$UID."""
    home = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"), "Trash")
    dev = os.lstat(os.path.dirname(path)).st_dev
    if dev_of(home) == dev:
        return home, None
    top = os.path.dirname(path)
    while top != "/" and os.lstat(os.path.dirname(top)).st_dev == dev:
        top = os.path.dirname(top)
    return os.path.join(top, f".Trash-{os.getuid()}"), top


def trash(path):
    """Send PATH to Trash; returns (trash dir, name inside it) for Undo, the name None if it can't be found.
    Raises only when the item is still in place."""
    from gi.repository import Gio
    folder, top = trash_dir_for(path)
    info_dir = os.path.join(folder, "info")
    # GLib names a second "a.txt" "a.2.txt": the entry is the one that wasn't there before, with our Path=
    before = set(os.listdir(info_dir)) if os.path.isdir(info_dir) else set()
    Gio.File.new_for_path(path).trash(None)
    want = path if top is None else os.path.relpath(path, top)
    try:
        new = [i for i in os.listdir(info_dir) if i.endswith(".trashinfo") and i not in before]
    except OSError:
        return folder, None   # trashed somewhere we didn't expect: the copy goes on, Undo can't bring it back
    for info in new:
        with open(os.path.join(info_dir, info), encoding="utf-8", errors="replace") as f:
            stored = next((unquote(l[5:].strip()) for l in f if l.startswith("Path=")), "")
        if stored == want:
            return folder, info[:-len(".trashinfo")]
    return folder, None


def untrash(folder, name):
    info = os.path.join(folder, "info", name + ".trashinfo")
    with open(info, encoding="utf-8", errors="replace") as f:
        stored = next((unquote(l[5:].strip()) for l in f if l.startswith("Path=")), "")
    target = stored if stored.startswith("/") else os.path.join(os.path.dirname(folder), stored)
    if os.path.lexists(target):
        print(f"transfer.py: “{target}” exists, not restoring over it", file=sys.stderr)
        sys.exit(1)
    os.rename(os.path.join(folder, "files", name), target)
    os.unlink(info)


class Job:
    def __init__(self, dest, move_mode):
        self.dest = dest
        self.done = 0
        self.last = 0.0
        self.failed = 0
        self.meta = not remote(dest)
        self.mode = move_mode       # "copy" | "move" | "auto"
        self.dest_dev = os.stat(dest).st_dev
        self.all = {}               # "file"|"folder" -> the choice Apply to All set

    def choose(self, src, old, more):
        """Ask what to do about OLD, which has SRC's name: skip | keep | replace | merge (folders)."""
        folder = os.path.isdir(src) and not os.path.islink(src) and os.path.isdir(old) and not os.path.islink(old)
        kind = "folder" if folder else "file"
        if kind in self.all:
            return self.all[kind]
        so, sn = os.lstat(old), os.lstat(src)
        is_dir = lambda p: os.path.isdir(p) and not os.path.islink(p)
        out({"ask": "conflict", "name": os.path.basename(src), "dest": os.path.dirname(old), "isDir": folder,
             "oldIsDir": is_dir(old), "newIsDir": is_dir(src),
             "canTrash": can_trash(old), "old": {"size": so.st_size, "mtime": int(so.st_mtime)},
             "new": {"size": sn.st_size, "mtime": int(sn.st_mtime)}, "more": bool(more)})
        a = answer()
        if a.get("cancel"):
            raise Cancelled
        choice = a.get("choice")
        if choice not in (("skip", "keep", "merge") if folder else ("skip", "keep", "replace")):
            choice = "keep"   # the one that never loses anything
        if a.get("all"):
            self.all[kind] = choice
        return choice

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


def settle(part, dst):
    """Put PART at DST without ever overwriting: a name taken meanwhile (another job) gets " (2)". Returns the path."""
    while True:
        if os.path.lexists(dst):
            dst = unique(os.path.dirname(dst), os.path.basename(dst))
        try:
            os.link(part, dst)
        except FileExistsError:
            continue
        except OSError:
            os.rename(part, dst)   # no hard links here (FUSE): a rename right after the check
            return dst
        os.unlink(part)
        return dst


def copy_file(src, dst, job):
    """Copy SRC's data to DST through a hidden part file; returns where it ended up."""
    part = os.path.join(os.path.dirname(dst), f".{os.path.basename(dst)}.{os.getpid()}.himeko-part")
    try:
        with open(src, "rb") as fi, open(part, "wb") as fo:
            copy_data(fi, fo, job, os.path.basename(src))
        if job.meta and not remote(src):
            shutil.copystat(src, part)
        return settle(part, dst)
    except BaseException:
        try:
            os.unlink(part)
        except OSError:
            pass
        raise


def copy_item(src, dst, job):
    """Copy SRC to DST (which doesn't exist). Returns (everything under it was copied, where it ended up)."""
    st = os.lstat(src)
    if stat.S_ISLNK(st.st_mode):
        os.symlink(os.readlink(src), dst)
        return True, dst
    if stat.S_ISREG(st.st_mode):
        return True, copy_file(src, dst, job)
    if not stat.S_ISDIR(st.st_mode):
        job.fail(src, "Not a regular file")
        return False, dst
    os.mkdir(dst)
    complete = True
    for name in sorted(os.listdir(src)):
        if cancelled:
            raise Cancelled
        child = os.path.join(src, name)
        try:
            complete = copy_item(child, os.path.join(dst, name), job)[0] and complete
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
    return complete, dst


def remove(path):
    if os.path.isdir(path) and not os.path.islink(path):
        shutil.rmtree(path)
    else:
        os.unlink(path)


def place(src, dest, job, more):
    """Put SRC into the folder DEST, asking when its name is taken. Returns the path it went to, or None (skipped)."""
    dst = os.path.join(dest, os.path.basename(src))
    if os.path.lexists(dst):
        if os.path.dirname(src) == dest:
            dst = unique(dest, os.path.basename(src))   # a copy into its own folder is a duplicate, not a clash
        else:
            choice = job.choose(src, dst, more)
            if choice == "skip":
                return None
            if choice == "keep":
                dst = unique(dest, os.path.basename(src))
            elif choice == "merge":
                return merge(src, dst, job, more)
            elif choice == "replace":
                if can_trash(dst):
                    try:
                        folder, name = trash(dst)
                    except Exception as e:   # couldn't trash it: leave it alone rather than overwrite it
                        job.fail(src, f"Couldn't move “{os.path.basename(dst)}” to Trash: {getattr(e, 'message', e)}")
                        return None
                    if name:
                        out({"undo": {"replaced": dst, "trash": [folder, name]}})
                else:
                    remove(dst)   # no Trash here (a server): the dialog said it would be overwritten
    move = job.mode == "move" or (job.mode == "auto" and os.lstat(src).st_dev == job.dest_dev)
    if move and os.lstat(src).st_dev == job.dest_dev:
        os.rename(src, dst)
        out({"undo": {"moved": [src, dst]}})   # first: a cancel must never fall between the move and its record
        job.tick(job.sizes.get(src, (0, 0))[0], os.path.basename(src))
        return dst
    try:
        complete, dst = copy_item(src, dst, job)
    except (Cancelled, NoSpace):
        if os.path.lexists(dst):
            out({"undo": {"created": dst}})   # the part of it that got there
        raise
    if move and complete:
        remove(src)   # only once its copy is whole
        out({"undo": {"moved": [src, dst]}})
    else:
        out({"undo": {"created": dst}})
    return dst


def merge(src, dst, job, more):
    """Copy or move SRC's contents into the existing folder DST, asking again for each clash inside."""
    names = sorted(os.listdir(src))
    for i, name in enumerate(names):
        if cancelled:
            raise Cancelled
        child = os.path.join(src, name)
        try:
            place(child, dst, job, more or i < len(names) - 1)
        except (Cancelled, NoSpace):
            raise
        except OSError as e:
            job.fail(child, e.strerror or str(e))
    if job.mode != "copy":
        try:
            os.rmdir(src)   # a move leaves the source folder only if something stayed behind
        except OSError:
            pass
    return dst


def transfer(mode, dest, sources):
    dest = os.path.abspath(dest)
    job = Job(dest, mode)
    job.sizes = {}
    sources = [os.path.abspath(s).rstrip("/") or "/" for s in sources]
    sizes, files = {}, 0
    for i, src in enumerate(sources):
        try:
            sizes[src] = size_of(src)
        except OSError:
            sizes[src] = (0, 0)
        files += sizes[src][1]
        out({"scanning": files})
    folders = [s for s in sources if os.path.isdir(s) and not os.path.islink(s)]
    moves = mode == "move" or (mode == "auto" and all(os.path.lexists(s) and os.lstat(s).st_dev == os.stat(dest).st_dev for s in sources))
    job.sizes = sizes
    out({"total": sum(b for b, _ in sizes.values()), "files": files, "allFiles": not folders, "move": moves})
    dest_dev = job.dest_dev
    for i, src in enumerate(sources):
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
        try:
            dst = place(src, dest, job, i < len(sources) - 1)
            out({"made": [src, dst]} if dst else {"skipped": src})
        except (Cancelled, NoSpace):
            raise
        except OSError as e:
            job.fail(src, e.strerror or str(e))
    out({"done": True, "failed": job.failed})


def main(argv):
    if len(argv) == 3 and argv[0] == "untrash":
        return untrash(argv[1], argv[2])
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
