#!/usr/bin/env bash
#
# path_checker.sh — show every entry in $PATH and where it was added from.
#
# PATH is just a string by the time a shell is ready, so the "who added me"
# information is gone. To recover it we re-run the user's login shell under
# xtrace, but starting from a minimal baseline PATH, with a PS4 that embeds
# the *live* value of PATH on every traced command. Diffing consecutive PATH
# snapshots tells us which startup file (and line) introduced each directory.
# That learned map is then applied to the real, current $PATH. Entries that
# no startup file explains are session/environment provided; for those we fall
# back to a static grep of the usual config files.
#
# Usage:
#   ./path_checker.sh                 # inspect the shell from $SHELL
#   ./path_checker.sh -d              # collapse + flag duplicate entries
#   ./path_checker.sh /bin/bash       # force a specific login shell to inspect
#   ./path_checker.sh -d /bin/bash    # combine options

set -u

# --- argument parsing --------------------------------------------------------
DEDUPE=0
TARGET_SHELL=""
for arg in "$@"; do
    case "$arg" in
        -d|--dedupe) DEDUPE=1 ;;
        -h|--help)
            # Print only the leading comment block (stop at first non-# line).
            awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"
            exit 0
            ;;
        -*)
            printf 'Unknown option: %s\n' "$arg" >&2
            exit 2
            ;;
        *) TARGET_SHELL="$arg" ;;
    esac
done

# --- colors ------------------------------------------------------------------
if [ -t 1 ]; then
    C_OK=$'\033[32m'      # green: directory exists
    C_BAD=$'\033[31m'     # red:   directory missing
    C_SRC=$'\033[90m'     # grey:  source annotation
    C_HDR=$'\033[1;36m'   # bold cyan: headers
    C_RST=$'\033[0m'
else
    C_OK=''; C_BAD=''; C_SRC=''; C_HDR=''; C_RST=''
fi

TARGET_SHELL="${TARGET_SHELL:-${SHELL:-/bin/bash}}"
SHELL_NAME="$(basename "$TARGET_SHELL")"
REPORT_PATH="$PATH"   # the PATH we actually want to explain

# Minimal baseline for the traced run: small enough that startup-file additions
# stand out, but real enough that rc scripts can still call basic tools.
BASELINE_PATH="/usr/bin:/bin"

# Config files worth grepping for entries no startup file explains.
CONFIG_FILES=(
    /etc/profile /etc/profile.d/* /etc/bash.bashrc /etc/bashrc
    /etc/environment /etc/security/pam_env.conf
    /etc/zsh/zshenv /etc/zsh/zprofile /etc/zsh/zshrc /etc/zsh/zlogin
    /etc/zshenv /etc/zprofile /etc/zshrc
    "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"
    "$HOME/.zshenv" "$HOME/.zprofile" "$HOME/.zshrc" "$HOME/.zlogin"
    "$HOME/.pam_environment"
)

# Marker keeps our trace lines distinguishable from arbitrary rc-file output.
MARKER='@@PCHK@@'
PS4_FMT_BASH="${MARKER}|\${BASH_SOURCE}|\${LINENO}|\${PATH}|"
PS4_FMT_ZSH="${MARKER}|%x|%I|\${PATH}|"

TRACE_FILE="$(mktemp)"
trap 'rm -f "$TRACE_FILE"' EXIT

# --- run the login shell under xtrace, from the baseline PATH ----------------
case "$SHELL_NAME" in
    zsh)
        # promptsubst is required so ${PATH} expands inside PS4; %x/%I give
        # the sourcing file and line number.
        PATH="$BASELINE_PATH" PS4="$PS4_FMT_ZSH" \
            "$TARGET_SHELL" -o promptsubst -x -l -i -c 'true' \
            </dev/null >/dev/null 2>"$TRACE_FILE"
        ;;
    *)
        PATH="$BASELINE_PATH" PS4="$PS4_FMT_BASH" \
            "$TARGET_SHELL" -x -l -i -c 'true' \
            </dev/null >/dev/null 2>"$TRACE_FILE"
        ;;
esac

# --- reduce trace to PATH "boundary" records ---------------------------------
# Each output record: <source>\t<line>\t<path-after-change>.
# The first record is the baseline PATH, tagged BASELINE.
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

# --- build map: PATH entry -> startup file that first introduced it ----------
declare -A ADDED_BY
declare -A SEEN

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

    IFS=':' read -r -a dirs <<< "$path"
    for d in "${dirs[@]}"; do
        [ -z "$d" ] && continue
        if [ -z "${SEEN[$d]+x}" ]; then
            SEEN["$d"]=1
            ADDED_BY["$d"]="$label"
        fi
    done
done

# --- helper: static grep fallback for a directory ----------------------------
static_source() {
    local dir="$1" hits
    hits="$(grep -lF -- "$dir" "${CONFIG_FILES[@]}" 2>/dev/null | paste -sd, -)"
    [ -n "$hits" ] && printf '%s' "$hits"
}

# --- resolve a directory to (source string, is-environment flag) -------------
# Sets the globals RESOLVED_SRC and RESOLVED_ENV (1 = environment/session).
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

# --- count occurrences for duplicate detection -------------------------------
declare -A COUNT
IFS=':' read -r -a report_dirs <<< "$REPORT_PATH"
for dir in "${report_dirs[@]}"; do
    [ -z "$dir" ] && continue
    COUNT["$dir"]=$(( ${COUNT["$dir"]:-0} + 1 ))
done

# --- report ------------------------------------------------------------------
echo ''
printf '%sPATH sources (login shell: %s)%s\n' "$C_HDR" "$TARGET_SHELL" "$C_RST"
printf '%sgreen%s = dir exists   %sred%s = dir missing   grey = where it came from\n' \
    "$C_OK" "$C_RST" "$C_BAD" "$C_RST"
if [ "$DEDUPE" -eq 1 ]; then
    printf 'duplicates collapsed (×N = number of times the entry appears)\n'
fi
echo ''

declare -A PRINTED
ENV_ENTRIES=()   # collected for the separate environment/session summary
position=0

for dir in "${report_dirs[@]}"; do
    [ -z "$dir" ] && continue
    position=$(( position + 1 ))

    resolve_source "$dir"
    [ "$RESOLVED_ENV" -eq 1 ] && ENV_ENTRIES+=("$dir"$'\t'"$RESOLVED_SRC")

    # In dedupe mode, print each unique directory only once.
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

# --- summary: environment/session entries reported separately ----------------
if [ "${#ENV_ENTRIES[@]}" -gt 0 ]; then
    echo ''
    printf '%sEnvironment / session entries (not added by any startup file)%s\n' \
        "$C_HDR" "$C_RST"
    printf '%sThese were set before shell startup — login manager, systemd,\n' "$C_SRC"
    printf 'PAM, the parent process, or the launcher itself.%s\n\n' "$C_RST"

    declare -A ENV_SEEN
    while IFS=$'\t' read -r dir src; do
        [ -n "${ENV_SEEN[$dir]+x}" ] && continue
        ENV_SEEN["$dir"]=1
        if [ -d "$dir" ]; then
            printf '%s%s%s  %s(%s)%s\n' "$C_OK" "$dir" "$C_RST" "$C_SRC" "$src" "$C_RST"
        else
            printf '%s%s%s  %s(%s)%s\n' "$C_BAD" "$dir" "$C_RST" "$C_SRC" "$src" "$C_RST"
        fi
    done < <(printf '%s\n' "${ENV_ENTRIES[@]}")
fi
echo ''
