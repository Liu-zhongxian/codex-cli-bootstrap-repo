#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=0
HOMEBREW_DRY_RUN_ANNOUNCED=0
SKIP_GIT=0
SKIP_NODE=0
SKIP_NPM=0
CODEX_VERSION="${CODEX_VERSION:-latest}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --skip-git)
      SKIP_GIT=1
      shift
      ;;
    --skip-node)
      SKIP_NODE=1
      shift
      ;;
    --skip-npm)
      SKIP_NPM=1
      shift
      ;;
    --codex-version)
      if [[ $# -lt 2 ]]; then
        echo "[error] --codex-version requires a value."
        exit 1
      fi
      CODEX_VERSION="$2"
      shift 2
      ;;
    --codex-version=*)
      CODEX_VERSION="${1#--codex-version=}"
      shift
      ;;
    *)
      echo "[error] Unsupported argument: $1"
      exit 1
      ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "[error] This bootstrap script only supports macOS."
  exit 1
fi

MIN_GIT_VERSION="${MIN_GIT_VERSION:-2.53.0}"
MIN_NODE_VERSION="${MIN_NODE_VERSION:-22.22.2}"
MIN_NPM_VERSION="${MIN_NPM_VERSION:-8.0.0}"
BOOTSTRAP_NODE_FORMULA="${BOOTSTRAP_NODE_FORMULA:-node}"
BOOTSTRAP_GIT_FORMULA="${BOOTSTRAP_GIT_FORMULA:-git}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NPM_CACHE_DIR="$WORKSPACE_ROOT/.npm-cache"
HOMEBREW_INSTALL_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"

write_step() {
  printf '==> %s\n' "$1"
}

write_info() {
  printf '[info] %s\n' "$1"
}

write_warning() {
  printf '[warning] %s\n' "$1"
}

write_dry_run() {
  printf '[dry-run] %s\n' "$1"
}

fail() {
  printf '[error] %s\n' "$1" >&2
  exit 1
}

ensure_directory() {
  mkdir -p "$1"
}

ensure_npm_cache() {
  ensure_directory "$NPM_CACHE_DIR"
}

validate_codex_version() {
  local value="$1"
  if [[ ! "$value" =~ ^(latest|[0-9]+(\.[0-9]+){0,2})$ ]]; then
    fail "Unsupported Codex version specifier: $value. Use latest or an exact version like 0.125.0."
  fi
}

parse_version_text() {
  local input="$1"
  if [[ "$input" =~ ([0-9]+(\.[0-9]+){0,3}) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  fi
}

normalize_version() {
  local value="$1"
  local parts=()
  local i
  IFS='.' read -r -a parts <<< "$value"
  for (( i=${#parts[@]}; i<3; i++ )); do
    parts+=(0)
  done
  printf '%s.%s.%s\n' "${parts[0]:-0}" "${parts[1]:-0}" "${parts[2]:-0}"
}

version_ge() {
  local current
  local minimum
  local current_parts=()
  local minimum_parts=()
  local i

  current="$(normalize_version "$1")"
  minimum="$(normalize_version "$2")"
  IFS='.' read -r -a current_parts <<< "$current"
  IFS='.' read -r -a minimum_parts <<< "$minimum"

  for (( i=0; i<3; i++ )); do
    if (( 10#${current_parts[i]} > 10#${minimum_parts[i]} )); then
      return 0
    fi
    if (( 10#${current_parts[i]} < 10#${minimum_parts[i]} )); then
      return 1
    fi
  done

  return 0
}

max_version() {
  if version_ge "$1" "$2"; then
    printf '%s\n' "$(normalize_version "$1")"
  else
    printf '%s\n' "$(normalize_version "$2")"
  fi
}

get_command_location() {
  command -v "$1" 2>/dev/null || true
}

get_tool_version() {
  local command_name="$1"
  shift
  local command_path
  local output

  command_path="$(get_command_location "$command_name")"
  if [[ -z "$command_path" ]]; then
    return 0
  fi

  if ! output="$("$command_path" "$@" 2>&1)"; then
    return 0
  fi

  parse_version_text "$output"
}

get_tool_state() {
  local command_name="$1"
  shift
  local command_path
  local version

  command_path="$(get_command_location "$command_name")"
  if [[ -z "$command_path" ]]; then
    return 1
  fi

  version="$(get_tool_version "$command_name" "$@")"
  printf '%s|%s\n' "$command_path" "$version"
}

assert_tool_state() {
  local display_name="$1"
  local tool_path="$2"
  local tool_version="$3"
  local minimum_version="$4"

  if [[ -z "$tool_path" ]]; then
    fail "$display_name was not found on PATH after the installation step."
  fi

  if [[ -z "$tool_version" ]]; then
    fail "$display_name was found at $tool_path, but its version could not be determined."
  fi

  if ! version_ge "$tool_version" "$minimum_version"; then
    fail "$display_name version $tool_version at $tool_path does not meet the minimum requirement $minimum_version."
  fi

  write_info "Resolved $display_name path:    $tool_path"
  write_info "Resolved $display_name version: $tool_version"
}

refresh_homebrew_path() {
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    return
  fi

  if [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

run_checked() {
  local description="$1"
  shift

  if (( DRY_RUN )); then
    write_dry_run "$description"
    return 0
  fi

  write_step "$description"
  "$@"
}

is_latest_codex_version() {
  [[ "$CODEX_VERSION" == "latest" ]]
}

get_codex_package_spec() {
  if is_latest_codex_version; then
    printf '@openai/codex@latest\n'
  else
    printf '@openai/codex@%s\n' "$CODEX_VERSION"
  fi
}

get_default_codex_metadata() {
  printf 'latest|>=16|16.0.0\n'
}

get_codex_metadata() {
  local npm_command
  local raw
  local parsed
  local package_spec

  npm_command="$(get_command_location npm)"
  if [[ -z "$npm_command" ]]; then
    write_info 'npm is not available, falling back to a safe default Codex requirement.'
    get_default_codex_metadata
    return
  fi

  ensure_npm_cache
  package_spec="$(get_codex_package_spec)"

  if ! raw="$("$npm_command" --cache "$NPM_CACHE_DIR" view "$package_spec" version engines --json 2>/dev/null)"; then
    write_info 'Falling back to a safe default Codex requirement because npm registry metadata could not be fetched.'
    get_default_codex_metadata
    return
  fi

  if ! parsed="$(printf '%s' "$raw" | node -e '
    const fs = require("node:fs");
    const input = fs.readFileSync(0, "utf8");
    const data = JSON.parse(input);
    const version = data.version || "latest";
    const range = (data.engines && data.engines.node) || ">=16";
    const matches = [...range.matchAll(/>=\s*(\d+(?:\.\d+){0,2})/g)];
    const normalize = (value) => {
      const parts = value.split(".");
      while (parts.length < 3) parts.push("0");
      return parts.slice(0, 3).map((part) => Number(part)).join(".");
    };
    const compare = (left, right) => {
      const a = left.split(".").map(Number);
      const b = right.split(".").map(Number);
      for (let i = 0; i < 3; i += 1) {
        if (a[i] !== b[i]) return a[i] - b[i];
      }
      return 0;
    };
    const minVersion = matches.length
      ? matches.map((match) => normalize(match[1])).sort(compare)[0]
      : "16.0.0";
    process.stdout.write([version, range, minVersion].join("|"));
  ' 2>/dev/null)"; then
    write_info 'Falling back to a safe default Codex requirement because npm package metadata could not be parsed.'
    get_default_codex_metadata
    return
  fi

  printf '%s\n' "$parsed"
}

ensure_homebrew() {
  refresh_homebrew_path
  if [[ -n "$(get_command_location brew)" ]]; then
    return
  fi

  write_warning 'Homebrew is not installed. This bootstrap will install Homebrew system-wide.'

  if (( DRY_RUN )); then
    if (( HOMEBREW_DRY_RUN_ANNOUNCED == 0 )); then
      write_dry_run "Installing Homebrew from $HOMEBREW_INSTALL_URL"
      HOMEBREW_DRY_RUN_ANNOUNCED=1
    fi
    return
  fi

  write_step "Installing Homebrew from $HOMEBREW_INSTALL_URL"
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL "$HOMEBREW_INSTALL_URL")"
  refresh_homebrew_path

  if [[ -z "$(get_command_location brew)" ]]; then
    fail 'Homebrew installation completed but brew was not found on PATH.'
  fi
}

ensure_brew_package() {
  local formula="$1"
  local display_name="$2"
  local brew_command

  ensure_homebrew
  refresh_homebrew_path
  brew_command="$(get_command_location brew)"
  if [[ -z "$brew_command" ]]; then
    if (( DRY_RUN )); then
      run_checked "Installing $display_name with Homebrew"
      return
    fi

    fail 'brew was not found after the Homebrew installation step.'
  fi

  if "$brew_command" list --formula "$formula" >/dev/null 2>&1; then
    run_checked "Upgrading $display_name with Homebrew" "$brew_command" upgrade "$formula"
  else
    run_checked "Installing $display_name with Homebrew" "$brew_command" install "$formula"
  fi
}

ensure_minimum_git_installed() {
  ensure_brew_package "$BOOTSTRAP_GIT_FORMULA" "Git"
}

ensure_minimum_node_installed() {
  ensure_brew_package "$BOOTSTRAP_NODE_FORMULA" "Node.js (includes npm)"
}

ensure_minimum_npm_installed() {
  local npm_command
  npm_command="$(get_command_location npm)"
  if [[ -z "$npm_command" ]]; then
    fail 'npm was not found while trying to upgrade npm.'
  fi

  ensure_npm_cache
  run_checked "Upgrading npm to meet the minimum version requirement" \
    "$npm_command" --cache "$NPM_CACHE_DIR" install -g npm@latest
}

ensure_git() {
  local git_state=''
  local git_path=''
  local git_version=''

  if git_state="$(get_tool_state git --version 2>/dev/null)"; then
    IFS='|' read -r git_path git_version <<< "$git_state"
  fi

  if [[ -z "$git_path" ]]; then
    if (( SKIP_GIT )); then
      fail 'Git is required but --skip-git was specified and git was not found.'
    fi

    write_info 'Git is not installed.'
    ensure_minimum_git_installed
    if (( DRY_RUN )); then
      write_dry_run 'Verifying Git command path and version after installation'
      return
    fi
    refresh_homebrew_path
    git_state="$(get_tool_state git --version || true)"
    IFS='|' read -r git_path git_version <<< "$git_state"
  elif ! version_ge "$git_version" "$MIN_GIT_VERSION"; then
    if (( SKIP_GIT )); then
      fail "Git version $git_version is below the minimum requirement $MIN_GIT_VERSION and --skip-git was specified."
    fi

    write_info "Detected git version: $git_version"
    write_info "Minimum git version:  $MIN_GIT_VERSION"
    ensure_minimum_git_installed
    if (( DRY_RUN )); then
      write_dry_run 'Verifying Git command path and version after upgrade'
      return
    fi
    refresh_homebrew_path
    git_state="$(get_tool_state git --version || true)"
    IFS='|' read -r git_path git_version <<< "$git_state"
  fi

  assert_tool_state "Git" "$git_path" "$git_version" "$MIN_GIT_VERSION"
}

ensure_node_toolchain() {
  local node_state=''
  local node_path=''
  local node_version=''
  local npm_state=''
  local npm_path=''
  local npm_version=''
  local codex_metadata=''
  local codex_latest_version=''
  local codex_node_range=''
  local codex_min_node_version=''
  local effective_min_node_version=''

  codex_metadata="$(get_codex_metadata)"
  IFS='|' read -r codex_latest_version codex_node_range codex_min_node_version <<< "$codex_metadata"
  effective_min_node_version="$(max_version "$MIN_NODE_VERSION" "$codex_min_node_version")"

  if node_state="$(get_tool_state node -v 2>/dev/null)"; then
    IFS='|' read -r node_path node_version <<< "$node_state"
  fi

  if [[ -z "$node_path" ]]; then
    if (( SKIP_NODE )); then
      fail 'Node.js is required but --skip-node was specified and node was not found.'
    fi

    write_info 'Node.js is not installed.'
    ensure_minimum_node_installed
    if (( DRY_RUN )); then
      write_dry_run 'Verifying Node.js and npm command paths and versions after installation'
      return
    fi
    refresh_homebrew_path
    node_state="$(get_tool_state node -v || true)"
    IFS='|' read -r node_path node_version <<< "$node_state"
  elif ! version_ge "$node_version" "$effective_min_node_version"; then
    if (( SKIP_NODE )); then
      fail "Node.js version $node_version is below the minimum requirement $effective_min_node_version and --skip-node was specified."
    fi

    write_info "Detected node version: $node_version"
    write_info "Minimum node version:  $effective_min_node_version"
    ensure_minimum_node_installed
    if (( DRY_RUN )); then
      write_dry_run 'Verifying Node.js and npm command paths and versions after upgrade'
      return
    fi
    refresh_homebrew_path
    node_state="$(get_tool_state node -v || true)"
    IFS='|' read -r node_path node_version <<< "$node_state"
  fi

  assert_tool_state "Node.js" "$node_path" "$node_version" "$effective_min_node_version"

  if npm_state="$(get_tool_state npm -v 2>/dev/null)"; then
    IFS='|' read -r npm_path npm_version <<< "$npm_state"
  fi

  if [[ -z "$npm_path" ]]; then
    if (( SKIP_NODE || SKIP_NPM )); then
      fail 'npm was not found after resolving Node.js, and automatic npm repair was disabled by --skip-node or --skip-npm.'
    fi

    write_info 'npm was not found. Reinstalling Node.js to restore npm.'
    ensure_minimum_node_installed
    if (( DRY_RUN )); then
      write_dry_run 'Verifying npm command path and version after the Node.js repair step'
      return
    fi
    refresh_homebrew_path
    node_state="$(get_tool_state node -v || true)"
    IFS='|' read -r node_path node_version <<< "$node_state"
    assert_tool_state "Node.js" "$node_path" "$node_version" "$effective_min_node_version"
    npm_state="$(get_tool_state npm -v || true)"
    IFS='|' read -r npm_path npm_version <<< "$npm_state"
  fi

  if [[ -z "$npm_path" ]]; then
    fail 'npm was still not found after the Node.js installation step.'
  fi

  if ! version_ge "$npm_version" "$MIN_NPM_VERSION"; then
    if (( SKIP_NPM )); then
      fail "npm version $npm_version is below the minimum requirement $MIN_NPM_VERSION and --skip-npm was specified."
    fi

    ensure_minimum_npm_installed
    if (( DRY_RUN )); then
      write_dry_run 'Verifying npm command path and version after upgrade'
      return
    fi
    refresh_homebrew_path
    npm_state="$(get_tool_state npm -v || true)"
    IFS='|' read -r npm_path npm_version <<< "$npm_state"
  fi

  assert_tool_state "npm" "$npm_path" "$npm_version" "$MIN_NPM_VERSION"
  write_info "Requested Codex package: $(get_codex_package_spec)"
  write_info "Codex latest version:   $codex_latest_version"
  write_info "Codex node range:       $codex_node_range"
}

confirm_codex_cli() {
  local codex_command
  local codex_version_output
  local codex_version

  codex_command="$(get_command_location codex)"
  if [[ -z "$codex_command" ]]; then
    fail 'Codex CLI installed, but codex was not found on PATH. Open a new terminal and run codex --version.'
  fi

  if ! codex_version_output="$("$codex_command" --version 2>&1 | tr -d '\r')"; then
    fail "codex was found at $codex_command but its version command failed."
  fi

  codex_version="$(parse_version_text "$codex_version_output")"
  if [[ -z "$codex_version" ]]; then
    fail "codex was found at $codex_command, but its version output could not be parsed."
  fi

  if ! is_latest_codex_version && [[ "$(normalize_version "$codex_version")" != "$(normalize_version "$CODEX_VERSION")" ]]; then
    fail "Codex CLI version $codex_version was installed, but version $CODEX_VERSION was requested."
  fi

  write_info "Resolved Codex path:    $codex_command"
  write_info "Resolved Codex version: $codex_version"
  write_step "Codex CLI is ready: $codex_version_output"
}

install_codex_cli() {
  local npm_command
  local package_spec

  npm_command="$(get_command_location npm)"
  package_spec="$(get_codex_package_spec)"

  if [[ -z "$npm_command" ]]; then
    if (( DRY_RUN )); then
      write_dry_run 'npm is not available yet because the Node.js installation step was only simulated.'
      write_dry_run "Installing $package_spec globally"
      write_dry_run 'Verifying codex on PATH after installation'
      return
    fi

    fail 'npm was not found after the Node.js installation step.'
  fi

  ensure_npm_cache
  run_checked "Installing $package_spec globally" \
    "$npm_command" --cache "$NPM_CACHE_DIR" install -g "$package_spec"

  if (( DRY_RUN )); then
    write_dry_run 'Verifying codex on PATH after installation'
    return
  fi

  hash -r
  confirm_codex_cli
}

validate_codex_version "$CODEX_VERSION"

write_step "Checking Git, Node.js, npm, and Codex CLI requirements"
write_warning 'This bootstrap may install or upgrade system Git, Node.js, and npm.'
write_warning 'If Homebrew is missing, this bootstrap will install Homebrew automatically.'
refresh_homebrew_path
ensure_git
ensure_node_toolchain
refresh_homebrew_path
install_codex_cli
