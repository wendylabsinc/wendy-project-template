#!/usr/bin/env bash
# Applies wendy-project-template files to a target repo.
# Usage: apply-template.sh <path-to-target-repo>
set -euo pipefail

TARGET="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MARKER="$TARGET/.github/wendy-template.yml"

if [[ ! -f "$MARKER" ]]; then
    echo "ERROR: $MARKER not found" >&2
    exit 1
fi

TYPE=$(yq '.type' "$MARKER")
DEFAULTS="$TEMPLATE_ROOT/defaults/${TYPE}.yml"

if [[ ! -f "$DEFAULTS" ]]; then
    echo "ERROR: Unknown project type: $TYPE" >&2
    exit 1
fi

# Build merged config: defaults overridden by project overrides
MERGED=$(yq eval-all \
    'select(fileIndex == 0) * select(fileIndex == 1)' \
    "$DEFAULTS" \
    <(yq '.overrides // {}' "$MARKER"))

echo "Syncing $TYPE templates → $TARGET"

mkdir -p "$TARGET/.github/workflows"

# ── Helpers ───────────────────────────────────────────────────────────────────

copy_type_templates() {
    local type_dir="$TEMPLATE_ROOT/templates/$1"
    for f in "$type_dir"/*.yml; do
        local fname
        fname=$(basename "$f")
        if [[ "$fname" == "dependabot.yml" ]]; then
            cp "$f" "$TARGET/.github/dependabot.yml"
        else
            cp "$f" "$TARGET/.github/workflows/$fname"
        fi
    done
}

# Copy docs-update (common to all types)
cp "$TEMPLATE_ROOT/templates/common/docs-update.yml" \
    "$TARGET/.github/workflows/docs-update.yml"

# ── Per-type logic ────────────────────────────────────────────────────────────

apply_swift() {
    copy_type_templates swift

    local platforms
    platforms=$(echo "$MERGED" | yq -o=json '.platforms')
    yq -i ".jobs.build-and-test.strategy.matrix.os = ${platforms}" \
        "$TARGET/.github/workflows/ci.yml"

    local versions
    versions=$(echo "$MERGED" | yq -o=json '.swift_versions')
    yq -i ".jobs.build-and-test.strategy.matrix.swift-version = ${versions}" \
        "$TARGET/.github/workflows/ci.yml"

    local nightly
    nightly=$(echo "$MERGED" | yq '.nightly')
    if [[ "$nightly" == "true" ]]; then
        yq -i '.on.schedule = [{"cron": "0 2 * * *"}]' \
            "$TARGET/.github/workflows/ci.yml"
    fi
}

apply_go() {
    local docker
    docker=$(echo "$MERGED" | yq '.docker')

    # Copy non-CI templates (skip ci.yml and ci-docker.yml — handled below)
    for f in "$TEMPLATE_ROOT/templates/go/"*.yml; do
        local fname
        fname=$(basename "$f")
        [[ "$fname" == ci*.yml ]] && continue
        if [[ "$fname" == "dependabot.yml" ]]; then
            cp "$f" "$TARGET/.github/dependabot.yml"
        else
            cp "$f" "$TARGET/.github/workflows/$fname"
        fi
    done

    # Select the right CI variant
    if [[ "$docker" == "true" ]]; then
        cp "$TEMPLATE_ROOT/templates/go/ci-docker.yml" \
            "$TARGET/.github/workflows/ci.yml"
    else
        cp "$TEMPLATE_ROOT/templates/go/ci.yml" \
            "$TARGET/.github/workflows/ci.yml"
    fi
}

apply_node() {
    copy_type_templates node

    local node_version
    node_version=$(echo "$MERGED" | yq '.node_version')
    yq -i "(.jobs.build.steps[] | select(.uses == \"actions/setup-node@v4\") | .with.node-version) = \"${node_version}\"" \
        "$TARGET/.github/workflows/ci.yml"
}

apply_python() {
    copy_type_templates python

    local python_version
    python_version=$(echo "$MERGED" | yq '.python_version')
    yq -i "(.jobs.ci.steps[] | select(.uses == \"actions/setup-python@v5\") | .with.python-version) = \"${python_version}\"" \
        "$TARGET/.github/workflows/ci.yml"
}

apply_rust() {
    copy_type_templates rust

    local channel
    channel=$(echo "$MERGED" | yq '.rust_channel')
    yq -i "(.jobs.ci.steps[] | select(.name == \"Setup Rust\") | .with.toolchain) = \"${channel}\"" \
        "$TARGET/.github/workflows/ci.yml"
}

apply_firmware() {
    copy_type_templates firmware

    local idf_version
    idf_version=$(echo "$MERGED" | yq '.idf_version')
    yq -i ".jobs.build.container.image = \"espressif/idf:${idf_version}\"" \
        "$TARGET/.github/workflows/ci.yml"

    local targets
    targets=$(echo "$MERGED" | yq -o=json '.targets')
    yq -i ".jobs.build.strategy.matrix.target = ${targets}" \
        "$TARGET/.github/workflows/ci.yml"

    local nightly
    nightly=$(echo "$MERGED" | yq '.nightly')
    if [[ "$nightly" != "true" ]]; then
        yq -i 'del(.jobs.nightly)' "$TARGET/.github/workflows/ci.yml"
    fi
}

case "$TYPE" in
    swift)    apply_swift    ;;
    go)       apply_go       ;;
    node)     apply_node     ;;
    python)   apply_python   ;;
    rust)     apply_rust     ;;
    firmware) apply_firmware ;;
esac

echo "Done."
