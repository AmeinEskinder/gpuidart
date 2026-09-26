"""Observe real AT-SPI cache signal signatures from the owned application PID."""
import json
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

process, output = int(sys.argv[1]), sys.argv[2]
report = {"api": "Gio.DBusConnection", "process": process,
          "add": 0, "remove": 0, "invalid": [], "passed": False}
loop = GLib.MainLoop()
expected = {"AddAccessible": "((so)(so)(so)iiassusau)", "RemoveAccessible": "(so)"}
owners = {}

try:
    session = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    address = session.call_sync("org.a11y.Bus", "/org/a11y/bus", "org.a11y.Bus",
                                "GetAddress", None, None, Gio.DBusCallFlags.NONE,
                                3000, None).unpack()[0]
    bus = Gio.DBusConnection.new_for_address_sync(
        address, Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT |
        Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION, None, None)

    def signal(connection, sender, path, interface, name, parameters, _):
        try:
            if sender not in owners:
                owners[sender] = connection.call_sync(
                    "org.freedesktop.DBus", "/org/freedesktop/DBus",
                    "org.freedesktop.DBus", "GetConnectionUnixProcessID",
                    GLib.Variant("(s)", (sender,)), None,
                    Gio.DBusCallFlags.NONE, 3000, None).unpack()[0]
            if owners[sender] != process or name not in expected:
                return
            report["add" if name == "AddAccessible" else "remove"] += 1
            arguments = parameters.n_children()
            signature = (parameters.get_child_value(0).get_type_string()
                         if arguments == 1 else None)
            if arguments != 1 or signature != expected[name]:
                report["invalid"].append({"signal": name, "arguments": arguments,
                                          "signature": parameters.get_type_string()})
                loop.quit()
        except Exception as error:
            report["error"] = str(error)
            loop.quit()

    bus.signal_subscribe(None, "org.a11y.atspi.Cache", None, None, None,
                         Gio.DBusSignalFlags.NONE, signal, None)
    # Ordered round-trip after AddMatch, before announcing readiness.
    bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus",
                  "org.freedesktop.DBus", "GetId", None, None,
                  Gio.DBusCallFlags.NONE, 3000, None)

    def stop(source, condition):
        if condition & GLib.IO_IN:
            sys.stdin.readline()
        loop.quit()
        return False

    def expired():
        report["error"] = "Cache monitor deadline expired"
        loop.quit()
        return False

    GLib.io_add_watch(sys.stdin.fileno(), GLib.IO_IN | GLib.IO_HUP, stop)
    GLib.timeout_add_seconds(60, expired)
    print("ready", flush=True)
    loop.run()
    report["passed"] = (report["add"] > 0 and report["remove"] > 0 and
                        not report["invalid"] and "error" not in report)
except Exception as error:
    report["error"] = str(error)
finally:
    with open(output, "x", encoding="utf-8") as target:
        json.dump(report, target, indent=2)
sys.exit(0 if report["passed"] else 1)
