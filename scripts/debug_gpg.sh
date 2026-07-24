#!/usr/bin/env bash
set -euo pipefail

echo "== shell =="
echo "SHELL=${SHELL:-}"
echo "0=${0:-}"

echo
echo "== environment =="
echo "PATH=${PATH:-}"
echo "GPG_TTY=${GPG_TTY:-}"
echo "GNUPGHOME=${GNUPGHOME:-}"
echo "umask=$(umask)"

echo
echo "== gpg =="
if command -v gpg >/dev/null 2>&1; then
  gpg --version | sed -n '1,2p' || true
  echo
  gpgconf --list-dirs || true
  echo
  echo "agent-socket=$(gpgconf --list-dirs agent-socket 2>/dev/null || true)"
  echo "homedir=$(gpgconf --list-dirs homedir 2>/dev/null || true)"
  echo
  gpg --list-secret-keys --keyid-format=long || true
  echo
  gpg --list-keys --keyid-format=long || true
else
  echo "gpg not found"
fi

echo
echo "== config files =="
gnupg_homedir="$(gpgconf --list-dirs homedir 2>/dev/null || echo "$HOME/.gnupg")"
for f in "$gnupg_homedir/gpg.conf" "$gnupg_homedir/gpg-agent.conf"; do
  if [[ -f "$f" ]]; then
    echo "--- $f ---"
    cat "$f"
  else
    echo "--- $f (missing) ---"
  fi
done

echo
echo "== Homebrew paths =="
if command -v brew >/dev/null 2>&1; then
  echo "brew=$(command -v brew)"
  brew --prefix || true
  brew --prefix gnupg 2>/dev/null || true
  brew --prefix pinentry-mac 2>/dev/null || true
else
  echo "brew not found"
fi

echo
echo "== pinentry =="
if command -v pinentry-mac >/dev/null 2>&1; then
  echo "pinentry-mac=$(command -v pinentry-mac)"
else
  echo "pinentry-mac not found"
fi

echo
echo "== shell startup matches =="
grep -nE 'GPG_TTY|umask|brew shellenv|/opt/homebrew/bin|/usr/local/bin' \
  "$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.profile" "$HOME/.bash_profile" "$HOME/.bashrc" 2>/dev/null || true
