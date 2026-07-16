#!/usr/bin/env zsh
#
# install-mathiasbynens-dotfiles.zsh
# Safe staged installer for https://github.com/mathiasbynens/dotfiles
#
# WHY THIS EXISTS: the upstream bootstrap.sh does an unattended rsync of
# every dotfile straight into $HOME, and ships a .macos script that flips
# ~300 hidden macOS system defaults. The upstream README explicitly warns
# not to run either blindly. This wrapper never touches $HOME until you've
# reviewed a diff and passed --apply, and never runs .macos unless you pass
# --macos on top of that.
#
# Usage:
#   ./install-mathiasbynens-dotfiles.zsh [OPTIONS]
#
# Options:
#   --stage-dir <path>   Where to clone/stage the repo (default: ~/.dotfiles-staging)
#   --diff                Clone/update staging dir and show what WOULD change (default action)
#   --apply               Actually rsync staged dotfiles into $HOME (backs up first)
#   --macos                Additionally run .macos (macOS system defaults) — requires --apply, asks for typed confirmation
#   --brew                Additionally run brew.sh (installs Homebrew + full package list) — requires --apply, asks for typed confirmation
#   --restore              Restore $HOME dotfiles from the most recent backup
#   --list-backups          List available backups
#   --dry-run              With --apply/--macos/--brew: print actions only, change nothing
#   -h, --help              Show this help
#
# Files handled by --apply:
#   everything in the repo except README.md, bootstrap.sh, .macos, LICENSE-MIT.txt,
#   brew.sh, .osx, .DS_Store, .git, .gitignore, .gitattributes (exact-name matches,
#   not globs) — i.e. the actual dotfiles (.zshrc, .gitconfig, .vimrc, etc.). This list
#   is NOT a mirror of upstream bootstrap.sh's own rsync --exclude list -- upstream
#   never excludes .macos/brew.sh (this wrapper does, deliberately, so those stay
#   gated behind --macos/--brew) and does exclude .DS_Store.

set -uo pipefail

# shellcheck disable=SC2296  # zsh-only prompt-expansion idiom for "this script's own path"; no bash equivalent
SCRIPT_PATH="${(%):-%x}"

REPO_URL="https://github.com/mathiasbynens/dotfiles.git"
STAGE_DIR="${HOME}/.dotfiles-staging"
BACKUP_ROOT="${HOME}/.dotfiles-backups"

ACTION="diff"
DRY_RUN=false
DO_MACOS=false
DO_BREW=false

if [[ -t 1 ]]; then
  :
fi
info()  { print -P "%F{blue}[INFO]%f  $*"; }
ok()    { print -P "%F{green}[OK]%f    $*"; }
warn()  { print -P "%F{yellow}[WARN]%f  $*"; }
err()   { print -P "%F{red}[ERROR]%f $*" >&2; }

usage() {
  local code="${1:-0}"
  sed -n '2,30p' "$SCRIPT_PATH" | sed 's/^# \{0,1\}//'
  exit "$code"
}

while (( $# )); do
  case "$1" in
    --stage-dir)
      if (( $# < 2 )); then
        err "--stage-dir requires a value"
        usage 1
      fi
      STAGE_DIR="$2"; shift 2 ;;
    --diff)         ACTION="diff"; shift ;;
    --apply)        ACTION="apply"; shift ;;
    --restore)      ACTION="restore"; shift ;;
    --list-backups) ACTION="list-backups"; shift ;;
    --macos)        DO_MACOS=true; shift ;;
    --brew)         DO_BREW=true; shift ;;
    --dry-run)      DRY_RUN=true; shift ;;
    -h|--help)      usage 0 ;;
    *) err "Unknown argument: $1"; usage 1 ;;
  esac
done

# Wrapper-defined exclude list (exact-name matches, not globs -- see header
# comment). Not a mirror of upstream's own rsync --exclude list.
EXCLUDES=(README.md bootstrap.sh .macos LICENSE-MIT.txt brew.sh .osx .DS_Store .git .gitignore .gitattributes)

is_excluded() {
  local name="$1"
  local ex
  for ex in "${EXCLUDES[@]}"; do
    [[ "$name" == "$ex" ]] && return 0
  done
  return 1
}

# For a directory, `diff -rq` reports a difference whenever dst has ANY extra
# file not in src -- which is always true for the merge case (e.g. the
# user's own scripts alongside merged-in dotfiles in ~/bin), permanently
# flagging such directories as MODIFIED/changed on every run even when
# nothing from src actually changed. dir_matches instead checks only that
# every file src has is present in dst with identical content; extra files
# in dst are not a mismatch. NOTE: this deliberately does not detect or
# prune files that a *previous* apply installed from src but upstream has
# since removed -- auto-deleting files in $HOME based on a heuristic risks
# deleting a file the user added themselves, which is exactly the kind of
# surprise this tool exists to avoid. Such staleness is a known, accepted
# limitation, not a bug this function tries to solve.
dir_matches() {
  local s="$1" d="$2" f rel
  [[ -d "$d" ]] || return 1
  for f in "${s}"/**/*(N^/D); do
    rel="${f#"${s}"/}"
    if [[ -L "$f" ]]; then
      # Compare symlinks by target path, not content: [[ -e ]] follows
      # symlinks, so a dangling one (e.g. bin/subl pointing at an app
      # that isn't installed) would wrongly read as "missing" and cmp
      # would try to read a target that may not exist.
      [[ -L "${d}/${rel}" ]] || return 1
      [[ "$(readlink "$f")" == "$(readlink "${d}/${rel}")" ]] || return 1
    else
      [[ -e "${d}/${rel}" ]] || return 1
      cmp -s "$f" "${d}/${rel}" || return 1
    fi
  done
  return 0
}

is_unchanged() {
  local s="$1" d="$2"
  [[ -e "$d" ]] || return 1
  if [[ -d "$s" ]]; then
    dir_matches "$s" "$d"
  else
    diff -q "$s" "$d" >/dev/null 2>&1
  fi
}

# ---- clone or update staging dir ----
# refresh=true always fetches (used by --diff, so a review shows current
# upstream). refresh=false reuses whatever is already staged without
# fetching (used by --apply) so that content applied is the exact content
# a prior --diff reviewed, rather than silently re-fetching to whatever
# upstream has changed to in between the two separate invocations.
sync_stage() {
  local refresh="${1:-true}"
  if [[ -d "${STAGE_DIR}/.git" ]]; then
    if [[ "$refresh" == true ]]; then
      info "Updating existing staging clone: ${STAGE_DIR}"
      git -C "$STAGE_DIR" fetch --quiet origin || { err "git fetch failed"; exit 1; }
      git -C "$STAGE_DIR" reset --quiet --hard origin/HEAD || { err "git reset failed"; exit 1; }
    else
      info "Using already-staged clone: ${STAGE_DIR} (run --diff first to refresh)"
    fi
  else
    info "Cloning ${REPO_URL} -> ${STAGE_DIR}"
    git clone --quiet "$REPO_URL" "$STAGE_DIR" || { err "git clone failed"; exit 1; }
  fi
}

# List of top-level dotfiles that would be installed (name, staged path)
staged_files() {
  local f base
  for f in "${STAGE_DIR}"/.*(N) "${STAGE_DIR}"/*(N); do
    base="${f:t}"
    [[ "$base" == "." || "$base" == ".." ]] && continue
    is_excluded "$base" && continue
    print -r -- "$base"
  done
}

# ---- diff ----
do_diff() {
  sync_stage true
  info "Files that would be installed into \$HOME (upstream bootstrap.sh set, minus excludes):"
  local base changed=0
  for base in $(staged_files); do
    local src="${STAGE_DIR}/${base}"
    local dst="${HOME}/${base}"
    if [[ ! -e "$dst" ]]; then
      print -P "  %F{green}NEW%f       ${base}"
      changed=1
    elif ! is_unchanged "$src" "$dst"; then
      print -P "  %F{yellow}MODIFIED%f  ${base}"
      changed=1
    else
      print -P "  %F{240}unchanged%f  ${base}"
    fi
  done
  if (( changed )); then
    info "Run with --apply to install (backs up every touched file first)."
  else
    ok "Nothing to change — \$HOME already matches staged dotfiles."
  fi
  if $DO_MACOS || $DO_BREW; then
    warn "--macos/--brew require --apply; ignored in --diff mode."
  fi
}

# ---- apply ----
do_apply() {
  sync_stage false
  local ts backup_dir
  ts="$(date +%Y%m%d-%H%M%S)"
  backup_dir="${BACKUP_ROOT}/${ts}"

  local base src dst any=0
  for base in $(staged_files); do
    src="${STAGE_DIR}/${base}"
    dst="${HOME}/${base}"
    if is_unchanged "$src" "$dst"; then
      continue  # identical, nothing to do
    fi
    any=1
    if $DRY_RUN; then
      [[ -e "$dst" ]] && info "[dry-run] Would back up ${dst} -> ${backup_dir}/${base}"
      info "[dry-run] Would install ${src} -> ${dst}"
      continue
    fi
    if [[ -e "$dst" ]]; then
      mkdir -p "$backup_dir"
      if ! cp -R "$dst" "${backup_dir}/${base}"; then
        err "Backup of ${dst} failed -- skipping install of ${base}"
        continue
      fi
    fi
    # When src is a directory and dst already exists as one (e.g. a
    # pre-existing ~/bin with the user's own scripts), plain `cp -R src
    # dst` nests src *inside* dst instead of merging into it. Merge via
    # the trailing-/. form in that case; every other case (dst absent,
    # or src a plain file) is already handled correctly by cp -R alone.
    if [[ -d "$src" && -d "$dst" ]]; then
      if cp -R "$src"/. "$dst"/; then
        ok "Installed ${base}"
      else
        err "Failed to install ${base} (merge into ${dst})"
      fi
    else
      if cp -R "$src" "$dst"; then
        ok "Installed ${base}"
      else
        err "Failed to install ${base}"
      fi
    fi
  done

  if (( ! any )); then
    ok "Nothing to apply — \$HOME already matches staged dotfiles."
  elif ! $DRY_RUN; then
    ok "Backup of overwritten files: ${backup_dir}"
    info "Reload your shell (source ~/.zshrc) to pick up changes."
  fi

  if $DO_MACOS; then
    run_macos
  fi
  if $DO_BREW; then
    run_brew
  fi
}

# ---- .macos: system defaults, high blast radius, extra confirmation ----
run_macos() {
  local macos_script="${STAGE_DIR}/.macos"
  if [[ ! -f "$macos_script" ]]; then
    err ".macos not found in staged repo — skipping"
    return 1
  fi
  warn ".macos rewrites ~300 hidden macOS system preferences (Finder, Dock, Safari, screenshots, etc.),"
  warn "using sudo to write system-wide settings outside \$HOME (/Library/Preferences, NVRAM, pmset)."
  warn "--restore only undoes \$HOME dotfiles -- it CANNOT undo anything .macos changes via sudo."
  warn "Review it first: less \"${macos_script}\""
  if $DRY_RUN; then
    info "[dry-run] Would run: ${macos_script}"
    return 0
  fi
  print -n "Type EXACTLY \"apply macos defaults\" to proceed, anything else cancels: "
  read -r confirm
  if [[ "$confirm" != "apply macos defaults" ]]; then
    info "Cancelled .macos run."
    return 0
  fi
  zsh "$macos_script"
  ok ".macos applied. Some settings need a logout/restart to take effect."
}

# ---- brew.sh: installs Homebrew + a large package list, high blast radius ----
run_brew() {
  local brew_script="${STAGE_DIR}/brew.sh"
  if [[ ! -f "$brew_script" ]]; then
    err "brew.sh not found in staged repo — skipping"
    return 1
  fi
  warn "brew.sh assumes Homebrew is ALREADY installed (it does not bootstrap it) and runs"
  warn "brew update/upgrade plus a large, opinionated package/cask install list."
  warn "Review it first: less \"${brew_script}\""
  if $DRY_RUN; then
    info "[dry-run] Would run: ${brew_script}"
    return 0
  fi
  print -n "Type EXACTLY \"apply brew list\" to proceed, anything else cancels: "
  read -r confirm
  if [[ "$confirm" != "apply brew list" ]]; then
    info "Cancelled brew.sh run."
    return 0
  fi
  zsh "$brew_script"
  ok "brew.sh completed."
}

# ---- restore ----
do_restore() {
  if [[ ! -d "$BACKUP_ROOT" ]]; then
    err "No backups found at ${BACKUP_ROOT}"
    exit 1
  fi
  local -a latest_dirs
  latest_dirs=("${BACKUP_ROOT}"/*(/om[1]N))
  if (( ${#latest_dirs} == 0 )); then
    err "No backup snapshots found under ${BACKUP_ROOT}"
    exit 1
  fi
  local dir="${latest_dirs[1]}"
  info "Restoring from ${dir}"
  # (N^/D): every non-directory leaf, including symlinks -- the plain-files-
  # only `.` qualifier used here previously silently skipped symlinked
  # dotfiles (e.g. bin/subl) during restore with no error or warning.
  local f rel
  for f in "${dir}"/**/*(N^/D); do
    rel="${f#"${dir}"/}"
    if $DRY_RUN; then
      info "[dry-run] Would restore ${rel} -> ${HOME}/${rel}"
    else
      mkdir -p "${HOME}/${rel:h}"
      if cp -R "$f" "${HOME}/${rel}"; then
        ok "Restored ${rel}"
      else
        err "Failed to restore ${rel}"
      fi
    fi
  done
}

do_list_backups() {
  if [[ ! -d "$BACKUP_ROOT" ]]; then
    info "No backups yet."
    return 0
  fi
  ls -1t "$BACKUP_ROOT"
}

case "$ACTION" in
  diff)          do_diff ;;
  apply)         do_apply ;;
  restore)       do_restore ;;
  list-backups)  do_list_backups ;;
esac
