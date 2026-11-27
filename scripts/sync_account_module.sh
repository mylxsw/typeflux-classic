#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# != 1 ]]; then
    echo "Usage: $0 <upstream-commit>|--check" >&2
    exit 2
fi
if [[ $1 == --check ]]; then
    [[ -s scripts/account_module_files.txt ]]
    grep -Eq '^# upstream [0-9a-f]{40}$' <(head -1 UPSTREAM_ACCOUNT_SYNC)
    diff -u scripts/account_module_files.txt <(tail -n +2 UPSTREAM_ACCOUNT_SYNC | cut -d ' ' -f 3-)
    tail -n +2 UPSTREAM_ACCOUNT_SYNC | shasum -a 256 --check
    exit
fi
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
repo=${TYPEFLUX_UPSTREAM_REPO:-}
if [[ -z $repo ]]; then
    repo=$tmp/upstream
    git clone --quiet --bare --filter=blob:none https://github.com/mylxsw/typeflux.git "$repo"
    if [[ $1 =~ ^[0-9a-fA-F]{40}$ ]] && ! git -C "$repo" cat-file -e "$1^{commit}" 2>/dev/null; then
        git -C "$repo" fetch --quiet origin "$1"
    fi
fi
commit=$(git -C "$repo" rev-parse --verify --end-of-options "$1^{commit}")
git -C "$repo" show "$commit:scripts/account_module_files.txt" > "$tmp/files"
printf '# upstream %s\n' "$commit" > "$tmp/lock"
mkdir "$tmp/tree"
while IFS= read -r path; do
    [[ $path =~ ^(Sources/Typeflux|Tests/TypefluxTests)/[a-zA-Z0-9_+./-]+\.swift$ && $path != *..* ]]
    mkdir -p "$tmp/tree/$(dirname "$path")"
    git -C "$repo" show "$commit:$path" > "$tmp/tree/$path"
    (cd "$tmp/tree" && shasum -a 256 "$path") >> "$tmp/lock"
done < "$tmp/files"
if [[ -f UPSTREAM_ACCOUNT_SYNC ]]; then
    while read -r hash path; do
        [[ $hash != '#' ]] || continue
        [[ $path =~ ^(Sources/Typeflux|Tests/TypefluxTests)/[a-zA-Z0-9_+./-]+\.swift$ && $path != *..* ]]
        if ! grep -Fxq "$path" "$tmp/files"; then rm -f -- "$path"; fi
    done < UPSTREAM_ACCOUNT_SYNC
fi
cp -R "$tmp/tree/." .
cp "$tmp/files" scripts/account_module_files.txt
mv "$tmp/lock" UPSTREAM_ACCOUNT_SYNC
