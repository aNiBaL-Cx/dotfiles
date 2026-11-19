#!/usr/bin/env python3
# Names the Herdr agent by level colour: "<ticket>-<colour>" in a worktree, "<colour>"
# elsewhere, with a number when the name is taken: sq2-1234-green, sq2-1234-blue2, red.
# The root pane of a worktree workspace is "<ticket>-maestro". Colours follow the levels
# in agents/skills/references/model-levels.md: staff red, senior green, mid blue, junior
# grey. A model whose level depends on effort and resolves to no row falls back to the
# CLI tag: sq2-1234-codex. AGENT_LEVEL=<level|colour> in the env forces the colour.
# The pane label gets "<TICKET> <Model>" for the eye: "SQ2-1234 Opus".
# Usage: herdr-pane-name.sh [claude|codex|grok|...] on SessionStart, hook JSON on stdin.
# Self-check of the naming rules: herdr-pane-name.sh --check
# Never overwrites a name or label it did not write itself (a name given by the skill that
# started the agent survives /clear and /compact). Forks so the session is not held while
# it waits for herdr-agent-state.sh to register the agent.
import json, os, re, subprocess, sys, time, tomllib

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
raw_model = str(data.get("model") or "")
model = next((n for n in ("Opus", "Fable", "Sonnet", "Haiku") if n.lower() in raw_model.lower()), tag.capitalize())

COLOURS = {"staff": "red", "senior": "green", "mid": "blue", "junior": "grey"}
CLAUDE = {"fable": "staff", "opus": "senior", "sonnet": "mid", "haiku": "junior"}
# (model, effort) -> level, main pick then alternative, from model-levels.md. Effort None:
# the model alone decides. The main pick wins a clash (grok-4.6 xhigh is senior, not the
# staff alternative).
LEVELS = {
    "codex": [
        ("gpt-6-astra", None, "staff"), ("gpt-6.1-sol", "medium", "senior"),
        ("gpt-6.1-sol", "low", "mid"), ("gpt-6-luna", None, "junior"),
        ("gpt-6.1-sol", "high", "staff"), ("gpt-6-sol", "medium", "senior"),
        ("gpt-5.6-terra", None, "mid"), ("gpt-5.6-luna", None, "junior"),
    ],
    "grok": [
        ("grok-4.7", "medium", "senior"), ("grok-4.7", None, "staff"),
        ("grok-4.6", "xhigh", "senior"), ("grok-4.6", "medium", "mid"),
        ("grok-4.5", None, "junior"),
    ],
}


def level_for(kind, model_id, effort):
    model_id, effort = (model_id or "").lower(), (effort or "").lower()
    if kind == "claude":
        return next((v for k, v in CLAUDE.items() if k in model_id), None)
    for m, e, level in LEVELS.get(kind, []):
        if m == model_id and e in (None, effort):
            return level
    return None


def launch_args(kind):
    # The CLI process above this hook: its argv carries -m/--model and the effort flags.
    pid = os.getppid()
    for _ in range(8):
        out = subprocess.run(["ps", "-o", "ppid=,args=", "-p", str(pid)], capture_output=True, text=True).stdout.split(None, 1)
        if len(out) < 2:
            return []
        args = out[1].split()
        if os.path.basename(args[0]).startswith(kind) or any(os.path.basename(a) == kind for a in args[:2]):
            return args
        pid = int(out[0])
    return []


def flag(args, *names):
    for i, a in enumerate(args):
        for n in names:
            if a == n and i + 1 < len(args):
                return args[i + 1]
            if a.startswith(n + "="):
                return a.split("=", 1)[1]
    return None


def config(kind):
    path = {
        "codex": os.path.join(os.environ.get("CODEX_HOME") or os.path.expanduser("~/.codex"), "config.toml"),
        "grok": os.path.expanduser("~/.grok/config.toml"),
    }.get(kind)
    try:
        c = tomllib.load(open(path, "rb"))
    except Exception:
        return None, None
    if kind == "codex":
        return c.get("model"), c.get("model_reasoning_effort")
    return c.get("models", {}).get("default"), c.get("models", {}).get("default_reasoning_effort")


def colour_for():
    forced = os.environ.get("AGENT_LEVEL", "").lower()
    if forced in COLOURS.values():
        return forced
    if forced in COLOURS:
        return COLOURS[forced]
    if cli == "claude":
        level = level_for("claude", raw_model, None)
    else:
        args = launch_args(cli)
        cfg_model, cfg_effort = config(cli)
        effort = None
        if cli == "codex":
            sets = [b for a, b in zip(args, args[1:]) if a in ("-c", "--config")]
            effort = next((v.split("=", 1)[1].strip("\"'") for v in sets if v.startswith("model_reasoning_effort=")), None)
        elif cli == "grok":
            effort = flag(args, "--effort")
        level = level_for(cli, raw_model or flag(args, "-m", "--model") or cfg_model, effort or cfg_effort)
    return COLOURS.get(level)


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
        name = f"{got}-maestro9" if got else "maestro9"
        assert len(name) <= 20 and re.fullmatch(r"[a-z][a-z0-9_-]{0,31}", name), name
    for kind, m, e, want in [
        ("claude", "claude-fable-5-1", None, "staff"), ("claude", "claude-opus-5-5[1m]", None, "senior"),
        ("claude", "claude-sonnet-5-5", None, "mid"), ("claude", "claude-haiku-5-5", None, "junior"),
        ("codex", "gpt-6-astra", "high", "staff"), ("codex", "gpt-6.1-sol", "medium", "senior"),
        ("codex", "gpt-6.1-sol", "low", "mid"), ("codex", "gpt-6.1-sol", "xhigh", None),
        ("codex", "gpt-6-luna", "medium", "junior"), ("grok", "grok-4.7", "high", "staff"),
        ("grok", "grok-4.7", "medium", "senior"), ("grok", "grok-4.6", "xhigh", "senior"),
        ("grok", "grok-4.6", "medium", "mid"), ("grok", "grok-4.6", "high", None),
        ("grok", "grok-4.5", "low", "junior"),
    ]:
        got = level_for(kind, m, e)
        assert got == want, f"{kind} {m} {e}: {got!r} != {want!r}"
    assert flag(["codex", "-m", "gpt-6-astra"], "-m", "--model") == "gpt-6-astra"
    assert flag(["grok", "--effort=low"], "--effort") == "low"
    print("ok")
    sys.exit(0)


def run(*args):
    out = subprocess.run([herdr, *args], capture_output=True, text=True).stdout
    try:
        return json.loads(out).get("result") or {}
    except Exception:
        return {}


prefix = prefix_for(str(data.get("cwd") or os.getcwd()))
# Both before the fork: launch_args walks up from this process's parent.
root = False
if prefix:
    ws = run("pane", "get", pane).get("pane", {}).get("workspace_id")
    panes = run("pane", "list", "--workspace", ws).get("panes", []) if ws else []
    root = bool(panes) and panes[0].get("pane_id") == pane
word = "maestro" if root else colour_for() or tag
base = f"{prefix}-{word}" if prefix else word

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
