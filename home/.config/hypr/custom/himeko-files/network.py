#!/usr/bin/env python3
"""Network locations for Himeko Files through gvfs (called by ops.sh net …).
  mounts                    -> name, address, FUSE path, can-unmount (TAB-separated), one network mount per line
  mount ADDRESS             -> JSON lines: gvfs' questions ({"ask": …}, each answered by one JSON line on stdin),
                               then {"path", "uri"} or {"error"}
  unmount ADDRESS [--force] -> exit 2 when the server is busy
  browse ADDRESS            -> JSON lines: questions, {"item": {name, target, kind}}…, then {"done": true} or {"error"}
  schemes                   -> the URI schemes gvfs supports here
Passwords only ever arrive on stdin. HF_ASK_QUESTION=1 (tests): ask a question before mounting."""
import json
import os
import sys

from gi.repository import Gio, GLib

DEVICES = {"file", "mtp", "gphoto2", "afc"}   # phones and cameras aren't servers
SAVE = {"never": Gio.PasswordSave.NEVER, "session": Gio.PasswordSave.FOR_SESSION, "permanently": Gio.PasswordSave.PERMANENTLY}


def out(obj):
    print(json.dumps(obj), flush=True)


def fail(message):
    out({"error": message})
    sys.exit(1)


def answer():
    """One JSON line from the app; end of input or garbage counts as Cancel."""
    line = sys.stdin.readline()
    try:
        return json.loads(line) if line.strip() else {"cancel": True}
    except ValueError:
        return {"cancel": True}


def split(message):
    title, _, rest = message.partition("\n")
    return title, rest


def operation():
    op = Gio.MountOperation()

    def ask_password(op, message, user, domain, flags):
        f = Gio.AskPasswordFlags
        title, text = split(message)
        out({"ask": "password", "title": title, "message": text, "user": user or "", "domain": domain or "",
             "needUser": bool(flags & f.NEED_USERNAME), "needDomain": bool(flags & f.NEED_DOMAIN),
             "needPassword": bool(flags & f.NEED_PASSWORD), "anonymous": bool(flags & f.ANONYMOUS_SUPPORTED),
             "canSave": bool(flags & f.SAVING_SUPPORTED)})
        a = answer()
        if a.get("cancel"):
            return op.reply(Gio.MountOperationResult.ABORTED)
        op.set_anonymous(bool(a.get("anonymous")))
        op.set_username(a.get("user", ""))
        op.set_domain(a.get("domain", ""))
        op.set_password(a.get("password", ""))
        op.set_password_save(SAVE.get(a.get("save"), Gio.PasswordSave.NEVER))
        op.reply(Gio.MountOperationResult.HANDLED)

    def ask_question(op, message, choices):
        title, text = split(message)
        out({"ask": "question", "title": title, "message": text, "choices": list(choices)})
        a = answer()
        if a.get("cancel") or not isinstance(a.get("choice"), int):
            return op.reply(Gio.MountOperationResult.ABORTED)
        op.set_choice(a["choice"])
        op.reply(Gio.MountOperationResult.HANDLED)

    op.connect("ask-password", ask_password)
    op.connect("ask-question", ask_question)
    return op


def run(start):
    """Run an async gvfs call to its end; returns the GLib.Error, or None."""
    loop, result = GLib.MainLoop(), {}

    def done(source, res):
        try:
            result["value"] = finish(source, res)
        except GLib.Error as e:
            result["error"] = e
        loop.quit()

    finish = start(done)
    loop.run()
    return result.get("error")


def message(err):
    return "Cancelled" if err.matches(Gio.io_error_quark(), Gio.IOErrorEnum.FAILED_HANDLED) else err.message


def mount_enclosing(f):
    def start(done):
        f.mount_enclosing_volume(Gio.MountMountFlags.NONE, operation(), None, done)
        return lambda source, res: source.mount_enclosing_volume_finish(res)
    err = run(start)
    if err and not err.matches(Gio.io_error_quark(), Gio.IOErrorEnum.ALREADY_MOUNTED):
        fail(message(err))


def mount(address):
    if os.environ.get("HF_ASK_QUESTION") == "1":
        out({"ask": "question", "title": "Test question", "message": "Is this a test?", "choices": ["Log In Anyway", "Cancel"]})
        if answer().get("choice") != 0:
            fail("Cancelled")
    f = Gio.File.new_for_uri(address)
    mount_enclosing(f)
    path = f.get_path()
    if not path:
        fail("This location can't be opened as a folder")
    out({"path": path, "uri": f.get_uri()})


def clean(text):
    return " ".join(text.split())


def mounts():
    for m in Gio.VolumeMonitor.get().get_mounts():
        root = m.get_root()
        path = root.get_path()
        if root.get_uri_scheme() in DEVICES or not path:
            continue
        print("\t".join([clean(m.get_name()), root.get_uri(), path, "1" if m.can_unmount() else "0"]))


def unmount(address, force):
    try:
        m = Gio.File.new_for_uri(address).find_enclosing_mount()
    except GLib.Error as e:
        print(e.message, file=sys.stderr)
        sys.exit(1)

    def start(done):
        flags = Gio.MountUnmountFlags.FORCE if force else Gio.MountUnmountFlags.NONE
        m.unmount_with_operation(flags, Gio.MountOperation(), None, done)
        return lambda source, res: source.unmount_with_operation_finish(res)
    err = run(start)
    if err:
        print(err.message, file=sys.stderr)
        sys.exit(2 if err.matches(Gio.io_error_quark(), Gio.IOErrorEnum.BUSY) else 1)


ATTRS = "standard::name,standard::display-name,standard::target-uri,standard::type"


def item(parent, info):
    target = info.get_attribute_string("standard::target-uri") or parent.get_child(info.get_name()).get_uri()
    scheme, _, rest = target.partition("://")
    share = rest.partition("/")[2].strip("/")
    kind = ("computer" if scheme == "smb" and not share
            else "share" if info.get_file_type() in (Gio.FileType.MOUNTABLE, Gio.FileType.SHORTCUT) else "folder")
    return {"item": {"name": clean(info.get_display_name()), "target": target, "kind": kind}}


def browse(address):
    f = Gio.File.new_for_uri(address)
    try:
        children = f.enumerate_children(ATTRS, Gio.FileQueryInfoFlags.NONE, None)
    except GLib.Error as e:
        if not e.matches(Gio.io_error_quark(), Gio.IOErrorEnum.NOT_MOUNTED):
            fail(e.message)
        mount_enclosing(f)
        try:
            children = f.enumerate_children(ATTRS, Gio.FileQueryInfoFlags.NONE, None)
        except GLib.Error as e2:
            fail(e2.message)
    seen = set()
    for info in children:
        seen.add(info.get_name())
        out(item(f, info))
    if address.startswith("network:"):
        # Discovery daemons keep finding computers for a moment: wait for late ones
        loop = GLib.MainLoop()
        monitor = f.monitor_directory(Gio.FileMonitorFlags.NONE, None)

        def changed(monitor, child, other, event):
            if event == Gio.FileMonitorEvent.CREATED and child.get_basename() not in seen:
                seen.add(child.get_basename())
                try:
                    out(item(f, child.query_info(ATTRS, Gio.FileQueryInfoFlags.NONE, None)))
                except GLib.Error:
                    pass
        monitor.connect("changed", changed)
        GLib.timeout_add_seconds(3, loop.quit)
        loop.run()
    out({"done": True})


def main(argv):
    cmd, args = (argv[0], argv[1:]) if argv else ("", [])
    if cmd == "mounts" and not args:
        mounts()
    elif cmd == "mount" and len(args) == 1:
        mount(args[0])
    elif cmd == "unmount" and args and args[1:] in ([], ["--force"]):
        unmount(args[0], args[1:] == ["--force"])
    elif cmd == "browse" and len(args) == 1:
        browse(args[0])
    elif cmd == "schemes" and not args:
        print("\n".join(Gio.Vfs.get_default().get_supported_uri_schemes()))
    else:
        print("network.py: bad arguments: " + " ".join(argv), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main(sys.argv[1:])
