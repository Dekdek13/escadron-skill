"""Battement de cœur d'un worker d'escadron (29/09/2026).

Les sessions Remote Control n'écrivent pas de transcript .jsonl lisible sur le disque : le chien de garde
(watch-escadron.ps1) ne peut pas voir si un worker avance. Ce hook, appelé seulement chez un worker
(ESCADRON_WORKER=1), écrit son état dans <dossier du rapport>\\.status\\<nom>.json :
  UserPromptSubmit / PostToolUse -> working
  PreToolUse                     -> tool (+ nom de l'outil)
  (Stop est écrit par escadron_stop_gate.py : idle si l'arrêt est accepté, working s'il est refusé)
Toute erreur interne laisse passer (exit 0).
"""
import json
import os
import sys
from datetime import datetime
from pathlib import Path


def write_status(state, tool=""):
    report = os.environ.get("ESCADRON_REPORT", "")
    if not report:
        return
    rp = Path(report)
    name = rp.stem[len("REPORT-"):] if rp.stem.startswith("REPORT-") else rp.stem
    d = rp.parent / ".status"
    d.mkdir(parents=True, exist_ok=True)
    tmp = d / f"{name}.json.tmp"
    tmp.write_text(json.dumps({"state": state, "tool": tool, "at": datetime.now().isoformat(timespec="seconds"),
                               "pid": os.getppid()}), encoding="utf-8")
    os.replace(tmp, d / f"{name}.json")


def noter_prompt(data):
    """02/10/2026 : garde le dernier message recu par la session (Remote Control = pas de transcript
    lisible). guardrails.py s'en sert pour l'exception « c'est l'utilisateur qui le dit »."""
    sid = data.get("session_id") or ""
    if not sid:
        return
    d = Path(os.path.expanduser("~/.claude/hooks/.state"))
    d.mkdir(parents=True, exist_ok=True)
    f = d / f"prompts-{sid}.json"
    try:
        n = json.loads(f.read_text(encoding="utf-8")).get("n", 0)
    except Exception:
        n = 0
    tmp = d / f"prompts-{sid}.json.tmp"
    tmp.write_text(json.dumps({"n": n + 1, "dernier": str(data.get("prompt") or "")[:4000],
                               "at": datetime.now().isoformat(timespec="seconds")}, ensure_ascii=False),
                   encoding="utf-8")
    os.replace(tmp, f)


def main():
    if os.environ.get("ESCADRON_WORKER") != "1":
        return
    data = json.loads(sys.stdin.buffer.read().decode("utf-8") or "{}")
    event = data.get("hook_event_name", "")
    if event == "PreToolUse":
        write_status("tool", data.get("tool_name", ""))
    elif event in ("PostToolUse", "UserPromptSubmit", "PostToolUseFailure"):
        write_status("working")
    if event == "UserPromptSubmit":
        noter_prompt(data)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
