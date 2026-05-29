#!/bin/bash
#
# install-hooks.sh — install netop-tools git hooks into .git/hooks/.
#
# Run from any working directory inside the repo. Idempotent: re-running
# overwrites prior symlinks.
#
set -e

REPO_ROOT="$(git rev-parse --show-toplevel)"
HOOKS_SRC="${REPO_ROOT}/tools/git-hooks"
HOOKS_DST="${REPO_ROOT}/.git/hooks"

if [ ! -d "${HOOKS_SRC}" ]; then
  echo "ERROR: hooks source directory not found: ${HOOKS_SRC}" >&2
  exit 1
fi

mkdir -p "${HOOKS_DST}"

for HOOK in "${HOOKS_SRC}"/*; do
  NAME="$(basename "${HOOK}")"
  ln -sf "../../tools/git-hooks/${NAME}" "${HOOKS_DST}/${NAME}"
  chmod +x "${HOOK}"
  echo "installed: .git/hooks/${NAME} -> tools/git-hooks/${NAME}"
done
