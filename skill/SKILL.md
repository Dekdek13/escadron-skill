---
name: escadron
description: Monte, brief, surveille, intègre et ferme un escadron de sessions Claude Code sur ton PC. Une session par worker, dans SA fenêtre, en Sonnet (Opus sur demande), autonome (portail de fin, interdits durs, chien de garde qui relance et reprend seul), connectée au Remote Control (pilotable depuis l'iPhone), dans SON worktree git, briefée par un fichier de mission. Déclenché quand l'utilisateur dit : monte un escadron, lance N sessions, ouvre 3 Claude sur tel chantier, fais-le faire par des agents, ferme l'escadron, qui est vivant, brief les workers, ou après un /clear pour ré-armer les sessions.
---

# /escadron v4 : piloter une flotte autonome de sessions Claude

Refondu le 28/09/2026 à partir des pièges réellement payés. **v4 du 01/10/2026 : journal de décisions par worker, vérificateur neuf par lot, audit du matin par une session neuve**. **v3 du 29/09/2026 : escadron autonome**, l'utilisateur n'intervient qu'au début (la spec) et à la fin (conditions de fin remplies, une seule notification). **Ce skill est la procédure exécutable. Le manuel `LOOP-ENGINEERING.md (optionnel, ton propre manuel de leçons)` garde les leçons et leurs preuves** : lis-le une fois avant d'orchestrer, mais ce sont les commandes d'ICI qui font foi.

l'utilisateur pilote **depuis son iPhone**, loin du PC. Rien de ce qui suit ne doit exiger un clic de sa part, **ni même son attention pendant la mission** : pas de notification intermédiaire, pas de question. Le PC fixe est son serveur, allumé en permanence.

## L'autonomie (29/09/2026, testée en réel)
| Pièce | Où | Ce qu'elle fait |
|---|---|---|
| Mode worker | `launch-escadron.ps1 -Brief` | pose `ESCADRON_WORKER=1` et `ESCADRON_REPORT=<rapport>` dans la session, l'inscrit dans `<mission>\escadron.json` |
| Interdits durs | `~/.claude/hooks/guardrails.py` (PreToolUse, workers seulement, **à écrire selon tes outils**, voir README) | bloque push, merge, passage sur main, deploys (Vercel, Supabase, Modal, npm publish), écritures `gws`, Stripe live, kill par nom, publication / Zoho / Stripe / Supabase en MCP, `PushNotification` |
| Portail de fin | `~/.claude/hooks/escadron_stop_gate.py` (Stop) | pas de rapport = pas d'arrêt : renvoie le worker au travail, 3 fois max (`-GateMax`) |
| Battement de cœur | `~/.claude/hooks/escadron_heartbeat.py` | écrit `<mission>\.status\<nom>.json` (working / tool / idle / done). Indispensable : une session Remote Control n'écrit **aucun transcript local** |
| Journal de décisions (v4) | `helpers/log-decision.py` + portail de fin (`ESCADRON_DECISIONS=1`) | une ligne par décision dans `<mission>\decisions-<Nom>.tsv` (heure, phase, décision, raison, preuve, résultat) ; sans journal, le portail refuse l'arrêt |
| Vérificateur neuf (v4) | `helpers/verify-lot.ps1` | session headless neuve, sur le COMMITÉ de la branche dans un worktree jetable : rejoue la condition de fin, écrit `VERDICT-<Nom>.md` (`VERDICT: ACCEPT` / `REJECT`), exit 0 / 1 |
| Audit du matin (v4) | `helpers/audit-mission.ps1` | session headless neuve : relit journaux, rapports et verdicts, écrit `AUDIT.md` qui finit par `## Attention` |
| Chien de garde | `helpers/watch-escadron.ps1` | toutes les 2 min : mort, outil figé 30 min, aucun signe de vie 3 min après le lancement, rendormi après une relance → **reprise automatique** (session neuve qui repart du disque) ; arrêté sans rapport → réveille l'orchestrateur pour UNE relance par message ; 2 reprises épuisées → `BLOCKED` ; tous `DONE`/`BLOCKED` → `ALL_DONE` |

Preuve de bout en bout (29/09) : `_briefs\test-autonomie-2\` : E2E-Normal fini seul, E2E-Mort figé au démarrage puis tué en plein travail et fini après 2 reprises automatiques, E2E-Sourd relancé puis `BLOCKED` ; `ALL_DONE` sans intervention humaine.

## Vocabulaire
- **Orchestrateur** : toi. Découpe, briefe, **vérifie**, intègre, rend compte. Seul à pousser et merger.
- **Worker** : une session lancée par toi. Exécute un lot dans SON worktree, commite sur SA branche, écrit SON rapport. Ne pousse jamais, ne merge jamais.

## La règle d'or (sans elle, ne lance rien)
**Chaque lot a une condition de fin vérifiable par une commande** (un check exit 0, un fichier qui existe, un test qui passe). « Améliore X » n'en est pas une. Si tu ne sais pas écrire la commande qui prouve que c'est fini, le lot n'est pas prêt.
Sépare toujours le vérifiable-machine (build, tests) du vérifiable-humain (rendu visuel) : un worker ne peut pas prouver qu'un écran est beau.

Helpers : `~/.claude/skills/escadron/helpers/` (`new-worktree.ps1`, `launch-escadron.ps1`, `watch-escadron.ps1`, `log-decision.py`, `verify-lot.ps1`, `audit-mission.ps1`, `wait-reports.sh`, `close-session.ps1`, `check-trust.js`, `trust-dir.js`).

---

## 1. MONTER

### A. Cadrer (une question max)
- Déduis toi-même repo et nombre de sessions, **annonce ton choix**. Repos : `C:\Users\<toi>\Projets\<repo>`.
- **Découpe par zones disjointes.** Si tout tient dans une zone ou un fichier : **séquentiel, une seule session**, et dis-le.
- Nomme chaque worker d'après son lot : `App-Clips`, `App-Paiement`. ASCII, sans apostrophe. Pas de numéro.
- **Chemins absolus obligatoires dans les briefs de sous-agents** (constat F03, 01/10/2026) : chaque chemin cité dans `BRIEF.md` est un chemin absolu complet (`C:\Users\<toi>\...`), jamais relatif ni déduit par le worker — un worker lancé dans son propre worktree n'a pas le même répertoire courant que l'orchestrateur.

### A bis. Choisir le bon mécanisme de délégation (escadron vs sous-agent Task vs direct) — ajouté 01/10/2026 (R02)
Avant de lancer quoi que ce soit, choisis explicitement UN des trois mécanismes, pas par défaut :
- **Travail direct (toi, sans délégation)** : la tâche est courte, ou urgente, ou l'utilisateur vient de dire "fais-le toi-même", "pas besoin de passer par une autre session", "on fait du tac au tac". Dans ce cas, ne spawn rien, édite/exécute directement.
- **Sous-agent Task/Agent (`subagent_type`, modèle Sonnet)** : la tâche est un sous-travail borné et ponctuel dans la session courante (recherche, lecture d'un gros dossier, exécution d'un lot de fichiers indépendant) que tu veux garder hors de ton contexte, mais qui ne justifie pas une fenêtre Claude Code séparée ni un suivi par l'utilisateur.
- **Escadron (nouvelle fenêtre Claude Code nommée, Remote Control)** : la tâche est un chantier large, multi-étapes, qui mérite d'être pilotable indépendamment par l'utilisateur depuis son iPhone, ou qui doit tourner en parallèle d'autres chantiers sur le même projet pendant un temps long.

**Avant de lancer un escadron sur un projet** : vérifie avec `ListAgents` s'il existe déjà une fenêtre escadron active sur ce même projet. S'il y en a une, n'en relance pas une deuxième sans raison explicite (chevauchement de travail = confusion, conflits git, double consommation de quota) : soit tu rejoins/continues celle qui existe via `SendMessage`, soit tu dis clairement à l'utilisateur pourquoi une deuxième fenêtre est nécessaire (ex. lot strictement indépendant, worktree différent).

**Si l'utilisateur dit "arrête les agents", "arrête d'appeler claude", "reprends la main"** : c'est un ordre d'arrêt immédiat de toute délégation en cours (sous-agents ET fenêtres escadron), pas une suggestion pour la prochaine tâche. Stoppe ce qui tourne (`TaskStop` / fermeture de fenêtre selon le cas) avant de continuer en direct.

### B. Dossier de mission
`C:\Users\<toi>\Projets\_briefs\<mission>\`
- `BRIEF.md` : tronc commun + une section par worker (modèle §2).
- `MISSION.md` : le tableau de bord pour ré-armer après un `/clear` : workers, worktrees, branches, ports, statut. Mets-le à jour à chaque étape.
- Chaque worker y écrira `REPORT-<Worker>.md`.

Un worktree ne contient **que le commité** : si le lot a besoin d'un fichier non suivi (plans, specs), mets-le dans le dossier de mission, pas dans le repo.

### C. Un worktree par worker (toujours, dès qu'il y a du code)
```
pwsh -File ~/.claude/skills/escadron/helpers/new-worktree.ps1 -Repo "<repo>" -Lot <lot>
```
Crée `<repo>-wt-<lot>` sur la branche `wt/<lot>`, copie les `.env*` non versionnés, fait `npm install`, approuve le dossier. Dernière ligne : `WORKTREE <chemin>`.
Pourquoi : le 02/09, un `git add -A` de l'orchestrateur a commité le travail à moitié fini d'un autre worker. Sans worktree, deux sessions se marchent dessus.

### D. Lancer
```
pwsh -File ~/.claude/skills/escadron/helpers/launch-escadron.ps1 -Names "<W1>","<W2>" -Dirs "<wt1>","<wt2>" -Brief "<mission>\BRIEF.md"
```
Le lanceur garantit ce qui a déjà coûté cher :
| Garantie | Piège évité |
|---|---|
| `--model sonnet` par défaut | 7 sessions Opus ont vidé le quota du jour le 14/09. `-Model opus -Effort medium` si l'utilisateur le demande (autorisé depuis le 29/09). Les **sous-agents** restent Sonnet obligatoire (hook). |
| mode worker (`-Brief`) | interdits durs + portail de fin + battement de cœur + inscription au manifeste du chien de garde |
| `--remote-control='<Nom>'`, pas `-n` | `-n` n'est qu'un nom d'affichage : session invisible sur l'iPhone et injoignable (19/09). |
| refus d'un nom déjà vivant | des sessions homonymes ont coexisté : un ordre part à la mauvaise session sans erreur. |
| dossier approuvé avant lancement | « do you trust this folder » fige la session, invisible et indéblocable depuis l'iPhone. |
| brief par fichier | un brief long en argument casse sur les apostrophes de `pwsh -c`. |
| `-w new` | `-w 0` ouvrirait un onglet dans la fenêtre courante. |

**Quel Chrome ?** (02/10) : si le lot a besoin des sessions de l'utilisateur (prod connectée, réseaux, dashboards, OAuth), lance avec `-Chrome` (son vrai Chrome, une session à la fois, jamais Publier/Programmer/Envoyer/Payer sans go) ; sinon Chrome séparé. Écris-le dans le brief.

Session de **vérification visuelle** (elle regarde, ne code pas) : ajoute `-Chrome`, sur le worktree de la branche à valider, avec un port dédié.

### E. Confirmer qu'ils tournent
`ListAgents` : chaque nom doit apparaître en `Remote Control · running`. Il retarde (une session morte reste `idle` une minute) ; la vérité reste `Get-Process` / la liste des pwsh `remote-control`.
Tu n'as **pas** besoin de leur envoyer le brief : il est dans leur prompt initial.

### F. Surveiller : la boucle du chien de garde
```
pwsh -File ~/.claude/skills/escadron/helpers/watch-escadron.ps1 -Mission "<mission>"
```
À lancer en **`run_in_background`**. Il répare seul les workers morts, figés sur un outil depuis 30 min (`-BusyMinutes`) ou restés muets après une relance : reprise automatique, 2 max par worker (`-MaxResumes`), ensuite `BLOCKED`. Tu es réveillé dans deux cas seulement :
- **exit 10 `ACTION`** : un worker est `STALE` (arrêté sans rapport depuis 1 min, ou muet depuis 10 min). Envoie-lui un `SendMessage` de relance (nom + `[ref]` via `ListAgents`), note-le avec `watch-escadron.ps1 -Mission "<mission>" -MarkNudged <Nom>`, puis **relance le chien de garde en arrière-plan**. Testé le 29/09 : la relance est bien reçue par une session Remote Control, même si l'envoi n'est jamais confirmé.
- **exit 0 `ALL_DONE`** : chaque worker est `DONE` ou `BLOCKED`. Passe au §3.

Instantané à tout moment : `-Once`. Ne boucle jamais sur `ListAgents` et n'envoie jamais « t'as fini ? ».
⚠️ `notify_when_idle` ne marche pas sur Remote Control (28/09). `wait-reports.sh` reste disponible pour une simple attente de rapports.

### F bis. Juger chaque lot par un vérificateur neuf (v4, marche 3)
Un lot n'est ✅ qu'après **ACCEPT** d'une session qui ne l'a pas écrit. Dès qu'un worker est `DONE` :
```
pwsh -File ~/.claude/skills/escadron/helpers/verify-lot.ps1 -Mission "<mission>" -Name "<W1>"
```
Exit 0 `ACCEPT`, 1 `REJECT`, 2 pas de verdict. Le vérificateur part du **commité** de la branche (worktree jetable détaché, supprimé à la fin), lit le brief comme cahier des charges, traite le rapport comme des allégations et teste chaque exemple du brief directement sur le code (des tests verts peuvent avoir été adaptés à un code faux). `-Model opus` pour un juge d'une autre famille que l'auteur.
`REJECT` : renvoie le lot au worker (relance avec le verdict), jamais de correction par l'orchestrateur à sa place ; un second `REJECT` = ❌ dans le rapport à l'utilisateur.

### G. Rendre compte à l'utilisateur : UNE fois, à la fin
Avant la notification : `pwsh -File ~/.claude/skills/escadron/helpers/audit-mission.ps1 -Mission "<mission>"` (session neuve, `AUDIT.md`). La section **« Attention »** de l'audit va en tête de ton rapport à l'utilisateur : il audite des décisions, pas la nuit entière.
Pas de notification au lancement ni en cours de route. Au `ALL_DONE`, après le contrôle des preuves (§3) : `PushNotification` d'une ligne, résultat en premier (« Mission X finie : 3 ✅, 1 blocked (raison), 2 décisions pour toi »), puis le détail en tableau avec les **décisions pour l'utilisateur** regroupées (merge, actions externes, arbitrages produit).

---

## 2. Le brief (modèle de `BRIEF.md`)

L'orchestrateur ne connaît pas sa propre ref (`ListAgents` ne liste pas la session qui l'appelle) : **le canal de retour, c'est le fichier de rapport**, pas un message.

> # Mission <nom>
> Tu es **worker** d'un escadron piloté par l'orchestrateur de l'utilisateur.
> ⚠️ **l'utilisateur n'est pas dans la boucle** : personne ne répondra à une question. Ne demande rien, n'attends rien, avance seul jusqu'à la condition de fin. Tout ce qui lui revient (action externe, choix produit, action physique) va dans la section **« Décisions pour l'utilisateur »** de ton rapport, et tu continues le reste du lot. Les interdits (push, merge, deploy, envois) sont bloqués par un hook : ne cherche pas à les contourner.
> Lis d'abord `LOOP-ENGINEERING.md (si tu en as un)` (§1, §5, §6, §12).
>
> **Pourquoi** : <le but, en deux lignes>
> **Livrables** : <fichiers exacts>
> **Condition de fin** : <la commande et le résultat attendu>
>
> **Règles**
> 1. Périmètre strict : ton worktree et tes livrables, rien d'autre. **Jamais dans le repo principal.**
> 2. Distingue ce que tu as **LU** de ce que tu **DÉDUIS**. N'invente jamais un fichier, une route, une variable, une URL. Pas trouvé = « pas trouvé ».
> 3. Dis explicitement ce que tu n'as **PAS** pu vérifier. ⬜ compte autant que ❌.
> 4. Conflit ou risque : tu t'arrêtes et tu l'écris dans ton rapport avant d'agir.
> 5. Sous-agents : **Sonnet uniquement** (`model: 'sonnet'`), l'utilisateur les autorise pour ce lot. Tu relis ce qu'ils produisent.
> 6. Dev server : uniquement sur ton port dédié, `NODE_OPTIONS=--max-old-space-size=4096`, vérifie le PID qui écoute, arrête-le à la fin. **Jamais `npm run build` si un dev server tourne sur ton dossier.**
> 7. Préfère les CLI officielles aux MCP quand elles existent.
> 8. **Aucune action externe** : mail, publication, deploy, migration, écriture Stripe live, suppression de données réelles.
> 8 bis. N'écris `REPORT-<Nom>.md` qu'à la toute fin ; un point d'étape va dans `REPORT-<Nom>.partial.md`.
> 8 ter. **Journal de décisions** : à chaque décision (garder, jeter, changer d'angle, s'arrêter), `py ~/.claude/skills/escadron/helpers/log-decision.py --phase <cadrage|lecture|repro|build|preuve|nettoyage|rapport|blocage> --decision "..." --raison "..." --preuve "<commande + résultat, ou aucune>" --resultat <garde|jete|bloque>`. Sans journal, le portail de fin refuse ton arrêt. Ton lot sera jugé par un **vérificateur neuf** qui rejoue ta condition de fin sur ce qui est **commité**.
> 9. Commits sur ta branche `wt/<lot>`, chemins listés explicitement (**jamais `git add -A`**). ❌ Aucun push, aucun merge.
>
> **Rendu** : le chemin EXACT de ton rapport est dans ton prompt de lancement (`_briefs\<mission>\REPORT-<Nom>.md`, nom de fichier à ne pas modifier) : verdict d'abord, fichiers touchés, hashes de commit, **sorties brutes** des checks, **preuves dans l'app** (captures, si le repo a un skill `verify-app`), ce qui reste ouvert, ce qui t'a manqué, **Décisions pour l'utilisateur**. Pas de `PushNotification` : c'est l'orchestrateur qui prévient l'utilisateur, une fois, à la fin.
>
> ## <Worker 1> : worktree, branche, port, spécificités du projet
> ## <Worker 2> : …

Spécificités à rappeler selon le repo :

---

## 3. VÉRIFIER (ton vrai travail)

**v4 : le premier contrôle n'est plus le tien.** `verify-lot.ps1` (§1.F bis) juge chaque lot ; toi, tu contrôles le verdict (ouvre `VERDICT-<Nom>.md`, rejoue un point au hasard) et le journal (`decisions-<Nom>.tsv` : une décision sans preuve est un drapeau).

**Ne relaie jamais un rapport sans contrôler le terrain.** Le rapport est une carte.
- Relis le **diff** de la branche (`git log $(git merge-base <base> wt/<lot>)..wt/<lot>`), pas le résumé.
- **Rejoue toi-même la condition de fin** dans le worktree. Si elle ne passe pas chez toi, elle ne passe pas.
- Interroge le vrai système (API, base, fichiers) plutôt que le rapport.
- Jamais juger un script via un pipe (`| tail`) : l'exit code est celui du dernier maillon.
- Diff filtré : les lignes modifiées qui **ne contiennent pas** le motif attendu montrent ce qu'un worker a touché sans le dire.
- Un correctif d'interface non vu à l'écran est « raisonné, pas constaté » : dis-le comme tel.
- Si un worker te contredit avec une preuve, il a probablement raison : corrige-toi en public.

## 4. INTÉGRER (orchestrateur seul, après le go de l'utilisateur)
1. `git -C <wt> rebase <base>` avant toute fusion (une branche en retard peut **annuler** des commits de la base ; sur un fichier de config, la base gagne).
2. Merge dans la base, depuis le repo principal, **chemins et branche explicites**.
3. Push, puis `git fetch` et compare local / distant.
4. Déploiement : surveille jusqu'au **Ready**, pas jusqu'au push. Rien de public ou d'irréversible sans le go de l'utilisateur.
5. Nettoie : `git worktree remove <wt>` puis `git branch -d wt/<lot>`.

## 5. FERMER
```
pwsh -File ~/.claude/skills/escadron/helpers/close-session.ps1 -Names "<W1>","<W2>"
```

**Puis TOUJOURS fermer les fenêtres mortes** (04/10/2026 : « fermer les terminaux aussi, pour ne pas laisser de survivant ») :
```
pwsh -File ~/.claude/skills/escadron/helpers/close-dead-windows.ps1          # -DryRun pour voir avant
```
Il garde chaque fenêtre qui héberge une session vivante et ferme toutes les autres. Fin de mission = **0 fenêtre morte** : vérifie que la dernière ligne affiche autant de « Restantes » que de sessions vivantes. Une mission n'est pas finie tant qu'il reste une fenêtre morte.
⚠️ Le 04/10, `close-session.ps1` n'a rien fermé, sans message d'erreur, sur 8 sessions : contrôle toujours après coup qu'il n'existe plus de shell `--remote-control='<Nom>'`, sinon ferme par PID (`taskkill /PID <shell> /T /F`, jamais WindowsTerminal).
Tue **tout l'arbre** de la session : shell, `claude.exe` et tout ce qu'elle a lancé (bash, npm, dev servers, tsc), feuilles d'abord, puis vérifie : `FERME <Nom>` ou `SURVIT <Nom>`, et affiche les ports libérés. Avant le 29/09 seul `pwsh` + `claude.exe` étaient tués : un dev server lancé par le worker survivait. Les **stacks Supabase docker ne font pas partie de l'arbre** : le script les signale, arrête-les avec `npx supabase stop --workdir <dossier de la stack>` (une stack du bloc B a survécu à la fermeture de son orchestrateur le 29/09).
❌ Jamais `Stop-Process -Name claude` (tue tout l'escadron et l'orchestrateur). ❌ Jamais tuer `WindowsTerminal` (toutes les fenêtres). ❌ Jamais cibler par date de démarrage (a déjà tué une session saine). **Toujours par nom.**
Confirme avant de fermer une session que l'utilisateur n'a pas nommée ou que tu n'as pas lancée.

## 6. RÉ-ARMER après un `/clear`
1. Lis `_briefs\<mission>\MISSION.md` (demande à l'utilisateur la mission si plusieurs dossiers sont actifs).
2. `ListAgents` + liste des process pour l'état réel.
3. Les rapports déjà présents sont la vérité sur ce qui est fini ; `watch-escadron.ps1 -Mission <mission> -Once` donne l'état de chaque worker, puis relance-le en arrière-plan.
4. Pas de notification à l'utilisateur tant que la mission n'est pas finie.

## Pièges payés (à ne pas repayer)
| Piège | Conséquence | Parade |
|---|---|---|
| Session Opus | quota du jour vidé (14/09) | hook + `--model sonnet` |
| `-n` au lieu de `--remote-control` | session invisible, injoignable (19/09) | lanceur |
| Dossier non approuvé | session figée à distance | lanceur / new-worktree |
| `git add -A` partagé | travail d'un autre worker commité (02/09) | worktree par worker, chemins explicites |
| Worktree sans `.env` | l'app ne démarre pas | new-worktree copie les `.env*` |
| `notify_when_idle` sur Remote Control | non supporté, attente infinie (28/09) | `wait-reports.sh` en arrière-plan |
| Rapport « optimiste » | fausse info relayée à l'utilisateur | §3, rejouer la condition de fin |
| Sous-agents refusés dans un worker | fan-out impossible sans l'accord de l'utilisateur dans SA session | l'écrire dans le brief ; sinon l'utilisateur le dit au worker |
| `TaskStop` sur `npm run dev` | `vite` survit et garde le port (03/09) | vérifier le PID qui écoute |
| 3 sessions Chrome sur un dev server | 9,4 Go, serveur asphyxié (31/08) | heap 4096, redémarrer entre deux passes |
| `resize_window` Chrome | fenêtre bloquée à 438 × 98 px, irréparable à distance | responsive en headless uniquement |
| Branche en retard fusionnée sans rebase | commits de la base annulés | §4 rebase d'abord |
| Apostrophe française (`'`) dans un texte injecté dans une commande shell/PowerShell entre apostrophes droites (`'`) | `unexpected EOF while looking for matching` ou commande qui avale les lignes suivantes (B01/F01, 12 occurrences, 9 sessions) | remplacer `'` par `'` avant d'injecter du texte français libre dans un heredoc/une commande entre apostrophes, ou préférer les guillemets doubles `"..."` si le contenu n'a pas besoin d'être littéral |
| Kill global / par date | escadron entier ou session saine tués | close-session.ps1 par nom |
| Liste passée via `pwsh -File` | `"A","B"` arrive en une seule chaîne : 0 session lancée, puis relance sans brief (28/09) | le lanceur redécoupe la liste |
| Worker qui « corrige » son nom | Test-B a écrit `REPORT-TestB.md` : `wait-reports.sh` ne l'aurait jamais vu (28/09) | chemin exact du rapport dans le prompt de lancement |
| `claude --continue` sur Remote Control | la session relancée quitte aussitôt : aucun transcript local à reprendre (29/09) | reprise = session neuve qui repart du disque (git, fichiers, rapport partiel) |
| Approbation du dossier écrasée | E2E-Mort figé sur « do you trust this folder » : la session lancée juste avant a réécrit `~/.claude.json` sans l'approbation (29/09) | le lanceur re-vérifie l'approbation (5 essais) ; le chien de garde reprend toute session sans signe de vie après 3 min |
| Relance en boucle | un worker qui répond à la relance puis se rendort aurait été relancé à l'infini (29/09) | une seule relance par message, ensuite reprise |
| Pas de transcript local | le chien de garde ne voyait pas si un worker avançait (29/09) | battement de cœur écrit par les hooks du worker |
| Worker qui « attend » | Test-Reprise a affirmé avoir attendu plus de 300 s en une minute réelle, `Start-Sleep` étant bloqué par Claude Code (29/09) | contrôler les preuves, jamais le récit ; pour simuler une attente, `ping -n N` au premier plan |
| Capture d'écran PowerShell (`CopyFromScreen`) dans une session Chrome | renvoie le fond d'écran Windows, pas le Chrome piloté, même après `SetForegroundWindow` : le PC était **verrouillé** (l'utilisateur pilote depuis l'iPhone) (29/09) | `mcp__claude-in-chrome__computer` `screenshot` avec `save_to_disk:true`, puis relire chaque image |
| Rapport provisoire écrit au chemin final | Deux workers ont écrit « PROVISOIRE / en cours » dans `REPORT-<Nom>.md` : le chien de garde les a vus `DONE` et s'est arrêté alors qu'ils travaillaient (29/09) | `watch-escadron.ps1` et `escadron_stop_gate.py` ignorent un rapport dont les 8 premières lignes disent provisoire / en cours ; dans le brief : rapport partiel = `REPORT-<Nom>.partial.md` |
| Fenêtres mortes laissées ouvertes | 114 fenêtres Windows Terminal sans aucune session derrière, accumulées sur plusieurs jours (04/10) | `close-dead-windows.ps1` à chaque fermeture + `"closeOnExit": "always"` dans les réglages de Windows Terminal |
| Worker de rapports qui survit | 04/10 : Un worker a arrêté `vite` (port 5191 libre) mais `concurrently` et `worker:reports` (tsx) ont survécu à `close-session.ps1` : connexion `postgres.js` encore ouverte (`DROP DATABASE` refusé), dossier du worktree verrouillé (`git worktree remove` → `Invalid argument`) | avant de fermer : `Get-CimInstance Win32_Process` filtré sur le chemin du worktree, `taskkill /PID <racine concurrently> /T /F` ; dans le brief : « tue l'arbre `concurrently` entier, pas seulement le PID qui écoute » |
| Hook qui bloque du texte | un heredoc qui édite une doc contenant `claude -n` a été refusé (28/09) | le hook ignore les heredocs, ne regarde que les vraies positions de commande |

## Garde-fous du skill
- **Pas de blanchiment de permission** : une action refusée dans une session ne se fait pas exécuter par une autre. Remonte à l'utilisateur.
- Lancer, fermer, créer un worktree : local et réversible, pas besoin de demander. **Publier, déployer, envoyer un mail, écrire en live : toujours le go de l'utilisateur.**
- Nouvelle leçon payée : ajoute-la au tableau ci-dessus **avec sa preuve** (date, symptôme), et dans le manuel.
