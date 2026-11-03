#!/usr/bin/env bash
# Intended exclusively for disposable GitHub-hosted Ubuntu runners.
set -euo pipefail
if [[ "${GITHUB_ACTIONS:-}" != true || "${RUNNER_ENVIRONMENT:-}" != github-hosted ]]; then
  echo 'Run this script only on a disposable GitHub-hosted runner.' >&2
  exit 1
fi
case "${CLEANUP_MODE:-}" in
  none|opt|toolcache|apt|original) ;;
  *) echo 'Unknown CLEANUP_MODE' >&2; exit 1 ;;
esac

# Capture paths before deleting anything, including paths through symlinks.
shopt -s nullglob
nodes=(/home/runner/actions-runner/cached/*/externals/node*/bin/node
       /home/runner/runners/*/externals/node*/bin/node
       /opt/runner/externals/node*/bin/node
       /opt/actions-runner/externals/node*/bin/node)
# Discover the actual Runner.Worker location without relying on image layout.
pid=$PPID
while [[ "$pid" -gt 1 ]]; do
  exe=$(readlink "/proc/$pid/exe" || true)
  if [[ "$exe" == */Runner.Worker ]]; then
    runner_root=$(dirname "$(dirname "$exe")")
    nodes+=("$runner_root"/externals/node*/bin/node)
    break
  fi
  pid=$(ps -o ppid= -p "$pid" | tr -d ' ')
  pid=${pid:-1}
done
if [[ ${#nodes[@]} -eq 0 ]]; then
  echo 'Could not discover runner Node binaries; aborting before cleanup.' >&2
  exit 1
fi

snapshot() {
  echo "::group::Node diagnostics: $1"
  printf 'Workspace: %s\nToolcache: %s\n' "$GITHUB_WORKSPACE" "$AGENT_TOOLSDIRECTORY"
  test -d "$GITHUB_WORKSPACE" && echo 'Workspace exists' || true
  for node in "${nodes[@]}"; do
    echo "Node: $node"
    namei -l "$node" || true
    readlink -f "$node" || true
    file -L "$node" || true
    ldd "$node" || true
    if "$node" --version; then
      echo 'Node execution: OK'
    else
      echo "Node execution: FAILED (exit $?)"
    fi
  done
  df -h / /mnt
  echo '::endgroup::'
}

operation() {
  local label=$1
  shift
  echo "::group::Cleanup: $label"
  local status=0
  "$@" || status=$?
  echo "Cleanup exit status: $status"
  echo '::endgroup::'
  snapshot "$label"
}

snapshot before
if [[ "$CLEANUP_MODE" == opt || "$CLEANUP_MODE" == original ]]; then
  operation /opt sudo rm -rf /opt/*
fi
if [[ "$CLEANUP_MODE" == original ]]; then
  operation dotnet sudo rm -rf /usr/share/dotnet
fi
if [[ "$CLEANUP_MODE" == toolcache || "$CLEANUP_MODE" == original ]]; then
  : "${AGENT_TOOLSDIRECTORY:?}"
  operation toolcache sudo rm -rf "$AGENT_TOOLSDIRECTORY"
fi
if [[ "$CLEANUP_MODE" == original ]]; then
  operation android sudo rm -rf /usr/local/lib/android
  operation boost sudo rm -rf /usr/local/share/boost
  operation jvm sudo rm -rf /usr/lib/jvm
  operation docker sudo docker image prune --all --force
fi
if [[ "$CLEANUP_MODE" == apt || "$CLEANUP_MODE" == original ]]; then
  # Keep output visible to identify removed packages and dependencies.
  operation apt-purge sudo apt-get purge -y \
    'azure-cli*' 'dotnet-sdk*' 'ghc*' 'google-chrome-stable*' \
    'firefox*' 'moby-*' 'mongodb*' nginx 'postgresql*' \
    'temurin-*' 'llvm-*' 'php*' powershell 'ruby*' subversion
  operation apt-autoremove sudo apt-get autoremove -y
  operation apt-autoclean sudo apt-get autoclean -y
fi
if [[ "$CLEANUP_MODE" == original ]]; then
  # Match the package installation between cleanup and restore in the source job.
  sudo apt-get update
  sudo apt-get -y install gawk wget git diffstat unzip texinfo gcc \
    build-essential chrpath socat cpio python3 python3-pip python3-pexpect xz-utils \
    debianutils iputils-ping python3-git python3-jinja2 \
    pylint xterm zstd liblz4-tool
  sudo apt-get clean
  snapshot after-install
fi
