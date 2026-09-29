#!/usr/bin/env bash
# =============================================================================
#  OpenCode workshop setup (Linux, and Windows via WSL)
#
#  Installs OpenCode and configures it to use an OpenRouter endpoint.
#  Run with:   bash setup-opencode.sh
#
#  Safe to run more than once. An existing OpenCode config is backed up first.
# =============================================================================

# ---- FACILITATORS: fill in these values before handing the script out -------

# OpenRouter API base URL. The public endpoint is https://openrouter.ai/api/v1
OPENROUTER_BASE_URL="REPLACE_WITH_OPENROUTER_ENDPOINT_URL"

# OpenRouter API key. Leave the placeholder to make the script ask each
# participant for their own key (recommended), or paste a shared key here.
OPENROUTER_API_KEY="REPLACE_WITH_OPENROUTER_API_KEY"

# Main coding model: OpenRouter model ID exactly as shown on openrouter.ai,
# e.g. "vendor/model-name"
OPENCODE_MODEL="REPLACE_WITH_OPENROUTER_MODEL_ID"

# Small model for light background tasks such as naming sessions.
# Leave the placeholder to use the main model for these too.
OPENCODE_SMALL_MODEL="REPLACE_WITH_OPENROUTER_SMALL_MODEL_ID"

# Only route to OpenRouter providers serving the model at these precisions
# (comma-separated). Match what you will self-host later.
OPENROUTER_PRECISIONS="bf16,fp16"

# OpenCode version to install, e.g. "1.18.33". Empty = latest release.
# Pin a version so every participant runs the same build.
OPENCODE_VERSION=""

# ---- nothing below needs editing -------------------------------------------

set -euo pipefail

CONFIG_DIR="$HOME/.config/opencode"
CONFIG_FILE="$CONFIG_DIR/opencode.json"
KEY_FILE="$CONFIG_DIR/openrouter.key"
BIN_DIR="$HOME/.opencode/bin"

info()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()    { printf '\033[1;32m ok\033[0m %s\n' "$*"; }
fail()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

is_placeholder() { [[ "$1" == REPLACE_WITH_* || -z "$1" ]]; }

# 1. Check the settings and the machine -------------------------------------
info "Checking settings and prerequisites"

is_placeholder "$OPENROUTER_BASE_URL" && fail "OPENROUTER_BASE_URL is not set. Ask the facilitator for an updated script."
is_placeholder "$OPENCODE_MODEL"      && fail "OPENCODE_MODEL is not set. Ask the facilitator for an updated script."
[[ "$OPENROUTER_BASE_URL" == https://* ]] || fail "OPENROUTER_BASE_URL must start with https:// (got: $OPENROUTER_BASE_URL)"
OPENROUTER_BASE_URL="${OPENROUTER_BASE_URL%/}"   # drop a trailing slash
if is_placeholder "$OPENCODE_SMALL_MODEL"; then
  OPENCODE_SMALL_MODEL="$OPENCODE_MODEL"
fi
[[ -n "${OPENROUTER_PRECISIONS// /}" ]] || fail "OPENROUTER_PRECISIONS is empty. Use e.g. \"bf16,fp16\"."

[[ "$(uname -s)" == "Linux" ]] || fail "This script is for Linux or WSL. On Windows, use setup-opencode.ps1."
for cmd in curl tar; do
  command -v "$cmd" >/dev/null 2>&1 || fail "'$cmd' is required. Install it first, e.g.: sudo apt install $cmd"
done
command -v git >/dev/null 2>&1 || printf '    note: git is not installed. You will need it in the workshop (sudo apt install git).\n'
ok "Prerequisites found"

# 2. Get the API key -----------------------------------------------------------
if is_placeholder "$OPENROUTER_API_KEY"; then
  [[ -r /dev/tty ]] || fail "No API key in the script and no terminal to ask for one."
  printf 'Paste your OpenRouter API key (input is hidden) and press Enter: '
  IFS= read -rs OPENROUTER_API_KEY < /dev/tty
  printf '\n'
fi
OPENROUTER_API_KEY="$(printf '%s' "$OPENROUTER_API_KEY" | tr -d '[:space:]')"
[[ -n "$OPENROUTER_API_KEY" ]] || fail "No API key given."

# 3. Install OpenCode ----------------------------------------------------------
info "Installing OpenCode ${OPENCODE_VERSION:-(latest)}"
installer_args=()
[[ -n "$OPENCODE_VERSION" ]] && installer_args+=(--version "$OPENCODE_VERSION")
curl -fsSL https://opencode.ai/install | bash -s -- ${installer_args[@]+"${installer_args[@]}"}

export PATH="$BIN_DIR:$PATH"
command -v opencode >/dev/null 2>&1 || fail "OpenCode did not install. Scroll up for the installer's message."
ok "OpenCode $(opencode --version 2>/dev/null || echo '') installed in $BIN_DIR"

# 4. Write the configuration --------------------------------------------------
info "Writing configuration to $CONFIG_DIR"
mkdir -p "$CONFIG_DIR"

stamp="$(date +%Y%m%d-%H%M%S)"
for existing in "$CONFIG_DIR/opencode.json" "$CONFIG_DIR/opencode.jsonc"; do
  if [[ -f "$existing" ]]; then
    mv "$existing" "$existing.bak-$stamp"
    printf '    backed up %s\n' "$existing.bak-$stamp"
  fi
done

# The key lives in its own file, readable only by you.
( umask 077; printf '%s' "$OPENROUTER_API_KEY" > "$KEY_FILE" )
chmod 600 "$KEY_FILE"

# Routing rules sent to OpenRouter with every request for these models:
# only the chosen precisions, and only providers that don't store or train on data.
precisions_json="$(printf '%s' "$OPENROUTER_PRECISIONS" | tr -d ' ' | sed 's/,/", "/g; s/^/"/; s/$/"/')"
model_entry() {
  printf '        "%s": {\n' "$1"
  printf '          "options": {\n'
  printf '            "provider": {\n'
  printf '              "quantizations": [%s],\n' "$precisions_json"
  printf '              "data_collection": "deny"\n'
  printf '            }\n'
  printf '          }\n'
  printf '        }'
}
if [[ "$OPENCODE_SMALL_MODEL" == "$OPENCODE_MODEL" ]]; then
  models_json="$(model_entry "$OPENCODE_MODEL")"
  whitelist_json="\"$OPENCODE_MODEL\""
else
  models_json="$(model_entry "$OPENCODE_MODEL"),
$(model_entry "$OPENCODE_SMALL_MODEL")"
  whitelist_json="\"$OPENCODE_MODEL\", \"$OPENCODE_SMALL_MODEL\""
fi

cat > "$CONFIG_FILE" <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "model": "openrouter/$OPENCODE_MODEL",
  "small_model": "openrouter/$OPENCODE_SMALL_MODEL",
  "enabled_providers": ["openrouter"],
  "provider": {
    "openrouter": {
      "options": {
        "baseURL": "$OPENROUTER_BASE_URL",
        "apiKey": "{file:~/.config/opencode/openrouter.key}"
      },
      "models": {
$models_json
      },
      "whitelist": [$whitelist_json]
    }
  },
  "share": "disabled",
  "autoupdate": false
}
EOF
ok "Configuration written"

# 5. Done ----------------------------------------------------------------------
cat <<EOF

 OpenCode is installed and configured.

   Model:        openrouter/$OPENCODE_MODEL
   Small model:  openrouter/$OPENCODE_SMALL_MODEL
   Precision:    $OPENROUTER_PRECISIONS
   Endpoint:     $OPENROUTER_BASE_URL
   Config:       $CONFIG_FILE

 Next: open a NEW terminal (so PATH is updated), then run:

   opencode run "Reply with the single word: ready"

 If it replies, you're done. Start OpenCode in a project folder with:  opencode

EOF
