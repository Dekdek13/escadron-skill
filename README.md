# Escadron : piloter une flotte de sessions Claude Code

Un skill Claude Code qui transforme une session en **orchestrateur** : elle découpe un chantier en lots, ouvre une session Claude par lot (chacune dans sa fenêtre, son worktree git et sa branche), les surveille, fait juger chaque lot par une session neuve, puis te rend compte une seule fois à la fin.

Chaque session est connectée au **Remote Control** : tu peux toutes les suivre et leur parler depuis l'app Claude sur ton téléphone.

## Ce qu'il y a dedans

| Dossier | Contenu |
|---|---|
| `skill/SKILL.md` | La procédure complète : monter, briefer, surveiller, vérifier, intégrer, fermer, plus le tableau des pièges déjà payés |
| `skill/helpers/` | Les scripts : `new-worktree.ps1`, `launch-escadron.ps1`, `watch-escadron.ps1` (chien de garde), `verify-lot.ps1` (vérificateur neuf), `audit-mission.ps1`, `close-session.ps1`, `close-dead-windows.ps1`, `log-decision.py`… |
| `hooks/` | `escadron_stop_gate.py` (un worker ne peut pas s'arrêter sans rapport) et `escadron_heartbeat.py` (battement de cœur lu par le chien de garde) |

## Prérequis

- Windows, PowerShell 7 (`pwsh`), Windows Terminal, git, Node et Python (`py`)
- Claude Code installé et connecté, avec le Remote Control
- Un abonnement Max conseillé : plusieurs sessions en parallèle consomment vite le quota (les workers tournent en Sonnet par défaut)

## Installation

1. Copie `skill/` dans `~/.claude/skills/escadron/`.
2. Copie `hooks/` dans `~/.claude/hooks/`.
3. Ajoute les hooks dans `~/.claude/settings.json`. Ils ne s'activent que dans les sessions workers (`ESCADRON_WORKER=1`) :

```json
"hooks": {
  "Stop": [{ "hooks": [{ "type": "command",
    "command": "[ \"$ESCADRON_WORKER\" = \"1\" ] || exit 0; py \"$HOME/.claude/hooks/escadron_stop_gate.py\"" }] }],
  "UserPromptSubmit": [{ "hooks": [{ "type": "command",
    "command": "[ \"$ESCADRON_WORKER\" = \"1\" ] || exit 0; py \"$HOME/.claude/hooks/escadron_heartbeat.py\"" }] }],
  "PreToolUse": [{ "matcher": "*", "hooks": [{ "type": "command",
    "command": "[ \"$ESCADRON_WORKER\" = \"1\" ] || exit 0; py \"$HOME/.claude/hooks/escadron_heartbeat.py\"" }] }],
  "PostToolUse": [{ "matcher": "*", "hooks": [{ "type": "command",
    "command": "[ \"$ESCADRON_WORKER\" = \"1\" ] || exit 0; py \"$HOME/.claude/hooks/escadron_heartbeat.py\"" }] }]
}
```

4. Recommandé : écris ton propre `~/.claude/hooks/guardrails.py` (hook PreToolUse) qui bloque, pour les workers, ce qu'ils ne doivent jamais faire seuls : push, merge, déploiement, envoi de mails, paiements. Il dépend de tes outils, il n'est donc pas fourni. Tu peux demander à Claude de l'écrire avec toi.
5. Adapte les chemins : les exemples utilisent `C:\Users\<toi>\Projets\<repo>` pour les repos et `C:\Users\<toi>\Projets\_briefs\<mission>\` pour les dossiers de mission.

## Utilisation

Dans Claude Code : `/escadron`, ou simplement « monte un escadron de 3 sessions sur tel chantier ».

La règle d'or : **chaque lot a une condition de fin vérifiable par une commande** (un test qui passe, un fichier qui existe). Sans elle, ne lance rien.
