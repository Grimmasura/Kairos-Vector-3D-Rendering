#!/usr/bin/env bash
set -euo pipefail

# --- config ---
APP_NAME="kairos-vector-3d-rendering"
REPO_URL="${REPO_URL:-https://github.com/Grimmasura/Kairos-Vector-3D-Rendering}"
PKGVER_DEFAULT="0.1.0"

# --- sanity checks / deps (Arch) ---
need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1"; MISSING=1; }; }
MISSING=0
for b in git node npm makepkg; do need "$b"; done
if [[ "${MISSING:-0}" == "1" ]]; then
  echo "Install deps: sudo pacman -S --needed git nodejs npm base-devel"
  exit 1
fi

# electron runtime is a runtime dep; we'll rely on system electron
if ! command -v electron >/dev/null 2>&1; then
  echo "Installing system electron..."
  sudo pacman -S --needed electron
fi

# --- clone if not already here ---
if [ ! -d ".git" ]; then
  echo "Cloning repo..."
  git clone "$REPO_URL" "$APP_NAME"
  cd "$APP_NAME"
else
  echo "Using existing working directory: $(pwd)"
fi

# --- ensure project root ---
ROOT="$(pwd)"

# --- add electron wrapper ---
mkdir -p electron
cat > electron/main.js <<'JS'
const { app, BrowserWindow } = require("electron");

function createWindow () {
  const win = new BrowserWindow({
    width: 1280,
    height: 800,
    frame: false,            // frameless window
    backgroundColor: "#000000",
    autoHideMenuBar: true,
    webPreferences: { nodeIntegration: false, contextIsolation: true }
  });

  // Prefer local build if present, else optional env override, else Vercel
  const path = require("path");
  const fs = require("fs");
  const distIndex = path.join(__dirname, "../dist/index.html");
  const envUrl = process.env.KAIROS_URL;
  if (fs.existsSync(distIndex)) {
    win.loadURL(`file://${distIndex}`);
  } else if (envUrl) {
    win.loadURL(envUrl);
  } else {
    win.loadURL("https://kairos-vector-3-d-rendering.vercel.app/");
  }

  if (process.env.KIOSK === "1") win.setFullScreen(true);
}

app.whenReady().then(createWindow);
app.on("window-all-closed", () => { if (process.platform !== "darwin") app.quit(); });
JS

# --- patch or create package.json ---
if [ -f package.json ]; then
  echo "Patching existing package.json..."
  node - <<'NODE'
const fs = require('fs');
const pkg = JSON.parse(fs.readFileSync('package.json','utf8'));
pkg.main = pkg.main || 'electron/main.js';
pkg.scripts = Object.assign({
  "dev": "electron .",
  "start": "electron .",
  "build": pkg.scripts?.build || "echo \"(hint) add real build step (vite/webpack) if needed\""
}, pkg.scripts || {});
pkg.devDependencies = Object.assign({ "electron": "^31.0.0" }, pkg.devDependencies || {});
fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2));
NODE
else
  echo "Creating package.json..."
  cat > package.json <<JSON
{
  "name": "${APP_NAME}",
  "version": "${PKGVER_DEFAULT}",
  "description": "Kairos Vector 3D Rendering — frameless Electron wrapper",
  "main": "electron/main.js",
  "type": "module",
  "scripts": {
    "dev": "electron .",
    "start": "electron .",
    "build": "echo \"(hint) add real build step (vite/webpack) if needed\""
  },
  "devDependencies": { "electron": "^31.0.0" }
}
JSON
fi

# --- optional icon placeholder ---
mkdir -p icons
if [ ! -f icons/kairos.png ]; then
  # generate a tiny placeholder if none exists
  echo -n > icons/kairos.png
fi

# --- install JS deps & try build (non-fatal if not defined for your frontend) ---
echo "Installing npm deps..."
npm ci || npm install
echo "Running build (non-fatal if not defined for your frontend)..."
npm run build || true

# --- PKGBUILD ---
mkdir -p pkg
cat > pkg/PKGBUILD <<'PKG'
# Maintainer: Joshua Robert Humphrey <you@example.com>
pkgname=kairos-vector-3d-rendering
pkgver=0.1.0
pkgrel=1
pkgdesc="Kairos Vector 3D Rendering (HFCTM-II) — frameless Electron app"
arch=('x86_64')
url="https://github.com/Grimmasura/Kairos-Vector-3D-Rendering"
license=('MIT')
depends=('electron' 'hicolor-icon-theme')
makedepends=('git' 'nodejs' 'npm')
source=("git+$url#branch=main")
sha256sums=('SKIP')

pkgver() {
  cd "$srcdir/Kairos-Vector-3D-Rendering"
  git describe --tags --always 2>/dev/null || echo "0.1.0"
}

build() {
  cd "$srcdir/Kairos-Vector-3D-Rendering"
  npm ci || npm install
  npm run build || true

  mkdir -p app
  cp -r electron app/
  if [ -d "dist" ]; then
    cp -r dist app/
  else
    [ -d "public" ] && { mkdir -p app/dist; cp -r public/* app/dist/ 2>/dev/null || true; }
    [ -f "index.html" ] && { mkdir -p app/dist; cp index.html app/dist/; }
    [ -d "src" ] && cp -r src app/dist/src 2>/dev/null || true
  fi

  mkdir -p app/icons
  [ -d icons ] && cp -r icons/* app/icons/ 2>/dev/null || true
}

package() {
  cd "$srcdir/Kairos-Vector-3D-Rendering"

  install -d "$pkgdir/usr/lib/$pkgname"
  cp -r app/* "$pkgdir/usr/lib/$pkgname/"

  install -d "$pkgdir/usr/bin"
  cat > "$pkgdir/usr/bin/kairos-vector" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
APPDIR="/usr/lib/kairos-vector-3d-rendering"
export KAIROS_URL="${KAIROS_URL:-}"
exec electron "$APPDIR/electron/main.js" "$@"
EOF
  chmod +x "$pkgdir/usr/bin/kairos-vector"

  install -d "$pkgdir/usr/share/applications"
  cat > "$pkgdir/usr/share/applications/kairos-vector.desktop" <<'EOF'
[Desktop Entry]
Name=Kairos Vector 3D Rendering
Comment=HFCTM-II aligned toroidal glyph renderer
Exec=kairos-vector
Terminal=false
Type=Application
Categories=Graphics;Science;Visualization;
StartupWMClass=KairosVector
EOF

  if [ -f "icons/kairos.png" ]; then
    install -Dm644 "icons/kairos.png" "$pkgdir/usr/share/icons/hicolor/512x512/apps/kairos-vector.png"
    sed -i 's|^Exec=.*|&\nIcon=kairos-vector|' "$pkgdir/usr/share/applications/kairos-vector.desktop"
  fi

  [ -f "LICENSE" ] && install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
PKG

# --- build Arch package ---
echo "Building Arch package…"
pushd pkg >/dev/null
makepkg -si --noconfirm
popd >/dev/null

echo
echo "✔ Installed. Launch with: kairos-vector"
echo "   (Optional) Fullscreen kiosk: KIOSK=1 kairos-vector"
echo "   (Optional) Remote URL: KAIROS_URL=https://kairos-vector-3-d-rendering.vercel.app/ kairos-vector"
