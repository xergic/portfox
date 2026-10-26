#!/bin/sh
# Prints the body of a version's CHANGELOG section, which is both the GitHub
# release body and the Sparkle release notes. Fails when the section is missing,
# so a tag without notes stops before anything is signed.
set -eu

version="${1:?usage: release-notes.sh VERSION [CHANGELOG]}"
changelog="${2:-CHANGELOG.md}"

notes=$(awk -v heading="## [$version]" '
    index($0, heading) == 1 { found = 1; next }
    found && /^## \[/ { exit }
    found { print }
' "$changelog" | sed -e '/./,$!d')

if [ -z "$(printf '%s' "$notes" | tr -d '[:space:]')" ]; then
    echo "$changelog has no notes under \"## [$version]\". Add them before tagging." >&2
    exit 1
fi

printf '%s\n' "$notes"
