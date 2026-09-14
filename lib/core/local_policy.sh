#!/bin/bash
# Local-only execution and mandatory cleanup exclusions for this fork.

[[ -z "${MOLE_LOCAL_POLICY_LOADED:-}" ]] || return 0
readonly MOLE_LOCAL_POLICY_LOADED=1

# These are process-local defaults, never edits to the user's tool settings.
export HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_INSTALL_FROM_API=1
export PIP_DISABLE_PIP_VERSION_CHECK=1 PIP_NO_INDEX=1
export UV_OFFLINE=1 GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off
export npm_config_offline=true npm_config_update_notifier=false

mole_path_is_cloud() {
    case "$1/" in
        */Library/CloudStorage/* | */Library/Mobile\ Documents/*) return 0 ;;
    esac
    return 1
}

# Refuse unsupported filesystems and ambiguous probes. Query only after the
# lexical cloud check; do not hydrate a placeholder to decide its eligibility.
mole_path_is_local() {
    local path="$1" device="" flags=""
    mole_path_is_cloud "$path" && return 1
    [[ "$path" == /* && ! "$path" =~ [[:cntrl:]] ]] || return 1
    flags=$(run_with_timeout "$MOLE_TIMEOUT_SHORT_QUERY_SEC" \
        /usr/bin/stat -f %Df "$path" 2> /dev/null) || return $?
    [[ "$flags" =~ ^[0-9]+$ ]] || return 1
    (((flags & 0x40000000) == 0)) || return 1 # SF_DATALESS: never hydrate placeholders.
    device=$(run_with_timeout "$MOLE_TIMEOUT_SHORT_QUERY_SEC" \
        df -Pk "$path" 2> /dev/null) || return $?
    device=$(LC_ALL=C awk 'NR == 2 {print $1}' <<< "$device")
    [[ "$device" == /dev/* ]]
}

# Applies to automatic maintenance, including fallback and direct safe sinks.
# Uninstall and analyze have deliberate selection and retain their own rules.
mole_local_cleanup_protected() {
    local path="${1%/}" root="${_MOLE_LOCAL_CACHE_ROOT:-}" physical="${_MOLE_LOCAL_CACHE_PHYSICAL:-}"
    case "${MOLE_CURRENT_COMMAND:-}" in
        clean | optimize)
            # Only a reviewed, validated cache family may enter the funnel.
            [[ (-n "$root" && ("$path" == "$root" || "$path" == "$root/"*)) ||
                (-n "$physical" && ("$path" == "$physical" || "$path" == "$physical/"*)) ]] || return 0
            ;;
        purge) ;;
        *) return 1 ;;
    esac
    mole_path_is_cloud "$path" && return 0
    case "$path/" in
        *.[aA][pP][pP]/* | */.git/* | */.Trash/* | */node_modules/* | */vendor/* | */Pods/* | \
            */venv/* | */.venv/* | */.tox/* | */.nox/* | */.build/* | \
            */.gradle/* | */.terragrunt-cache/* | */.dart_tool/* | \
            */Service\ Worker/* | */Partitions/* | */WebStorage/* | \
            */ms-playwright/* | */.rustup/* | */.cargo/* | \
            */.ollama/* | */.lmstudio/* | */huggingface/* | \
            */.cache/torch/* | */.cache/whisper/* | */.cache/puppeteer/*)
            return 0
            ;;
    esac
    local protected
    for protected in "${_MOLE_INVOKING_PROJECT:-}" "${VIRTUAL_ENV:-}" "${CONDA_PREFIX:-}"; do
        [[ "$protected" == /* && "$protected" != / ]] || continue
        [[ "$path" == "$protected" || "$path" == "$protected/"* || "$protected" == "$path/"* ]] && return 0
    done
    return 1
}

mole_capture_invoking_project() {
    _MOLE_INVOKING_PROJECT=""
    local directory
    directory=$(pwd -P) || return 1
    while [[ "$directory" != / ]]; do
        if [[ -e "$directory/.git" || -f "$directory/pyproject.toml" || -f "$directory/package.json" || -f "$directory/go.mod" ]]; then
            _MOLE_INVOKING_PROJECT="$directory"
            return 0
        fi
        directory="${directory%/*}"
        [[ -n "$directory" ]] || break
    done
    return 0
}

mole_local_update_notice() {
    printf '%s\n' 'This local fork does not download or replace itself.' \
        'Review and build updates from this fork; no verified distribution channel is configured.'
}

# 0 = command target or unknown; 1 = a complete PATH inspection found no
# command inside this target. A missing resolver fails closed.
mole_preserves_command_target() {
    local path="$1" rc=0
    [[ -x /usr/bin/perl ]] || return 0
    /usr/bin/perl -MCwd=abs_path -e '
        $SIG{ALRM}=sub{exit 124}; alarm 3;
        my $target=abs_path($ARGV[0]); defined($target) or exit 2;
        for my $dir (split /:/, $ENV{PATH}//"", -1) {
            $dir="." if $dir eq "";
            $dir =~ m{^/(Volumes|Network|net)/|/Library/(CloudStorage|Mobile Documents)/} and exit 2;
            next unless -e $dir;
            opendir(my $dh,$dir) or exit 2;
            while (defined(my $name=readdir($dh))) {
                next if $name eq "." || $name eq "..";
                my $entry="$dir/$name";
                if (-l $entry) { my $link=readlink($entry); defined($link) or exit 2; $link =~ m{^/Volumes/} and exit 2; }
                next unless -x $entry && !-d $entry;
                my $command=abs_path($entry); defined($command) or exit 2;
                exit 0 if $command eq $target || index($command,"$target/")==0;
            }
            closedir($dh);
        }
        exit 1;
    ' "$path" || rc=$?
    [[ $rc -ne 124 && $rc -lt 128 ]] || return "$rc"
    [[ $rc -ne 1 ]]
}
