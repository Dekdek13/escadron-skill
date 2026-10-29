// Verifie si un dossier est deja approuve ("do you trust this folder") pour Claude Code.
// Usage : node check-trust.js "C:\Users\<toi>\Projets\mon-app"
const fs = require("fs");
const path = require("os").homedir() + "/.claude.json";
const arg = process.argv[2];
if (!arg) { console.log("usage: node check-trust.js <dossier>"); process.exit(2); }
const dir = arg.replace(/\\/g, "/").replace(/\/+$/, "");
const cfg = JSON.parse(fs.readFileSync(path, "utf8"));
const entry = (cfg.projects || {})[dir];
if (entry && entry.hasTrustDialogAccepted === true) {
  console.log("TRUST-OK " + dir);
} else {
  console.log("TRUST-NON " + dir);
  console.log("-> lancer : node trust-dir.js \"" + arg + "\"  (sauvegarde le config avant)");
  process.exit(1);
}
