#!/usr/bin/env bash
set -euo pipefail

load_bootstrap_env() {
  local env_file="${1:-}"
  if [ -z "$env_file" ]; then
    echo "Usage: <script> <bootstrap.env>" >&2
    exit 2
  fi
  if [ ! -f "$env_file" ]; then
    echo "bootstrap env file not found: $env_file" >&2
    exit 2
  fi

  # shellcheck disable=SC1090
  source "$env_file"

  : "${HERMES_BIN:?missing HERMES_BIN}"
  : "${HERMES_ROOT:?missing HERMES_ROOT}"
  : "${PROFILE_NAME:?missing PROFILE_NAME}"
  : "${PROFILE_HOME:?missing PROFILE_HOME}"
  : "${REPOS_DIR:?missing REPOS_DIR}"
}

ensure_repo() {
  local repo_url="$1"
  local target_dir="$2"

  mkdir -p "$(dirname "$target_dir")"
  if [ -d "$target_dir/.git" ]; then
    git -C "$target_dir" pull --ff-only
  else
    git clone "$repo_url" "$target_dir"
  fi
}

note() {
  printf '[bootstrap] %s\n' "$*"
}

