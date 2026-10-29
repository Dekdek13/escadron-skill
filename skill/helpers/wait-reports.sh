#!/bin/bash
# Attend que TOUS les rapports d'une mission existent, puis rend la main.
# A lancer par l'orchestrateur avec run_in_background : il est reveille a la fin.
# (notify_when_idle ne marche PAS sur les sessions Remote Control, verifie le 28/09/2026.)
#
# Usage : bash wait-reports.sh "<dossier mission>" REPORT-A.md REPORT-B.md ...
# Garde-fou : abandonne apres 12 h pour ne pas tourner a vide indefiniment.
dir="$1"; shift
deadline=$(( $(date +%s) + 12*3600 ))
while :; do
  missing=0
  for f in "$@"; do [ -f "$dir/$f" ] || missing=$((missing+1)); done
  [ "$missing" -eq 0 ] && { echo "RAPPORTS OK : $*"; exit 0; }
  [ "$(date +%s)" -gt "$deadline" ] && { echo "DELAI DEPASSE : $missing rapport(s) manquant(s)"; exit 1; }
  sleep 60
done
