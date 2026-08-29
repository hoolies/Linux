#!/usr/bin/env bash
# path_checker — show each PATH entry and which startup file added it.
# Manual page: path_checker.1

set -euo pipefail
export LC_ALL=C
unalias -a 2>/dev/null || true
unset -f timeout rm mv cp grep awk stat readlink basename dirname cat paste getent mktemp 2>/dev/null || true

readonly PROGNAME="${0##*/}"
readonly TRACE_TIMEOUT=20

usage() {
    cat <<EOF
Usage: $PROGNAME [OPTION]... [SHELL]
Show each PATH entry and which startup file added it.

Mandatory arguments to long options are mandatory for short options too.

  -d, --dedupe          collapse duplicate PATH entries
  -h, --help            display this help and exit

If SHELL is omitted, the account's default login shell is taken from
the passwd database.  \$SHELL is only a fallback.

PATH is a string by the time a shell is ready, so the script re-runs
the login shell under xtrace from a minimal baseline PATH and diffs
consecutive snapshots to attribute each directory to a file and line.
Entries no startup file explains are treated as environment/session
provided; those fall back to a static grep of the usual config files.
EOF
}

unrecognized_option() {
    printf '%s: unrecognized option %s\n' "$PROGNAME" "$1" >&2
    printf "Try '%s --help' for more information.\n" "$PROGNAME" >&2
}

parse_args() {
    DEDUPE=0
    TARGET_SHELL=""
    local arg
    for arg in "$@"; do
        case "$arg" in
            -d | --dedupe) DEDUPE=1 ;;
            -h | --help)
                usage
                exit 0
                ;;
            -*)
                unrecognized_option "$arg"
                exit 2
                ;;
            *) TARGET_SHELL="$arg" ;;
        esac
    done
}

init_colors() {
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
        C_OK=$'\033[32m'
        C_BAD=$'\033[31m'
        C_SRC=$'\033[1;33m'
        C_HDR=$'\033[1;36m'
        C_RST=$'\033[0m'
    else
        C_OK=''
        C_BAD=''
        C_SRC=''
        C_HDR=''
        C_RST=''
    fi
}

detect_login_user() {
    local owner
    if [ -n "${HOME:-}" ] && [ -d "$HOME" ]; then
        owner="$(stat -c '%U' -- "$HOME" 2>/dev/null || true)"
        if [ -n "$owner" ]; then
            printf '%s' "$owner"
            return 0
        fi
    fi
    id -un 2>/dev/null || printf '%s' "${USER:-${LOGNAME:-}}"
}

detect_default_shell() {
    local user="$1" entry=""
    if command -v getent >/dev/null 2>&1; then
        entry="$(getent passwd "$user" 2>/dev/null || true)"
    fi
    if [ -z "$entry" ]; then
        entry="$(awk -F: -v u="$user" '$1 == u { print $0; exit }' /etc/passwd 2>/dev/null || true)"
    fi
    entry="${entry%%$'\n'*}"
    if [ -n "$entry" ]; then
        printf '%s' "${entry##*:}"
        return 0
    fi
    printf '%s' "${SHELL:-/bin/sh}"
}

shell_family() {
    local path="$1" name resolved
    name="$(basename -- "$path")"
    resolved="$(basename -- "$(readlink -f -- "$path" 2>/dev/null || printf '%s' "$path")")"
    case "$name" in
        zsh)
            printf 'zsh'
            return
            ;;
        bash)
            printf 'bash'
            return
            ;;
        sh | dash | ash | busybox | ksh | mksh | pdksh)
            printf 'posix'
            return
            ;;
    esac
    case "$resolved" in
        zsh) printf 'zsh' ;;
        bash) printf 'bash' ;;
        dash | ash | busybox | ksh | mksh | pdksh | sh)
            printf 'posix'
            ;;
        *) printf '%s' "$name" ;;
    esac
}

resolve_target_shell() {
    LOGIN_USER="$(detect_login_user)"
    DEFAULT_SHELL="$(detect_default_shell "$LOGIN_USER")"
    DEFAULT_FAMILY="$(shell_family "$DEFAULT_SHELL")"
    FORCED_SHELL=0
    if [ -n "$TARGET_SHELL" ]; then
        FORCED_SHELL=1
    else
        TARGET_SHELL="$DEFAULT_SHELL"
    fi
    SHELL_FAMILY="$(shell_family "$TARGET_SHELL")"
    SH_TARGET="$(readlink -f -- /bin/sh 2>/dev/null || printf '%s' /bin/sh)"
}

init_config_files() {
    CONFIG_FILES=(
        /etc/profile /etc/profile.d/* /etc/bash.bashrc /etc/bashrc
        /etc/environment /etc/security/pam_env.conf
        /etc/zsh/zshenv /etc/zsh/zprofile /etc/zsh/zshrc /etc/zsh/zlogin
        /etc/zshenv /etc/zprofile /etc/zshrc
        "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"
        "$HOME/.zshenv" "$HOME/.zprofile" "$HOME/.zshrc" "$HOME/.zlogin"
        "$HOME/.pam_environment"
    )
}

run_with_timeout() {
    if command -v timeout >/dev/null 2>&1; then
        timeout "$TRACE_TIMEOUT" "$@"
    else
        printf '%s: timeout(1) not found; running unbounded\n' "$PROGNAME" >&2
        "$@"
    fi
}

run_traced_login() {
    if ! case "$SHELL_FAMILY" in
        zsh)
            PATH="$BASELINE_PATH" PS4="$PS4_FMT_ZSH" \
                run_with_timeout "$TARGET_SHELL" -o promptsubst -x -l -i -c 'true' \
                </dev/null >/dev/null 2>"$TRACE_FILE"
            ;;
        posix)
            PATH="$BASELINE_PATH" \
                run_with_timeout "$TARGET_SHELL" -x -l -c 'true' \
                </dev/null >/dev/null 2>"$TRACE_FILE"
            ;;
        *)
            PATH="$BASELINE_PATH" PS4="$PS4_FMT_BASH" \
                run_with_timeout "$TARGET_SHELL" -x -l -i -c 'true' \
                </dev/null >/dev/null 2>"$TRACE_FILE"
            ;;
    esac then
        printf '%s: timed out or failed tracing %s\n' "$PROGNAME" "$TARGET_SHELL" >&2
        exit 1
    fi
}

parse_trace_boundaries() {
    mapfile -t BOUNDARIES < <(
        awk -v marker="$MARKER" '
        {
            idx = index($0, marker "|")
            if (idx == 0) next
            n = split(substr($0, idx), f, "|")
            src = f[2]; ln = f[3]; path = f[4]
            if (path == "") next
            if (!started) {
                print "BASELINE\t-\t" path
                started = 1
            } else if (path != prevPath) {
                print prevSrc "\t" prevLn "\t" path
            }
            prevSrc = src; prevLn = ln; prevPath = path
        }
        ' "$TRACE_FILE"
    )
}

record_new_dirs() {
    local path="$1" label="$2" d
    local -a dirs
    IFS=':' read -r -a dirs <<<"$path"
    for d in "${dirs[@]}"; do
        [ -z "$d" ] && continue
        if [ -z "${SEEN[$d]+x}" ]; then
            SEEN["$d"]=1
            ADDED_BY["$d"]="$label"
        fi
    done
}

build_added_by_map() {
    declare -gA ADDED_BY
    declare -gA SEEN
    local rec src rest ln path label
    for rec in "${BOUNDARIES[@]}"; do
        src="${rec%%$'\t'*}"
        rest="${rec#*$'\t'}"
        ln="${rest%%$'\t'*}"
        path="${rest#*$'\t'}"
        if [ "$src" = "BASELINE" ]; then
            label="__BASELINE__"
        elif [ -n "$src" ]; then
            label="$src:$ln"
        else
            label="(command line / interactive)"
        fi
        record_new_dirs "$path" "$label"
    done
}

static_source() {
    local dir="$1" hits
    hits="$(grep -lF -- "$dir" "${CONFIG_FILES[@]}" 2>/dev/null | paste -sd, - || true)"
    printf '%s' "$hits"
    return 0
}

resolve_source() {
    local dir="$1" label guess
    label="${ADDED_BY[$dir]:-}"
    if [ -n "$label" ] && [ "$label" != "__BASELINE__" ]; then
        RESOLVED_SRC="$label"
        RESOLVED_ENV=0
    else
        guess="$(static_source "$dir")"
        if [ -n "$guess" ]; then
            RESOLVED_SRC="referenced in $guess"
        else
            RESOLVED_SRC="no startup file references it"
        fi
        RESOLVED_ENV=1
    fi
}

count_report_dirs() {
    declare -gA COUNT
    local dir
    IFS=':' read -r -a report_dirs <<<"$REPORT_PATH"
    for dir in "${report_dirs[@]}"; do
        [ -z "$dir" ] && continue
        COUNT["$dir"]=$((${COUNT["$dir"]:-0} + 1))
    done
}

print_shell_detection() {
    printf '\n'
    printf '%sShell detection%s\n' "$C_HDR" "$C_RST"
    printf '  account              %s\n' "$LOGIN_USER"
    printf '  default login shell  %s  (%s)\n' "$DEFAULT_SHELL" "$DEFAULT_FAMILY"
    printf '  %s               %s\n' "\$SHELL" "${SHELL:-unset}"
    printf '  /bin/sh              %s\n' "$SH_TARGET"
    if [ "$FORCED_SHELL" -eq 1 ]; then
        printf '  inspecting           %s  (%s, forced)\n' "$TARGET_SHELL" "$SHELL_FAMILY"
    else
        printf '  inspecting           %s  (%s)\n' "$TARGET_SHELL" "$SHELL_FAMILY"
    fi
    if [ "$DEFAULT_FAMILY" != "$SHELL_FAMILY" ]; then
        printf '  %snote: default is %s; PATH attributions follow %s startup files%s\n' \
            "$C_BAD" "$DEFAULT_FAMILY" "$SHELL_FAMILY" "$C_RST"
    fi
}

print_legend() {
    printf '\n'
    printf '%sPATH sources%s\n' "$C_HDR" "$C_RST"
    printf '%sgreen%s = dir exists   %sred%s = dir missing   %syellow%s = where it came from\n' \
        "$C_OK" "$C_RST" "$C_BAD" "$C_RST" "$C_SRC" "$C_RST"
    if [ "$DEDUPE" -eq 1 ]; then
        printf 'duplicates collapsed (×N = number of times the entry appears)\n'
    fi
    printf '\n'
}

print_path_entries() {
    declare -gA PRINTED
    ENV_ENTRIES=()
    local dir position count
    position=0
    for dir in "${report_dirs[@]}"; do
        [ -z "$dir" ] && continue
        position=$((position + 1))
        resolve_source "$dir"
        [ "$RESOLVED_ENV" -eq 1 ] && ENV_ENTRIES+=("$dir"$'\t'"$RESOLVED_SRC")
        if [ "$DEDUPE" -eq 1 ] && [ -n "${PRINTED[$dir]+x}" ]; then
            continue
        fi
        PRINTED["$dir"]=1
        if [ -d "$dir" ]; then
            printf '%2d. %s%s%s' "$position" "$C_OK" "$dir" "$C_RST"
        else
            printf '%2d. %s%s%s' "$position" "$C_BAD" "$dir" "$C_RST"
        fi
        count="${COUNT[$dir]}"
        if [ "$count" -gt 1 ]; then
            printf ' %s(×%d)%s' "$C_BAD" "$count" "$C_RST"
        fi
        printf '\n      %s<- %s%s\n' "$C_SRC" "$RESOLVED_SRC" "$C_RST"
    done
}

print_env_entries() {
    [ "${#ENV_ENTRIES[@]}" -gt 0 ] || return 0
    printf '\n'
    printf '%sEnvironment / session entries (not added by any startup file)%s\n' \
        "$C_HDR" "$C_RST"
    printf '%sThese were set before shell startup — login manager, systemd,\n' "$C_SRC"
    printf 'PAM, the parent process, or the launcher itself.%s\n\n' "$C_RST"
    declare -A ENV_SEEN
    local dir src
    while IFS=$'\t' read -r dir src; do
        [ -n "${ENV_SEEN[$dir]+x}" ] && continue
        ENV_SEEN["$dir"]=1
        if [ -d "$dir" ]; then
            printf '%s%s%s  %s(%s)%s\n' "$C_OK" "$dir" "$C_RST" "$C_SRC" "$src" "$C_RST"
        else
            printf '%s%s%s  %s(%s)%s\n' "$C_BAD" "$dir" "$C_RST" "$C_SRC" "$src" "$C_RST"
        fi
    done < <(printf '%s\n' "${ENV_ENTRIES[@]}")
}

main() {
    parse_args "$@"
    init_colors
    resolve_target_shell
    REPORT_PATH="$PATH"
    readonly BASELINE_PATH="/usr/bin:/bin"
    readonly MARKER='@@PCHK@@'
    PS4_FMT_BASH="${MARKER}|\${BASH_SOURCE}|\${LINENO}|\${PATH}|"
    PS4_FMT_ZSH="${MARKER}|%x|%I|\${PATH}|"
    init_config_files
    TRACE_FILE="$(mktemp)"
    trap 'rm -f -- "$TRACE_FILE"' EXIT
    run_traced_login
    parse_trace_boundaries
    build_added_by_map
    count_report_dirs
    print_shell_detection
    print_legend
    print_path_entries
    print_env_entries
    printf '\n'
}

main "$@"
