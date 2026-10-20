#!/usr/bin/env python3
"""Recent files, stars and pinned folders for Himeko Files (called by ops.sh; TAB-separated output).
  recent list [MAX]            -> path isDir size mtime used, newest first (GTK's recently-used.xbel)
  recent add|remove PATH
  starred list                 -> path isDir size mtime (existing only)
  starred add|remove PATH...
  bookmarks pin PATH [LABEL] | unpin PATH | rename PATH LABEL | move PATH -1|1   (GTK's bookmarks file)
  moved OLD NEW                -> stars, pins and recent entries follow a rename/move
Env: HF_RECENT, HF_STARRED, XDG_CONFIG_HOME. Writes: temp file next to the real target + rename, mode kept."""
import fcntl
import os
import sys
import tempfile
import time

from gi.repository import GLib

HOME = os.path.expanduser("~")
RECENT = os.environ.get("HF_RECENT") or os.path.join(HOME, ".local/share/recently-used.xbel")
STARRED = os.environ.get("HF_STARRED") or os.path.join(HOME, ".local/state/himeko-files/starred")
BOOKMARKS = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.join(HOME, ".config"), "gtk-3.0/bookmarks")


def fail(msg):
    print(f"places: {msg}", file=sys.stderr)
    sys.exit(1)


def read(path):
    try:
        with open(path, "rb") as f:
            return f.read()
    except FileNotFoundError:
        return b""


def atomic_write(path, data, new_mode=None):
    """Write through a symlink to its target, keep the old mode (GTK's files are shared with other apps)."""
    real = os.path.realpath(path)
    folder = os.path.dirname(real)
    os.makedirs(folder, exist_ok=True)
    try:
        mode = os.stat(real).st_mode & 0o7777
    except FileNotFoundError:
        umask = os.umask(0)
        os.umask(umask)
        mode = new_mode if new_mode is not None else 0o666 & ~umask
    fd, tmp = tempfile.mkstemp(dir=folder, prefix="." + os.path.basename(real) + ".")
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data if isinstance(data, bytes) else data.encode())
        os.chmod(tmp, mode)
        os.replace(tmp, real)
    except BaseException:
        os.unlink(tmp)
        raise


def uri_of(path):
    return GLib.filename_to_uri(os.path.abspath(path), None)


def path_of(uri):
    """Local path of a file:// URI, else None."""
    if not uri.startswith("file://"):
        return None
    try:
        return GLib.filename_from_uri(uri)[0]
    except GLib.Error:
        return None


def under(path, old):
    """NEW-relative remainder when PATH is OLD or inside it, else None."""
    if path == old:
        return ""
    return path[len(old):] if path.startswith(old + "/") else None


def row(path, *extra):
    """TSV line for an existing path (None when gone, or when the name can't be one TSV field)."""
    if "\n" in path or "\t" in path:
        return None
    try:
        st = os.stat(path)
    except OSError:
        return None
    is_dir = 1 if os.path.isdir(path) else 0
    return "\t".join(map(str, (path, is_dir, st.st_size, int(st.st_mtime), *extra)))


# ---- recent (GLib's own parser and writer: other apps read this file) ----

def load_recent():
    bf = GLib.BookmarkFile()
    data = read(RECENT)
    if data.strip():
        bf.load_from_data(data)
    return bf


def save_recent(bf):
    atomic_write(RECENT, bf.to_data(), 0o600)


def recent_list(limit=300):
    bf = load_recent()
    entries = []
    for uri in bf.get_uris():
        path = path_of(uri)
        if path is None:
            continue
        stamp = bf.get_modified_date_time(uri) or bf.get_visited_date_time(uri)
        entries.append((stamp.to_unix() if stamp else 0, path))
    entries.sort(key=lambda e: e[0], reverse=True)
    out = []
    for used, path in entries:
        if len(out) >= limit:
            break
        line = row(path, used)
        if line:
            out.append(line)
    return out


def recent_add(path):
    from gi.repository import Gio
    path = os.path.abspath(path)
    try:
        mime = Gio.File.new_for_path(path).query_info("standard::content-type", 0, None).get_content_type()
    except GLib.Error:
        fail(f"can't read {path}")
    bf = load_recent()
    uri = uri_of(path)
    bf.set_mime_type(uri, mime)
    bf.add_application(uri, "Himeko Files", "himeko-files %u")
    bf.set_modified_date_time(uri, GLib.DateTime.new_now_utc())
    save_recent(bf)


def recent_remove(path):
    bf = load_recent()
    try:
        bf.remove_item(uri_of(path))
    except GLib.Error:
        return
    save_recent(bf)


# ---- starred (ours: one absolute path per line) ----

def load_starred():
    return [line for line in read(STARRED).decode(errors="surrogateescape").split("\n") if line]


def save_starred(paths):
    atomic_write(STARRED, "".join(p + "\n" for p in paths).encode(errors="surrogateescape"))


def starred_add(paths):
    have = load_starred()
    new = [p for p in dict.fromkeys(os.path.abspath(p) for p in paths) if p not in have and "\n" not in p]
    if new:
        save_starred(have + new)


def starred_remove(paths):
    gone = {os.path.abspath(p) for p in paths}
    have = load_starred()
    keep = [p for p in have if p not in gone]
    if keep != have:
        save_starred(keep)


# ---- bookmarks (GTK's: "URI[ label]" per line; other schemes kept as they are) ----

def load_bookmarks():
    return [line for line in read(BOOKMARKS).decode(errors="surrogateescape").splitlines() if line.strip()]


def save_bookmarks(lines):
    atomic_write(BOOKMARKS, "".join(line + "\n" for line in lines).encode(errors="surrogateescape"))


def line_path(line):
    return path_of(line.partition(" ")[0])


def find_pin(lines, path):
    path = os.path.abspath(path)
    return next((i for i, line in enumerate(lines) if line_path(line) == path), -1)


def pin_line(path, label):
    return uri_of(path) + (" " + label if label else "")


def bookmarks(op, args):
    if not args:
        fail("missing PATH")
    lines = load_bookmarks()
    i = find_pin(lines, args[0])
    if op == "pin":
        if i < 0:
            save_bookmarks(lines + [pin_line(args[0], args[1] if len(args) > 1 else "")])
        return
    if i < 0:
        fail(f"not pinned: {args[0]}")
    if op == "unpin":
        del lines[i]
    elif op == "rename" and len(args) == 2:
        lines[i] = pin_line(args[0], args[1].replace("\n", " ").strip())
    elif op == "move" and len(args) == 2 and args[1] in ("-1", "1"):
        d = int(args[1])
        # Swap with the next pinned folder that way; other schemes (not shown) stay where they are
        j = i + d
        while 0 <= j < len(lines) and line_path(lines[j]) is None:
            j += d
        if not 0 <= j < len(lines):
            return
        lines[i], lines[j] = lines[j], lines[i]
    else:
        fail(f"bad arguments for bookmarks {op}")
    save_bookmarks(lines)


# ---- a rename or move done in the app ----

def moved(old, new):
    old, new = os.path.abspath(old), os.path.abspath(new)
    stars = load_starred()
    moved_stars = [new + rest if (rest := under(p, old)) is not None else p for p in stars]
    if moved_stars != stars:
        save_starred(moved_stars)
    lines = load_bookmarks()
    moved_lines = []
    for line in lines:
        path = line_path(line)
        rest = under(path, old) if path else None
        moved_lines.append(line if rest is None else pin_line(new + rest, line.partition(" ")[2]))
    if moved_lines != lines:
        save_bookmarks(moved_lines)
    bf = load_recent()
    changed = False
    for uri in bf.get_uris():
        path = path_of(uri)
        rest = under(path, old) if path else None
        if rest is not None:
            bf.move_item(uri, uri_of(new + rest))
            changed = True
    if changed:
        save_recent(bf)


def lines(rows):
    sys.stdout.write("".join(r + "\n" for r in rows))


def main(argv):
    if not argv:
        fail("usage: see places.py")
    what, args = argv[0], argv[1:]
    op = args[0] if args else ""
    if op != "list":
        # Every write is read-change-write: ours run one at a time (several files opened at once, two windows)
        lock = open(os.path.join(os.environ.get("XDG_RUNTIME_DIR") or tempfile.gettempdir(), "himeko-files-places.lock"), "a")
        fcntl.flock(lock, fcntl.LOCK_EX)
    if what == "recent" and op == "list":
        lines(recent_list(int(args[1]) if len(args) > 1 else 300))
    elif what == "recent" and op in ("add", "remove") and len(args) == 2:
        (recent_add if op == "add" else recent_remove)(args[1])
    elif what == "starred" and op == "list":
        lines(filter(None, map(row, load_starred())))
    elif what == "starred" and op in ("add", "remove") and len(args) > 1:
        (starred_add if op == "add" else starred_remove)(args[1:])
    elif what == "bookmarks" and op in ("pin", "unpin", "rename", "move"):
        bookmarks(op, args[1:])
    elif what == "moved" and len(args) == 2:
        moved(*args)
    else:
        fail(f"bad arguments: {' '.join(argv)}")


if __name__ == "__main__":
    main(sys.argv[1:])
