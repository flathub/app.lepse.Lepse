#!/usr/bin/bash
set -e

# Check for updates to the manifest

OLD_TAG=$(git diff app.lepse.Lepse.yml | sed -n 's/^\- *tag: *//p' |  tr -d '"'"'")
NEW_TAG=$(git diff app.lepse.Lepse.yml | sed -n 's/^\+ *tag: *//p' |  tr -d '"'"'")

if [ -z "$NEW_TAG" ]; then
    echo "No updates to git source! skipping."
    exit 0
fi

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

cleanup() {
    cd "$ROOT_DIR"
    rm -rf tmp
}
trap cleanup EXIT

# tmp
cleanup # enter root dir and cleanup before star
mkdir tmp
cd tmp

# Function to pull a tag and then generate the pruned package
# $1 <tag> $2 <dir>
prune() (
    git -c advice.detachedHead=false clone https://github.com/aervxa/lepse --depth 1 --branch "$1" "$2"
    cd "$2"
    pnpm dlx turbo@$(node -p 'require("./package.json").devDependencies.turbo') prune @lepse/lachesis --out-dir tmp
)

prune "$OLD_TAG" old
prune "$NEW_TAG" new

PNPM_CHANGED=false
CARGO_CHANGED=false

if cmp -s old/tmp/pnpm-lock.yaml new/tmp/pnpm-lock.yaml; then
    echo "pnpm lockfile unchanged! skipping."
else
    echo "pnpm lockfile changed!"
    PNPM_CHANGED=true
fi

if cmp -s old/tmp/apps/lachesis/src-tauri/Cargo.lock new/tmp/apps/lachesis/src-tauri/Cargo.lock; then
    echo "Cargo lockfile unchanged! skipping."
else
    echo "Cargo lockfile changed!"
    CARGO_CHANGED=true
fi

if [ "$PNPM_CHANGED" = false ] && [ "$CARGO_CHANGED" = false ]; then
    echo "No lockfile changed! skipping build tools and source generation."
    exit 0
fi

# clone builder tools
git clone --depth 1 https://github.com/flatpak/flatpak-builder-tools fbt

# setup a temp python
python -m venv .venv
source .venv/bin/activate

# Generate node and cargo deps
if [ "$PNPM_CHANGED" = true ]; then
    pip install fbt/node # install python deps
    flatpak-node-generator --no-requests-cache -o "$ROOT_DIR/node-sources.json" pnpm new/pnpm-lock.yaml --pnpm-store-version v11
fi

if [ "$CARGO_CHANGED" = true ]; then
    pip install aiohttp tomlkit # install python deps
    python fbt/cargo/flatpak-cargo-generator.py -o "$ROOT_DIR/cargo-sources.json" new/apps/lachesis/src-tauri/Cargo.lock
fi
