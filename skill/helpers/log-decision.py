"""Journal de décisions d'un worker d'escadron (marche 2 du plan Lauren Tan, 01/10/2026).

Une ligne par décision dans <dossier mission>\\decisions-<Nom>.tsv :
  heure  phase  decision  raison  preuve  resultat
Le chemin se déduit de ESCADRON_REPORT (posé par launch-escadron.ps1 -Brief), comme le battement de cœur :
le worker n'a rien à deviner. Les tabulations et retours à la ligne des champs sont aplatis, sinon le TSV casse.

Usage (dans le worktree du worker) :
  py <helpers>\\log-decision.py --phase build --decision "garder X" --raison "..." --preuve "tests 12/12" --resultat garde
  py <helpers>\\log-decision.py --show          (affiche le journal)
Hors worker (pas de ESCADRON_REPORT) : --file <chemin.tsv> obligatoire.
Exit 0 si la ligne est écrite, 2 si aucun journal n'est trouvable, 3 si un champ obligatoire est vide.
"""
import argparse, os, sys
from datetime import datetime
from pathlib import Path

HEADER = ["heure", "phase", "decision", "raison", "preuve", "resultat"]
PHASES = {"cadrage", "lecture", "repro", "build", "preuve", "nettoyage", "rapport", "blocage"}


def journal_path(explicit):
    if explicit:
        return Path(explicit)
    report = os.environ.get("ESCADRON_REPORT", "")
    if not report:
        return None
    rp = Path(report)
    name = rp.stem[len("REPORT-"):] if rp.stem.startswith("REPORT-") else rp.stem
    return rp.parent / f"decisions-{name}.tsv"


def flat(s):
    return " ".join(str(s).replace("\t", " ").split())


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser()
    ap.add_argument("--phase", choices=sorted(PHASES))
    ap.add_argument("--decision")
    ap.add_argument("--raison")
    ap.add_argument("--preuve", default="")
    ap.add_argument("--resultat", default="")
    ap.add_argument("--file")
    ap.add_argument("--show", action="store_true")
    a = ap.parse_args()
    p = journal_path(a.file)
    if p is None:
        print("Pas de journal : ESCADRON_REPORT absent, passe --file <chemin.tsv>"); sys.exit(2)
    if a.show:
        print(p.read_text(encoding="utf-8") if p.exists() else f"(vide) {p}"); return
    if not (a.phase and a.decision and a.raison):
        print("--phase, --decision et --raison sont obligatoires"); sys.exit(3)
    new = not p.exists() or p.stat().st_size == 0
    p.parent.mkdir(parents=True, exist_ok=True)
    with open(p, "a", encoding="utf-8", newline="\n") as fh:
        if new:
            fh.write("\t".join(HEADER) + "\n")
        fh.write("\t".join(flat(x) for x in (datetime.now().strftime("%Y-%m-%d %H:%M:%S"), a.phase, a.decision,
                                              a.raison, a.preuve, a.resultat)) + "\n")
    print(f"DECISION {p}")


if __name__ == "__main__":
    main()
