#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export PROJECT_ROOT
    mkdir "$BATS_TEST_TMPDIR/workflows"
    cp "$PROJECT_ROOT/.github/workflows/"*.yml "$BATS_TEST_TMPDIR/workflows/"
}

@test "fork CI policy accepts current workflows" {
    run ruby "$PROJECT_ROOT/tests/helpers/ci_policy.rb" "$BATS_TEST_TMPDIR/workflows"
    [ "$status" -eq 0 ] || {
        echo "$output"
        return 1
    }
}

@test "fork CI policy rejects write permissions and tag publication" {
    local fixture="$BATS_TEST_TMPDIR/workflows"
    sed 's/contents: read/contents: write/' "$PROJECT_ROOT/.github/workflows/check.yml" > "$fixture/check.yml"
    run ruby "$PROJECT_ROOT/tests/helpers/ci_policy.rb" "$fixture"
    [ "$status" -ne 0 ] || return 1
    [[ "$output" == *"token must be contents: read"* ]] || return 1
    sed 's/branches: \[main, dev\]/tags: ["V*"]/' "$PROJECT_ROOT/.github/workflows/check.yml" > "$fixture/check.yml"
    run ruby "$PROJECT_ROOT/tests/helpers/ci_policy.rb" "$fixture"
    [ "$status" -ne 0 ] || return 1
    [[ "$output" == *"branch-only"* ]]
}

@test "fork CI policy rejects renamed publishers and stored credentials" {
    local fixture="$BATS_TEST_TMPDIR/workflows"
    sed 's/persist-credentials: false/persist-credentials: true/' "$PROJECT_ROOT/.github/workflows/check.yml" > "$fixture/check.yml"
    run ruby "$PROJECT_ROOT/tests/helpers/ci_policy.rb" "$fixture"
    [ "$status" -ne 0 ] || return 1
    [[ "$output" == *"must not persist credentials"* ]] || return 1
    sed 's/actionlint$/gh release create V999/' "$PROJECT_ROOT/.github/workflows/check.yml" > "$fixture/check.yml"
    run ruby "$PROJECT_ROOT/tests/helpers/ci_policy.rb" "$fixture"
    [ "$status" -ne 0 ] || return 1
    [[ "$output" == *"publishing command is prohibited"* ]] || return 1
    cp "$PROJECT_ROOT/.github/workflows/check.yml" "$fixture/check.yml"
    cp "$fixture/check.yml" "$fixture/renamed-publisher.yml"
    run ruby "$PROJECT_ROOT/tests/helpers/ci_policy.rb" "$fixture"
    [ "$status" -ne 0 ] || return 1
    [[ "$output" == *"expected only check.yml and test.yml"* ]]
}
