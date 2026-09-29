#!/usr/bin/env python3
# Names the Herdr pane and its agent "<ticket> <model> <n>", e.g. "SQ2-1921 Opus 1".
# n is 1, or 1.1, 1.2... when another pane already has the same ticket and model.
# Runs on SessionStart. Resume/clear/compact keep the pane's name.
import json, os, re, subprocess, sys

pane = os.environ.get("HERDR_PANE_ID")
herdr = os.environ.get("HERDR_BIN_PATH", "herdr")
if os.environ.get("HERDR_ENV") != "1" or not pane:
    sys.exit(0)

data = json.load(sys.stdin)
if data.get("agent_id"):
    sys.exit(0)

cwd = data.get("cwd") or os.getcwd()
git = lambda *a: subprocess.run(["git", "-C", cwd, *a], capture_output=True, text=True).stdout.strip()
if "/.worktrees/" in cwd:
    where = cwd.split("/.worktrees/")[1].split("/")[0]
else:
    where = git("branch", "--show-current")
ticket = re.search(r"[A-Za-z]+\d*-\d+", where)
ticket = ticket.group(0).upper() if ticket else os.path.basename(git("rev-parse", "--show-toplevel") or cwd)

model = str(data.get("model") or "")
model = next((n for n in ("Opus", "Fable", "Sonnet", "Haiku") if n.lower() in model.lower()), model)

state_file = f"/tmp/herdr-pane-name-{pane.replace(':', '_')}.json"
try:
    state = json.load(open(state_file))
except Exception:
    state = {}

if state.get("ticket") != ticket or state.get("model") != model:
    panes = json.loads(subprocess.run([herdr, "pane", "list"], capture_output=True, text=True).stdout)["result"]["panes"]
    prefix = f"{ticket} {model} "
    taken = {p["label"][len(prefix):] for p in panes if p["pane_id"] != pane and (p.get("label") or "").startswith(prefix)}
    n = next(c for c in ["1"] + [f"1.{k}" for k in range(1, 100)] if c not in taken)
    state = {"ticket": ticket, "model": model, "n": n}

json.dump(state, open(state_file, "w"))
label = f"{ticket} {model} {state['n']}".replace("  ", " ")
subprocess.run([herdr, "pane", "rename", pane, label], capture_output=True)
# agent names are handles: lowercase, digits, - and _ only, 32 chars max
handle = re.sub(r"[^a-z0-9_-]", "-", label.lower().replace(".", "_"))[:32]
subprocess.run([herdr, "agent", "rename", pane, handle], capture_output=True)
