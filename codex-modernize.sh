#!/usr/bin/env bash
set -euo pipefail

# -------- config --------
REPO_DIR="${REPO_DIR:-.}"        # set to repo path if running from elsewhere
TARGET_NODE_MAJOR_MIN=18

# -------- helpers --------
say() { printf "\n==> %s\n" "$*"; }
warn() { printf "\n[warn] %s\n" "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

need_bins=(git node npm)
for b in "${need_bins[@]}"; do
  if ! have "$b"; then
    echo "Missing: $b. Install and re-run." >&2
    exit 1
  fi
done

node_major=$(node -p "process.versions.node.split('.')[0]")
if (( node_major < TARGET_NODE_MAJOR_MIN )); then
  warn "Node >= ${TARGET_NODE_MAJOR_MIN} recommended. Current: $(node -v)"
fi

cd "$REPO_DIR"

if [ ! -f package.json ]; then
  say "No package.json found; initializing…"
  npm init -y >/dev/null
fi

# -------- patch package.json (idempotent) --------
say "Patching package.json (engines, scripts, devDeps, overrides)…"
node - <<'NODE'
const fs = require('fs');
const path = 'package.json';
const pkg = JSON.parse(fs.readFileSync(path,'utf8'));

pkg.engines = Object.assign({}, pkg.engines, { node: ">=18" });

pkg.scripts = Object.assign({
  build: pkg.scripts?.build || "rollup -c || vite build || webpack --mode production",
  dev: pkg.scripts?.dev || "rollup -c -w || vite || webpack serve --mode development",
  start: pkg.scripts?.start || "electron ."
}, pkg.scripts || {});

pkg.devDependencies = Object.assign({
  // Modern rollup + plugins
  "rollup": "^4.22.0",
  "@rollup/plugin-node-resolve": "^15.3.0",
  "@rollup/plugin-commonjs": "^25.0.8",
  "@rollup/plugin-replace": "^5.0.7",
  "@rollup/plugin-terser": "^0.4.4",
  // Electron only if you use the frameless wrapper
  "electron": pkg.devDependencies?.electron || "^31.0.0"
}, pkg.devDependencies || {});

// Keep Workbox entries only if already present somewhere:
const hasWB = JSON.stringify(pkg).includes('workbox');
if (hasWB) {
  pkg.devDependencies["workbox-build"] = "^7.0.0";
  pkg.devDependencies["workbox-webpack-plugin"] = "^7.0.0";
}

// Mildly nudge transitive stacks via overrides (npm supports this)
pkg.overrides = Object.assign({
  "domexception": "^4.0.0",
  "abab": "^2.0.6",
  "w3c-hr-time": "^1.0.2"
}, pkg.overrides || {});

// Prefer not to force-install deprecated libs; do not remove them automatically.

fs.writeFileSync(path, JSON.stringify(pkg, null, 2));
console.log("package.json updated.");
NODE

# -------- patch rollup config(s) if present --------
patch_rollup() {
  local f="$1"
  [ -f "$f" ] || return 0
  say "Patching $f"
  # Replace deprecated terser plugin import
  sed -i \
    -e "s#from[[:space:]]*'rollup-plugin-terser'#from '@rollup/plugin-terser'#g" \
    -e 's#from[[:space:]]*"rollup-plugin-terser"#from "@rollup/plugin-terser"#g' \
    "$f" || true

  # Ensure core plugin imports are modern
  # (only patch known old forms; keep existing if already modern)
  sed -i \
    -e "s#from[[:space:]]*'rollup-plugin-node-resolve'#from '@rollup/plugin-node-resolve'#g" \
    -e 's#from[[:space:]]*"rollup-plugin-node-resolve"#from "@rollup/plugin-node-resolve"#g' \
    -e "s#from[[:space:]]*'rollup-plugin-commonjs'#from '@rollup/plugin-commonjs'#g" \
    -e 's#from[[:space:]]*"rollup-plugin-commonjs"#from "@rollup/plugin-commonjs"#g' \
    -e "s#from[[:space:]]*'rollup-plugin-replace'#from '@rollup/plugin-replace'#g" \
    -e 's#from[[:space:]]*"rollup-plugin-replace"#from "@rollup/plugin-replace"#g' \
    "$f" || true

  # If no terser usage exists, do nothing else; if it exists, ensure named import `terser` stays valid
}
for f in rollup.config.js rollup.config.mjs; do patch_rollup "$f"; done

# -------- upgrade workbox CDN references in service workers (if found) --------
say "Scanning for Workbox service worker CDN imports…"
sw_candidates=(
  "sw.js"
  "service-worker.js"
  "public/sw.js"
  "public/service-worker.js"
  "src/sw.js"
  "src/service-worker.js"
)
for sw in "${sw_candidates[@]}"; do
  if [ -f "$sw" ]; then
    if grep -q "workbox-cdn/releases/" "$sw"; then
      say "Updating Workbox CDN in $sw → 7.0.0"
      sed -i -E "s@workbox-cdn/releases/[0-9]+\.[0-9]+\.[0-9]+/@workbox-cdn/releases/7.0.0/@g" "$sw" || true
    fi
  fi
done

# -------- optional: bump jsdom if present --------
if jq -e '.devDependencies.jsdom or .dependencies.jsdom' package.json >/dev/null 2>&1; then
  say "jsdom present → bumping to ^24"
  npm i -D jsdom@^24
fi

# -------- tell user about direct usage of deprecated libs (q, stable, inflight) --------
say "Checking for direct imports of q, stable, inflight…"
found_any=0
grep -R --include='*.{js,mjs,ts,tsx,jsx}' -nE "from ['\"]q['\"]|require\(['\"]q['\"]\)" . && { warn "Direct 'q' usage detected (consider Promises/async-await)."; found_any=1; } || true
grep -R --include='*.{js,mjs,ts,tsx,jsx}' -nE "from ['\"]stable['\"]|require\(['\"]stable['\"]\)" . && { warn "Direct 'stable' usage detected (use native Array.prototype.sort)."; found_any=1; } || true
grep -R --include='*.{js,mjs,ts,tsx,jsx}' -nE "from ['\"]inflight['\"]|require\(['\"]inflight['\"]\)" . && { warn "Direct 'inflight' usage detected (replace with keyed coalescing or lru-cache pattern)."; found_any=1; } || true
if [ $found_any -eq 0 ]; then
  say "No direct imports of q/stable/inflight found (likely transitive)."
fi

# -------- fresh install + build --------
say "Reinstalling dependencies (clean)…"
rm -rf node_modules package-lock.json
npm i

say "Running build…"
if npm run -s build; then
  say "Build succeeded."
else
  warn "Build script failed. If you use Vite/Webpack instead of Rollup, ensure the correct build command is set in package.json."
fi

say "Done. Review warnings above (if any) and run your app."

