#!/bin/zsh
set -euo pipefail

IDENTITY_NAME="NoMenu Local Code Signing"
MODE="${1:-}"

if [[ $# -gt 1 || ( -n "$MODE" && "$MODE" != "--print-sha1" ) ]]; then
    print -u2 'Usage: check-local-signing.sh [--print-sha1]'
    exit 2
fi

IDENTITIES="$(/usr/bin/security find-identity -v -p codesigning)"
MATCHES="$(
    print -r -- "$IDENTITIES" |
        /usr/bin/awk -v name="$IDENTITY_NAME" '$0 ~ "\\\"" name "\\\"[[:space:]]*$" { print $2 }'
)"
MATCH_COUNT="$(print -r -- "$MATCHES" | /usr/bin/awk 'NF { count++ } END { print count + 0 }')"

if [[ "$MATCH_COUNT" -eq 0 ]]; then
    print -u2 -- "No valid code-signing identity named '$IDENTITY_NAME' was found."
    print -u2 'Create your own identity in Keychain Access using Certificate Assistant:'
    print -u2 "  Name: $IDENTITY_NAME"
    print -u2 '  Identity Type: Self Signed Root'
    print -u2 '  Certificate Type: Code Signing'
    print -u2 'Store it in your login keychain, then run this check again.'
    exit 1
fi

if [[ "$MATCH_COUNT" -ne 1 ]]; then
    print -u2 -- "Found $MATCH_COUNT valid identities named '$IDENTITY_NAME'."
    print -u2 'Remove or rename duplicates in Keychain Access before building.'
    exit 1
fi

IDENTITY_SHA1="$(print -r -- "$MATCHES" | /usr/bin/awk 'NF { print; exit }')"
if ! print -r -- "$IDENTITY_SHA1" | /usr/bin/grep -Eq '^[[:xdigit:]]{40}$'; then
    print -u2 'The matching signing identity has an unexpected identifier format.'
    exit 1
fi

if [[ "$MODE" == "--print-sha1" ]]; then
    print -r -- "$IDENTITY_SHA1"
else
    print -r -- "Found one valid local code-signing identity named '$IDENTITY_NAME'."
fi
