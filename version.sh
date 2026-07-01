#!/usr/bin/env bash
# Prints the full version X.Y.Z:
#   X.Y  — from the VERSION file (bumped manually for minor/major releases)
#   Z    — hex index of the current commit on main (commit count - 1)
# So the initial commit is 0.1.0 and Z iterates in hex per commit; a minor bump
# edits VERSION to X.(Y+1) and Z keeps tracking commits (never .0 again).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
base="$(tr -d '[:space:]' < "${here}/VERSION")"
count="$(git -C "${here}" rev-list --count HEAD)"
printf '%s.%x\n' "${base}" "$((count - 1))"
