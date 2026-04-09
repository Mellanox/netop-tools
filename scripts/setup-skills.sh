#!/bin/bash
#
# Setup AI agent skills for netop-tools
#
# Creates symlinks from agent-specific directories to the canonical
# skills/ directory (SSOT). Supports Claude Code, Cursor, Continue,
# Cline, Windsurf, and the cross-agent .agents/ standard.
#
# Usage:
#   ./scripts/setup-skills.sh              # Project-level install (symlinks in repo)
#   ./scripts/setup-skills.sh --user       # User-level install (symlinks in ~/.agents/ and ~/.<agent>/)
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILLS_DIR="${REPO_ROOT}/skills"

if [ ! -d "${SKILLS_DIR}" ]; then
  echo "ERROR: Skills directory not found: ${SKILLS_DIR}"
  exit 1
fi

SKILLS=$(find "${SKILLS_DIR}" -maxdepth 1 -mindepth 1 -type d -exec basename {} \;)
SKILL_COUNT=$(echo "${SKILLS}" | wc -w)

echo "Found ${SKILL_COUNT} skills in ${SKILLS_DIR}"

# Determine install mode
if [ "${1:-}" = "--user" ]; then
  echo "Installing to user-level agent directories (~/.agents/, ~/.claude/, etc.)"
  BASE_DIR="${HOME}"
  # .agents is the cross-agent standard from skills.sh
  AGENT_DIRS=".agents .claude .cursor"
else
  echo "Installing to project-level agent directories"
  BASE_DIR="${REPO_ROOT}"
  # .agents is the cross-agent standard, others are agent-specific
  AGENT_DIRS=".agents .claude .cursor"
fi

for AGENT_DIR in ${AGENT_DIRS}; do
  TARGET="${BASE_DIR}/${AGENT_DIR}/skills"
  mkdir -p "${TARGET}"
  for SKILL in ${SKILLS}; do
    LINK="${TARGET}/${SKILL}"
    if [ -L "${LINK}" ]; then
      rm -f "${LINK}"
    fi
    if [ "${1:-}" = "--user" ]; then
      # User-level: use absolute paths
      ln -sfn "${SKILLS_DIR}/${SKILL}" "${LINK}"
    else
      # Project-level: use relative paths (portable across machines)
      REL_PATH="../../skills/${SKILL}"
      ln -sfn "${REL_PATH}" "${LINK}"
    fi
  done
  echo "  ${AGENT_DIR}/skills/ -> ${SKILL_COUNT} symlinks"
done

echo ""
echo "Skills installed for all agents."
echo ""
echo "Available skills:"
for SKILL in ${SKILLS}; do
  DESC=$(head -5 "${SKILLS_DIR}/${SKILL}/SKILL.md" | grep "^description:" | sed 's/^description: //')
  printf "  %-40s %s\n" "/${SKILL}" "${DESC:0:60}"
done
