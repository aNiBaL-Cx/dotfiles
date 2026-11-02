#!/usr/bin/env python3
# Names the Herdr agent "<ticket>_<cli>" in a worktree, "<cli>" elsewhere, with a number
# when the name is taken: sq2-1234_claude, sq2-1234_claude2, task-0a_codex, grok2.
# Max 18 chars. The pane label gets "<TICKET> <Model>" for the eye: "SQ2-1234 Opus".
# Usage: herdr-pane-name.sh [claude|codex|grok|...] on SessionStart, hook JSON on stdin.
# Self-check of the naming rule: herdr-pane-name.sh --check
# Never overwrites a name or label it did not write itself (a role rename like
# sq2-1234_dev survives /clear and /compact). Forks so the session is not held while it
# waits for herdr-agent-state.sh to register the agent.
import json, os, re, subprocess, sys, time

pane = os.environ.get("HERDR_PANE_ID")
herdr = os.environ.get("HERDR_BIN_PATH", "herdr")
cli = (sys.argv[1] if len(sys.argv) > 1 else "claude").lower()
if cli != "--check" and (os.environ.get("HERDR_ENV") != "1" or not pane):
    sys.exit(0)

try:
    data = {} if cli == "--check" else json.load(sys.stdin)
except Exception:
    data = {}
if data.get("agent_id"):
    sys.exit(0)

# A second Codex account (CODEX_HOME=~/.codex-personal) is told apart by the first letter
# of its home suffix: codexp. ~/.codex stays plain codex.
tag = cli
home = os.path.basename(os.environ.get("CODEX_HOME", "").rstrip("/"))
if cli == "codex" and home.startswith(".codex-") and len(home) > 7:
    tag = "codex" + home[7].lower()

model = str(data.get("model") or "")
model = next((n for n in ("Opus", "Fable", "Sonnet", "Haiku") if n.lower() in model.lower()), tag.capitalize())


def prefix_for(cwd):
    m = re.search(r"/\.worktrees/([^/]+)", cwd)
    if not m:
        return ""
    folder = m.group(1).lower()
    ticket = re.search(r"(?<![a-z0-9])[a-z]+\d*-\d+(?![a-z0-9])", folder)
    p = ticket.group(0) if ticket else re.sub(r"[^a-z0-9-]", "-", folder)[:10].rstrip("-")
    return ("t" + p if p[0].isdigit() else p)[:10]


if cli == "--check":
    for cwd, want in {
        "/x/.worktrees/SQ2-1234": "sq2-1234",
        "/x/.worktrees/sq1-345/engines": "sq1-345",
        "/x/.worktrees/task-0a": "task-0a",
        "/x/.worktrees/SQ2-1234-canvas-backfill": "sq2-1234",
        "/x/.worktrees/refactor-reports": "refactor-r",
        "/x/.worktrees/1234-fix": "t1234-fix",
        "/x/projects/app": "",
    }.items():
        got = prefix_for(cwd)
        assert got == want, f"{cwd}: {got!r} != {want!r}"
        name = f"{got}_cursor9" if got else "cursor9"
        assert len(name) <= 18 and re.fullmatch(r"[a-z][a-z0-9_-]{0,31}", name), name
    print("ok")
    sys.exit(0)


def run(*args):
    out = subprocess.run([herdr, *args], capture_output=True, text=True).stdout
    try:
        return json.loads(out).get("result") or {}
    except Exception:
        return {}


prefix = prefix_for(str(data.get("cwd") or os.getcwd()))
base = f"{prefix}_{tag}" if prefix else tag

state_file = f"/tmp/herdr-pane-name-{pane.replace(':', '_')}.json"
try:
    state = json.load(open(state_file))
except Exception:
    state = {}

if os.fork():
    sys.exit(0)
os.setsid()
devnull = os.open(os.devnull, os.O_RDWR)
for fd in (0, 1, 2):
    os.dup2(devnull, fd)

agent = None
for _ in range(30):
    agent = run("agent", "get", pane).get("agent")
    if agent:
        break
    time.sleep(0.5)
# Codex runs hooks in its shared app-server daemon, whose HERDR_PANE_ID is the pane
# that started the daemon, not this session's: never rename another CLI's agent.
if not agent or agent.get("agent") != cli:
    sys.exit(0)

current_name = agent.get("name")
old_label = state.get("label")
legacy = re.sub(r"[^a-z0-9_-]", "-", str(old_label or "").lower())
if current_name and current_name not in (state.get("name"), legacy):
    sys.exit(0)

if state.get("base") != base or not state.get("name"):
    taken = {a.get("name") for a in run("agent", "list").get("agents", []) if a.get("pane_id") != pane}
    n = next(k for k in range(1, 100) if (base if k == 1 else f"{base}{k}") not in taken)
    state = {"base": base, "name": base if n == 1 else f"{base}{n}", "n": n}

suffix = "" if state["n"] == 1 else str(state["n"])
label = f"{prefix.upper()} {model}{suffix}" if prefix else f"{model}{suffix}"
pane_label = run("pane", "get", pane).get("pane", {}).get("label")
if not pane_label or pane_label == old_label:
    run("pane", "rename", pane, label)
state["label"] = label

if current_name != state["name"]:
    run("agent", "rename", pane, state["name"])
json.dump(state, open(state_file, "w"))
