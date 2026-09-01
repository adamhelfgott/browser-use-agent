#!/usr/bin/env sh
# bootstrap.sh — make a fresh session (cloud or local) able to use `bu` / `bu-drive`.
# Idempotent. Installs the two uv scripts + config into the standard locations.
#
#   BROWSER_USE_API_KEY=bu_...  sh bootstrap.sh
#   # or, if the key is already in the environment / a mounted secret:
#   sh bootstrap.sh
#
# The bundle here (bu, bu-drive, config.json) carries NO secret. The only secret is
# BROWSER_USE_API_KEY, which must arrive via the environment (or be written to
# ~/.agents/browser/credentials/api_key out of band). Profiles are account-scoped on
# Browser Use's side, so any session with the same key sees the same synced logins.
set -eu

REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/adamhelfgott/browser-use-agent/main}"
BU_HOME="${BU_HOME:-$HOME/.agents/browser}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"

# Siblings come from the repo by default (works when piped `curl … | sh`). If a local
# bundle dir is staged, set BOOTSTRAP_SRC=/path/to/bundle to copy from it instead.
SRC_DIR="${BOOTSTRAP_SRC:-/nonexistent}"
fetch() {  # fetch <name> <dest>
  if [ -f "$SRC_DIR/$1" ]; then cp "$SRC_DIR/$1" "$2"
  else curl -fsSL "$REPO_RAW/$1" -o "$2"; fi
}

echo "bootstrap: installing bu tooling"
mkdir -p "$BIN_DIR" "$BU_HOME/runs" "$BU_HOME/credentials"
chmod 700 "$BU_HOME/credentials" 2>/dev/null || true

# 1. uv (self-contained-script runtime the scripts need)
if ! command -v uv >/dev/null 2>&1; then
  echo "bootstrap: installing uv"
  curl -fsSL https://astral.sh/uv/install.sh | sh
  # uv installs to ~/.local/bin or ~/.cargo/bin; make sure it's on PATH for this run
  export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
fi

# 2. the two scripts
fetch bu "$BIN_DIR/bu"
fetch bu-drive "$BIN_DIR/bu-drive"
chmod +x "$BIN_DIR/bu" "$BIN_DIR/bu-drive"

# 3. config (only if absent — never clobber a customized local config)
if [ ! -f "$BU_HOME/config.json" ]; then
  fetch config.json "$BU_HOME/config.json"
fi

# 3b. the deep instruction doc, so the session can read it locally
fetch BROWSER-USE.md "$BU_HOME/BROWSER-USE.md" 2>/dev/null || true

# 4. the key: prefer an existing key file, else take it from the environment
if [ -n "${BROWSER_USE_API_KEY:-}" ] && [ ! -s "$BU_HOME/credentials/api_key" ]; then
  printf '%s' "$BROWSER_USE_API_KEY" > "$BU_HOME/credentials/api_key"
  chmod 600 "$BU_HOME/credentials/api_key"
fi

case ":$PATH:" in *":$BIN_DIR:"*) : ;; *)
  echo "bootstrap: NOTE add $BIN_DIR to PATH (export PATH=\"$BIN_DIR:\$PATH\")" ;;
esac

if [ -s "$BU_HOME/credentials/api_key" ] || [ -n "${BROWSER_USE_API_KEY:-}" ]; then
  echo "bootstrap: OK — try:  bu models   then   bu which vercel.com"
else
  echo "bootstrap: installed, but NO API KEY found."
  echo "  set BROWSER_USE_API_KEY in the environment, or write it to"
  echo "  $BU_HOME/credentials/api_key (chmod 600), then re-run."
fi
