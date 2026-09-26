"""External AT-SPI client for the SDK's owned test window (X11 CI)."""
import json
import sys

import gi

gi.require_version("Atspi", "2.0")
from gi.repository import Atspi

process = int(sys.argv[1])
operation, name, value = sys.argv[2:5]
identifier = sys.argv[5]
Atspi.init()
Atspi.set_timeout(3000, 10000)
desktop = Atspi.get_desktop(0)
apps = [desktop.get_child_at_index(i) for i in range(desktop.get_child_count())]
apps = [app for app in apps if app.get_process_id() == process]
if len(apps) != 1:
    raise RuntimeError(f"Expected one AT-SPI app for {process}, got {len(apps)}")

elements = []


def visit(element, parent=None):
    if len(elements) >= 4096:
        raise RuntimeError("AT-SPI tree exceeds probe bound")
    index = len(elements)
    elements.append((element, parent))
    for i in range(element.get_child_count()):
        visit(element.get_child_at_index(i), index)


visit(apps[0])
if operation != "query":
    matches = [e for e, _ in elements if (e.get_accessible_id() == identifier if identifier else e.get_name() == name)]
    if len(matches) != 1:
        raise RuntimeError(f"Expected one AT-SPI element named {name}, got {len(matches)}")
    element = matches[0]
    if operation in ("invoke", "toggle"):
        action = element.get_action_iface()
        names = [action.get_action_name(i) for i in range(action.get_n_actions())]
        candidates = [i for i, n in enumerate(names) if n in ("click", "press", "toggle")]
        if len(candidates) != 1:
            raise RuntimeError(f"Expected one click action, got {names}")
        accepted = action.do_action(candidates[0])
    elif operation == "set-value":
        accepted = element.get_editable_text_iface().set_text_contents(value)
    elif operation == "set-range":
        accepted = element.get_value_iface().set_current_value(float(value))
    elif operation == "focus":
        accepted = element.get_component_iface().grab_focus()
    else:
        raise ValueError(operation)
    if not accepted:
        raise RuntimeError(f"AT-SPI rejected {operation}")
    print(json.dumps({"api": "AT-SPI", "operation": operation, "accepted": accepted}))
else:
    nodes = []
    for element, parent in elements:
        state = element.get_state_set()
        node = {
            "parent": parent,
            "name": element.get_name(),
            "role": element.get_role_name(),
            "id": element.get_accessible_id(),
            "enabled": state.contains(Atspi.StateType.ENABLED),
            "focused": state.contains(Atspi.StateType.FOCUSED),
            "focusable": state.contains(Atspi.StateType.FOCUSABLE),
            "checked": state.contains(Atspi.StateType.CHECKED),
            "selected": state.contains(Atspi.StateType.SELECTED),
            "expanded": state.contains(Atspi.StateType.EXPANDED),
            "modal": state.contains(Atspi.StateType.MODAL),
            "interfaces": list(element.get_interfaces()),
        }
        action = element.get_action_iface()
        if action:
            node["actions"] = [action.get_action_name(i) for i in range(action.get_n_actions())]
        text = element.get_text_iface()
        if text:
            node["value"] = text.get_text(0, -1)
        numeric = element.get_value_iface()
        if numeric:
            node.update(number=numeric.get_current_value(), min=numeric.get_minimum_value(),
                        max=numeric.get_maximum_value(), step=numeric.get_minimum_increment())
        nodes.append(node)
    print(json.dumps({"api": "AT-SPI", "process": process, "nodes": nodes}))
