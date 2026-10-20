#!/usr/bin/env python3
# Names the Herdr pane and its agent "<model>", or "<model><n>" (n >= 2) when other
# panes already have the same model, e.g. "Opus", "Opus2", "Opus3".
# Runs on SessionStart. Resume/clear/compact keep the pane's name.
# Never touches a pane whose label it did not set itself: only an empty label, or the
# label this script wrote last time (kept in the state file), is safe to overwrite.
import json, os, re, subprocess, sys

pane = os.environ.get("HERDR_PANE_ID")
herdr = os.environ.get("HERDR_BIN_PATH", "herdr")
if os.environ.get("HERDR_ENV") != "1" or not pane:
    sys.exit(0)

data = json.load(sys.stdin)
if data.get("agent_id"):
    sys.exit(0)

model = str(data.get("model") or "")
model = next((n for n in ("Opus", "Fable", "Sonnet", "Haiku") if n.lower() in model.lower()), model)

state_file = f"/tmp/herdr-pane-name-{pane.replace(':', '_')}.json"
try:
    state = json.load(open(state_file))
except Exception:
    state = {}

current = json.loads(subprocess.run([herdr, "pane", "get", pane], capture_output=True, text=True).stdout)["result"]["pane"].get("label")
if current and current != state.get("label"):
    sys.exit(0)

if state.get("model") != model or not isinstance(state.get("n"), int):
    panes = json.loads(subprocess.run([herdr, "pane", "list"], capture_output=True, text=True).stdout)["result"]["panes"]
    taken = {int(m.group(1) or 1) for p in panes if p["pane_id"] != pane and (m := re.fullmatch(re.escape(model) + r"(\d*)", p.get("label") or ""))}
    n = next(k for k in range(1, 100) if k not in taken)
    state = {"model": model, "n": n}

label = model if state["n"] == 1 else f"{model}{state['n']}"
state["label"] = label
json.dump(state, open(state_file, "w"))
subprocess.run([herdr, "pane", "rename", pane, label], capture_output=True)
# agent names are handles: lowercase, digits, - and _ only, 32 chars max
handle = re.sub(r"[^a-z0-9_-]", "-", label.lower())[:32]
subprocess.run([herdr, "agent", "rename", pane, handle], capture_output=True)
