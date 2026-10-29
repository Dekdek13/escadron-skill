// Approuve un dossier pour Claude Code (evite le blocage "do you trust this folder"
// au demarrage d'une session lancee automatiquement, indeblocable a distance).
// Sauvegarde le config AVANT toute ecriture.
// Usage : node trust-dir.js "C:\Users\<toi>\Projets\mon-repo" [autre-dossier...]
const fs = require("fs");
const path = require("os").homedir() + "/.claude.json";
const args = process.argv.slice(2);
if (!args.length) { console.log("usage: node trust-dir.js <dossier> [dossier...]"); process.exit(2); }

const stamp = new Date().toISOString().replace(/[-:T]/g, "").slice(0, 15);
fs.copyFileSync(path, path + ".bak-" + stamp);
console.log("backup -> .claude.json.bak-" + stamp);

const cfg = JSON.parse(fs.readFileSync(path, "utf8"));
cfg.projects = cfg.projects || {};
let n = 0;
for (const a of args) {
  const dir = a.replace(/\\/g, "/").replace(/\/+$/, "");
  cfg.projects[dir] = cfg.projects[dir] || {};
  if (cfg.projects[dir].hasTrustDialogAccepted !== true) {
    cfg.projects[dir].hasTrustDialogAccepted = true;
    n++;
    console.log("approuve : " + dir);
  } else {
    console.log("deja approuve : " + dir);
  }
}
fs.writeFileSync(path, JSON.stringify(cfg, null, 2));
console.log("nouvellement approuves : " + n);
