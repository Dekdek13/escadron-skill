"""Portail de fin d'un worker d'escadron (hook Stop). Ajouté le 29/09/2026.

Un worker (ESCADRON_WORKER=1) ne peut pas finir son tour tant que son rapport (ESCADRON_REPORT)
n'existe pas : le hook refuse l'arrêt et lui dit de continuer. C'est ce qui évite qu'une session
« s'endorme » en attendant une réponse que personne ne donnera (l'utilisateur n'est pas dans la boucle).
Condition de sortie de la boucle : au plus ESCADRON_GATE_MAX refus (défaut 3) par session,
ensuite on laisse s'arrêter et le chien de garde de l'orchestrateur prend le relais.
Toute erreur interne laisse passer (exit 0).
"""
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from escadron_heartbeat import write_status  # noqa: E402

STATE = Path.home() / ".claude" / "hooks" / ".state" / "escadron-gate"


def main():
    if os.environ.get("ESCADRON_WORKER") != "1":
        return
    report = os.environ.get("ESCADRON_REPORT", "")
    import re as _re
    _head = ""
    if report and Path(report).is_file():
        try:
            _head = " ".join(Path(report).read_text(encoding="utf-8", errors="ignore").splitlines()[:8])
        except Exception:
            _head = ""
    # 29/09/2026 : un rapport marque provisoire en tete ne vaut pas fin de mission.
    _provisional = bool(_re.search(r"(?i)provisoire|en cours de finalisation|statut.{0,40}en cours|work in progress", _head))
    # 01/10/2026 (marche 2) : avec ESCADRON_DECISIONS=1, un rapport sans journal de décisions ne vaut pas fin.
    _journal = ""
    if report and os.environ.get("ESCADRON_DECISIONS") == "1":
        _rp = Path(report)
        _name = _rp.stem[len("REPORT-"):] if _rp.stem.startswith("REPORT-") else _rp.stem
        _tsv = _rp.parent / f"decisions-{_name}.tsv"
        _lines = _tsv.read_text(encoding="utf-8", errors="ignore").splitlines()[1:] if _tsv.is_file() else []
        if not any(l.strip() for l in _lines):
            _journal = str(_tsv)
    if report and Path(report).is_file() and Path(report).stat().st_size > 0 and not _provisional and not _journal:
        write_status("done")
        return
    data = json.loads(sys.stdin.buffer.read().decode("utf-8") or "{}")
    session = data.get("session_id") or "unknown"
    limit = int(os.environ.get("ESCADRON_GATE_MAX", "3"))
    STATE.mkdir(parents=True, exist_ok=True)
    counter = STATE / f"{session}.txt"
    count = int(counter.read_text()) if counter.is_file() else 0
    if count >= limit:
        write_status("idle")
        return
    counter.write_text(str(count + 1))
    reason = (
        f"[portail escadron {count + 1}/{limit}] Ton rapport n'existe pas encore ({report or 'chemin inconnu'}). "
        "Personne ne va te répondre : l'utilisateur n'est pas dans la boucle. Ne pose pas de question, n'attends pas. "
        "Continue ton lot jusqu'à sa condition de fin, puis écris ton rapport à ce chemin exact. "
        "Si tu es réellement bloqué, écris quand même le rapport avec le verdict « blocked », la raison exacte "
        "et ce que tu as essayé. Une décision qui revient à l'utilisateur va dans la section « Décisions pour l'utilisateur » "
        "du rapport, sans t'arrêter."
    )
    if _journal and report and Path(report).is_file():
        reason = (
            f"[portail escadron {count + 1}/{limit}] Ton rapport existe mais ton journal de décisions est vide ({_journal}). "
            "Ajoute une ligne par décision prise pendant le lot avec log-decision.py (phase, décision, raison, preuve, "
            "résultat), en relisant ton historique et git log. N'invente aucune preuve : si une décision n'a pas de "
            "preuve, écris « aucune »."
        )
    write_status("working")
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stdout.write(json.dumps({"decision": "block", "reason": reason}, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
