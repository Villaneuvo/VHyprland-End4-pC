#!/usr/bin/env python3
"""GNOME's org.gnome.Mutter.IdleMonitor for Hyprland.

Hyprland has no idle-time D-Bus API, so time-tracking apps that ask GNOME report "Input Monitoring"
as missing. This serves GetIdletime() = ms since the last keyboard/mouse/touchpad event, read from
/dev/input (needs the `input` group). Only event timestamps are used; key contents are never parsed.
Run only inside Hyprland: under GNOME, Mutter owns this name itself.
"""
import glob
import os
import select
import threading
import time

from gi.repository import Gio, GLib

BUS_NAME = "org.gnome.Mutter.IdleMonitor"
OBJECT_PATH = "/org/gnome/Mutter/IdleMonitor/Core"
INTROSPECTION = """
<node>
  <interface name="org.gnome.Mutter.IdleMonitor">
    <method name="GetIdletime"><arg type="t" direction="out"/></method>
  </interface>
</node>
"""
HUMAN_INPUT = ("ID_INPUT_KEYBOARD=1", "ID_INPUT_MOUSE=1", "ID_INPUT_TOUCHPAD=1",
               "ID_INPUT_TOUCHSCREEN=1", "ID_INPUT_TABLET=1")

last_activity = time.monotonic()


def is_human_input(path):
    # Skip lid switch, headphone jacks, sensors etc. so they can't keep resetting the idle time
    name = os.path.basename(path)
    # Skip uinput/virtual devices (ydotool and similar): idle time must reflect a person at the machine
    if "/devices/virtual/" in os.path.realpath(f"/sys/class/input/{name}"):
        return False
    try:
        with open(f"/sys/class/input/{name}/dev") as f:
            major_minor = f.read().strip()
        with open(f"/run/udev/data/c{major_minor}") as f:
            props = f.read()
    except OSError:
        return False
    return any(p in props for p in HUMAN_INPUT)


def watch_input():
    global last_activity
    open_fds = {}  # fd -> path
    while True:
        for path in glob.glob("/dev/input/event*"):
            if path not in open_fds.values() and is_human_input(path):
                try:
                    open_fds[os.open(path, os.O_RDONLY | os.O_NONBLOCK)] = path
                except OSError:
                    pass
        # Timeout doubles as the hotplug rescan interval (e.g. a USB mouse plugged in later)
        readable, _, _ = select.select(list(open_fds), [], [], 30)
        for fd in readable:
            try:
                os.read(fd, 4096)
                last_activity = time.monotonic()
            except OSError:  # device unplugged
                os.close(fd)
                del open_fds[fd]


def on_method_call(conn, sender, path, iface, method, params, invocation):
    if method == "GetIdletime":
        idle_ms = int((time.monotonic() - last_activity) * 1000)
        invocation.return_value(GLib.Variant("(t)", (idle_ms,)))


def on_bus_acquired(conn, name):
    node = Gio.DBusNodeInfo.new_for_xml(INTROSPECTION)
    conn.register_object(OBJECT_PATH, node.interfaces[0], on_method_call, None, None)


threading.Thread(target=watch_input, daemon=True).start()
Gio.bus_own_name(Gio.BusType.SESSION, BUS_NAME, Gio.BusNameOwnerFlags.NONE, on_bus_acquired, None, None)
GLib.MainLoop().run()
