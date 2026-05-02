#!/usr/bin/env bats

setup() {
    TARGET=$(mktemp -d)
    mkdir -p "$TARGET/.github"
    SCRIPT="$BATS_TEST_DIRNAME/../scripts/apply-template.sh"
}

teardown() {
    rm -rf "$TARGET"
}

# ── Error cases ────────────────────────────────────────────────────────────────

@test "fails when marker file is missing" {
    run bash "$SCRIPT" "$TARGET"
    [ "$status" -ne 0 ]
    [[ "$output" == *"wendy-template.yml not found"* ]]
}

@test "fails for unknown project type" {
    echo "type: cobol" > "$TARGET/.github/wendy-template.yml"
    run bash "$SCRIPT" "$TARGET"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown project type"* ]]
}

# ── Swift ──────────────────────────────────────────────────────────────────────

@test "swift: copies ci.yml to .github/workflows/" {
    printf 'type: swift\n' > "$TARGET/.github/wendy-template.yml"
    run bash "$SCRIPT" "$TARGET"
    [ "$status" -eq 0 ]
    [ -f "$TARGET/.github/workflows/ci.yml" ]
}

@test "swift: copies dependabot.yml to .github/ (not workflows/)" {
    printf 'type: swift\n' > "$TARGET/.github/wendy-template.yml"
    bash "$SCRIPT" "$TARGET"
    [ -f "$TARGET/.github/dependabot.yml" ]
    [ ! -f "$TARGET/.github/workflows/dependabot.yml" ]
}

@test "swift: copies docs-update.yml" {
    printf 'type: swift\n' > "$TARGET/.github/wendy-template.yml"
    bash "$SCRIPT" "$TARGET"
    [ -f "$TARGET/.github/workflows/docs-update.yml" ]
}

@test "swift: copies security-scan.yml" {
    printf 'type: swift\n' > "$TARGET/.github/wendy-template.yml"
    bash "$SCRIPT" "$TARGET"
    [ -f "$TARGET/.github/workflows/security-scan.yml" ]
}

@test "swift: patches swift_versions override" {
    cat > "$TARGET/.github/wendy-template.yml" << 'EOF'
type: swift
overrides:
  swift_versions:
    - "6.3"
EOF
    bash "$SCRIPT" "$TARGET"
    result=$(yq '.jobs.build-and-test.strategy.matrix.swift-version[0]' \
        "$TARGET/.github/workflows/ci.yml")
    [ "$result" = "6.3" ]
}

@test "swift: patches platforms override" {
    cat > "$TARGET/.github/wendy-template.yml" << 'EOF'
type: swift
overrides:
  platforms:
    - ubuntu-latest
EOF
    bash "$SCRIPT" "$TARGET"
    count=$(yq '.jobs.build-and-test.strategy.matrix.os | length' \
        "$TARGET/.github/workflows/ci.yml")
    [ "$count" = "1" ]
    first=$(yq '.jobs.build-and-test.strategy.matrix.os[0]' \
        "$TARGET/.github/workflows/ci.yml")
    [ "$first" = "ubuntu-latest" ]
}

@test "swift: idempotent — running twice produces same result" {
    printf 'type: swift\n' > "$TARGET/.github/wendy-template.yml"
    bash "$SCRIPT" "$TARGET"
    CHECKSUM_1=$(md5 -q "$TARGET/.github/workflows/ci.yml" 2>/dev/null || md5sum "$TARGET/.github/workflows/ci.yml" | cut -d' ' -f1)
    bash "$SCRIPT" "$TARGET"
    CHECKSUM_2=$(md5 -q "$TARGET/.github/workflows/ci.yml" 2>/dev/null || md5sum "$TARGET/.github/workflows/ci.yml" | cut -d' ' -f1)
    [ "$CHECKSUM_1" = "$CHECKSUM_2" ]
}

# ── Go ─────────────────────────────────────────────────────────────────────────

@test "go: copies ci.yml (non-docker by default)" {
    printf 'type: go\n' > "$TARGET/.github/wendy-template.yml"
    bash "$SCRIPT" "$TARGET"
    [ -f "$TARGET/.github/workflows/ci.yml" ]
    run grep -q "docker" "$TARGET/.github/workflows/ci.yml"
    [ "$status" -ne 0 ]
}

@test "go: uses ci-docker.yml when docker: true" {
    cat > "$TARGET/.github/wendy-template.yml" << 'EOF'
type: go
overrides:
  docker: true
EOF
    bash "$SCRIPT" "$TARGET"
    run grep -q "docker/build-push-action" "$TARGET/.github/workflows/ci.yml"
    [ "$status" -eq 0 ]
}

# ── Node ───────────────────────────────────────────────────────────────────────

@test "node: copies ci.yml" {
    printf 'type: node\n' > "$TARGET/.github/wendy-template.yml"
    bash "$SCRIPT" "$TARGET"
    [ -f "$TARGET/.github/workflows/ci.yml" ]
}

@test "node: patches node_version override" {
    cat > "$TARGET/.github/wendy-template.yml" << 'EOF'
type: node
overrides:
  node_version: "22"
EOF
    bash "$SCRIPT" "$TARGET"
    result=$(yq '.jobs.build.steps[] | select(.uses == "actions/setup-node@v4") | .with.node-version' \
        "$TARGET/.github/workflows/ci.yml")
    [ "$result" = "22" ]
}

# ── Firmware ───────────────────────────────────────────────────────────────────

@test "firmware: patches targets override" {
    cat > "$TARGET/.github/wendy-template.yml" << 'EOF'
type: firmware
overrides:
  targets:
    - esp32s3
EOF
    bash "$SCRIPT" "$TARGET"
    count=$(yq '.jobs.build.strategy.matrix.target | length' \
        "$TARGET/.github/workflows/ci.yml")
    [ "$count" = "1" ]
    first=$(yq '.jobs.build.strategy.matrix.target[0]' \
        "$TARGET/.github/workflows/ci.yml")
    [ "$first" = "esp32s3" ]
}

@test "firmware: patches idf_version override" {
    cat > "$TARGET/.github/wendy-template.yml" << 'EOF'
type: firmware
overrides:
  idf_version: "v5.4.0"
EOF
    bash "$SCRIPT" "$TARGET"
    result=$(yq '.jobs.build.container.image' "$TARGET/.github/workflows/ci.yml")
    [ "$result" = "espressif/idf:v5.4.0" ]
}
