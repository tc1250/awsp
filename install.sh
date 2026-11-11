#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${AWSP_INSTALL_DIR:-$HOME/.awsp}"
AWSP_SH="$INSTALL_DIR/awsp.sh"
SOURCE_LINE="[ -f \"\$HOME/.awsp/awsp.sh\" ] && source \"\$HOME/.awsp/awsp.sh\""
if [[ "$INSTALL_DIR" != "$HOME/.awsp" ]]; then
  SOURCE_LINE="[ -f \"$AWSP_SH\" ] && source \"$AWSP_SH\""
fi
MARKER="# awsp — AWS credential & profile manager"

mkdir -p "$INSTALL_DIR"
if [[ "$REPO_DIR/awsp.sh" != "$AWSP_SH" ]]; then
  cp "$REPO_DIR/awsp.sh" "$AWSP_SH"
  echo "Installed awsp.sh to $AWSP_SH"
fi

add_to_rc() {
  local rc_file="$1"
  if [[ ! -f "$rc_file" ]]; then
    return 0
  fi

  if grep -Fq "awsp.sh" "$rc_file" 2>/dev/null; then
    echo "Already configured in $rc_file"
    return 0
  fi

  printf '\n%s\n%s\n' "$MARKER" "$SOURCE_LINE" >> "$rc_file"
  echo "Added awsp source line to $rc_file"
}

if [[ ! -f "$HOME/.zshrc" && ! -f "$HOME/.bashrc" && ! -f "$HOME/.bash_profile" ]]; then
  touch "$HOME/.zshrc"
fi

add_to_rc "$HOME/.zshrc"
add_to_rc "$HOME/.bashrc"
if [[ ! -f "$HOME/.bashrc" && -f "$HOME/.bash_profile" ]]; then
  add_to_rc "$HOME/.bash_profile"
fi

echo ""
echo "Installation complete!"
echo "Reload your shell or run:"
echo "  source \"$AWSP_SH\""
