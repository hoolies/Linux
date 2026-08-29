#!/usr/bin/env bash
# path_cleaner — drop missing and duplicate directories from PATH.
# Dual bash/zsh: source this file to change the current session.
# Enable errexit/nounset/pipefail for this run; restore the caller when sourced.
_pc_had_errexit=0
_pc_had_nounset=0
_pc_had_pipefail=0
if [ -n "${ZSH_VERSION:-}" ]; then
    [[ -o errexit ]] && _pc_had_errexit=1
    [[ -o nounset ]] && _pc_had_nounset=1
    [[ -o pipefail ]] && _pc_had_pipefail=1
    setopt errexit nounset pipefail
else
    [[ -o errexit ]] && _pc_had_errexit=1
    [[ -o nounset ]] && _pc_had_nounset=1
    [[ -o pipefail ]] && _pc_had_pipefail=1
    set -euo pipefail
fi

# C locale for grep/sort; restore the caller when sourced.
_pc_had_lc_all=0
_pc_old_lc_all=""
if [ -n "${LC_ALL+x}" ]; then
    _pc_had_lc_all=1
    _pc_old_lc_all="$LC_ALL"
fi
export LC_ALL=C

_pc_temp_files=()
_pc_tmp=""
_pc_mktemp() {
    _pc_tmp="$(mktemp)"
    _pc_temp_files+=("$_pc_tmp")
}

_pc_rm_temps() {
    local f
    for f in ${_pc_temp_files[@]+"${_pc_temp_files[@]}"}; do
        rm -f -- "$f"
    done
    _pc_temp_files=()
}

_pc_rehash() {
    if [ -n "${ZSH_VERSION:-}" ]; then
        rehash
    else
        hash -r
    fi
}

_pc_run_with_timeout() {
    if command -v timeout >/dev/null 2>&1; then
        timeout "$TRACE_TIMEOUT" "$@"
    else
        printf '%s: timeout(1) not found; running unbounded\n' "$PROGNAME" >&2
        "$@"
    fi
}

# Split a colon-separated string into pc_parts. Avoids bash-only `read -a`
# so this file can be sourced from zsh.
pc_parts=()
_pc_split_path() {
    pc_parts=()
    local src="$1" piece
    while :; do
        case "$src" in
            *:*)
                piece="${src%%:*}"
                pc_parts+=("$piece")
                src="${src#*:}"
                ;;
            *)
                pc_parts+=("$src")
                break
                ;;
        esac
    done
}

# --- detect whether we are being sourced -------------------------------------
SOURCED=0
if [ -n "${ZSH_VERSION:-}" ]; then
    case "${ZSH_EVAL_CONTEXT:-}" in *:file*) SOURCED=1 ;; *) ;; esac
elif [ -n "${BASH_VERSION:-}" ]; then
    [ "${BASH_SOURCE[0]}" != "$0" ] && SOURCED=1
fi

_pc_saved_trap="$(trap -p EXIT 2>/dev/null || true)"
trap '_pc_rm_temps' EXIT

TRACE_TIMEOUT=20
if [ "$SOURCED" -eq 0 ]; then
    unalias -a 2>/dev/null || true
    unset -f timeout rm mv cp grep awk stat readlink basename dirname cat paste getent mktemp 2>/dev/null || true
    readonly TRACE_TIMEOUT
fi

# Absolute path to this script (used by --install). In bash when sourced, $0 is
# the shell, so use BASH_SOURCE; in zsh (and when executed) $0 is the script.
if [ -n "${BASH_SOURCE:-}" ]; then
    _self="${BASH_SOURCE[0]}"
else
    _self="$0"
fi
SCRIPT_PATH="$(cd -- "$(dirname -- "$_self")" 2>/dev/null && pwd)/$(basename -- "$_self")"
PROGNAME="$(basename -- "$SCRIPT_PATH")"
if [ "$SOURCED" -eq 0 ]; then
    readonly PROGNAME
fi

_pc_usage() {
    cat <<EOF
Usage: $PROGNAME [OPTION]... [RC]
Drop missing and duplicate directories from PATH.

Mandatory arguments to long options are mandatory for short options too.

  -s, --session         clean the current session (must be sourced)
  -p, --purge           comment out startup-file lines that add missing dirs
      --permanent       same as --purge
  -i, --interactive     choose skip, session-remove, or permanent delete
      --menu            same as --interactive
      --install         add a path_cleaner function to an rc file
  -r, --report          show what would be cleaned, change nothing
  -q, --quiet           print only the cleaned PATH string
  -e, --export          print an export PATH=... line
  -y, --yes             do not prompt before --purge
  -h, --help            display this help and exit

RC is an optional rc file for --install or --purge.  Default: the
login shell's usual rc file.

To change the current shell, source this file.  Running it as a
program cannot update the caller's PATH.
EOF
}

_pc_unrecognized_option() {
    printf '%s: unrecognized option %s\n' "$PROGNAME" "$1" >&2
    printf "Try '%s --help' for more information.\n" "$PROGNAME" >&2
}

# --- argument parsing --------------------------------------------------------
MODE="session"
RC_OVERRIDE=""
ASSUME_YES=0
for arg in "$@"; do
    case "$arg" in
        -s | --session) MODE="session" ;;
        -p | --purge | --permanent) MODE="purge" ;;
        -i | --menu | --interactive) MODE="interactive" ;;
        --install) MODE="install" ;;
        -r | --report) MODE="report" ;;
        -q | --quiet) MODE="quiet" ;;
        -e | --export) MODE="export" ;;
        -y | --yes) ASSUME_YES=1 ;;
        -h | --help) MODE="help" ;;
        -*)
            _pc_unrecognized_option "$arg"
            MODE="error"
            break
            ;;
        *) RC_OVERRIDE="$arg" ;;
    esac
done

# --- colors ------------------------------------------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "$MODE" != "quiet" ] && [ "$MODE" != "export" ]; then
    C_OK=$'\033[32m'
    C_BAD=$'\033[31m'
    C_DUP=$'\033[33m'
    C_HDR=$'\033[1;36m'
    C_SRC=$'\033[90m'
    C_RST=$'\033[0m'
else
    C_OK=''
    C_BAD=''
    C_DUP=''
    C_HDR=''
    C_SRC=''
    C_RST=''
fi

# --- compute the auto-cleaned PATH (missing dirs + duplicates) ---------------
declare -A SEEN
KEPT=()
REMOVED_MISSING=()
REMOVED_DUP=()
_pc_split_path "$PATH"
for dir in ${pc_parts[@]+"${pc_parts[@]}"}; do
    [ -z "$dir" ] && continue
    if [ ! -d "$dir" ]; then
        REMOVED_MISSING+=("$dir")
        continue
    fi
    if [ -n "${SEEN["$dir"]+x}" ]; then
        REMOVED_DUP+=("$dir")
        continue
    fi
    SEEN["$dir"]=1
    KEPT+=("$dir")
done
CLEAN_PATH=""
for dir in ${KEPT[@]+"${KEPT[@]}"}; do CLEAN_PATH="${CLEAN_PATH:+$CLEAN_PATH:}$dir"; done

# --- config files for static fallback ----------------------------------------
CONFIG_FILES=(
    /etc/profile /etc/bash.bashrc /etc/bashrc /etc/environment
    /etc/zsh/zshenv /etc/zsh/zprofile /etc/zsh/zshrc /etc/zsh/zlogin
    /etc/zshenv /etc/zprofile /etc/zshrc
    "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"
    "$HOME/.zshenv" "$HOME/.zprofile" "$HOME/.zshrc" "$HOME/.zlogin"
)
# Append /etc/profile.d/* if present. zsh errors on unmatched globs unless
# NULL_GLOB is on; LOCAL_OPTIONS keeps that from leaking when sourced.
_pc_append_profiled() {
    [ -d /etc/profile.d ] || return 0
    if [ -n "${ZSH_VERSION:-}" ]; then
        setopt LOCAL_OPTIONS NULL_GLOB
    fi
    local f
    for f in /etc/profile.d/*; do
        [ -e "$f" ] || continue
        CONFIG_FILES+=("$f")
    done
}
_pc_append_profiled
unset -f _pc_append_profiled

# --- source map: attribute each PATH dir to the startup file:line ------------
# Populates SRC_FILE[dir] and SRC_LINE[dir]. Dirs added before any startup file
# (inherited/session) get SRC_FILE="" .
declare -A SRC_FILE SRC_LINE
SRC_MAP_BUILT=0
_pc_build_source_map() {
    [ "$SRC_MAP_BUILT" -eq 1 ] && return
    SRC_MAP_BUILT=1
    local shell_name baseline trace marker
    shell_name="$(basename -- "${SHELL:-/bin/bash}")"
    baseline="/usr/bin:/bin"
    marker='@@PCHK@@'
    _pc_mktemp
    trace="$_pc_tmp"

    if ! case "$shell_name" in
        zsh)
            PATH="$baseline" PS4="${marker}|%x|%I|\${PATH}|" \
                _pc_run_with_timeout "${SHELL}" -o promptsubst -x -l -i -c 'true' \
                </dev/null >/dev/null 2>"$trace"
            ;;
        *)
            PATH="$baseline" PS4="${marker}|\${BASH_SOURCE}|\${LINENO}|\${PATH}|" \
                _pc_run_with_timeout "${SHELL:-/bin/bash}" -x -l -i -c 'true' \
                </dev/null >/dev/null 2>"$trace"
            ;;
    esac then
        printf '%s: timed out or failed tracing %s\n' "$PROGNAME" "${SHELL:-/bin/bash}" >&2
        return 1
    fi

    while IFS=$'\t' read -r f l d; do
        [ -z "$d" ] && continue
        [ -n "${SRC_FILE["$d"]+x}" ] && continue
        if [ "$f" = "__BASELINE__" ]; then
            SRC_FILE["$d"]=""
            SRC_LINE["$d"]=""
        else
            SRC_FILE["$d"]="$f"
            SRC_LINE["$d"]="$l"
        fi
    done < <(awk -v marker="$marker" '
        function emit(path, src, ln,   n, arr, i, d) {
            n = split(path, arr, ":")
            for (i = 1; i <= n; i++) {
                d = arr[i]
                if (d == "" || (d in seen)) continue
                seen[d] = 1
                print src "\t" ln "\t" d
            }
        }
        {
            idx = index($0, marker "|"); if (idx == 0) next
            split(substr($0, idx), f, "|")
            src = f[2]; ln = f[3]; path = f[4]
            if (path == "") next
            if (!started) { emit(path, "__BASELINE__", "-"); started = 1 }
            else if (path != prevPath) { emit(path, prevSrc, prevLn) }
            prevSrc = src; prevLn = ln; prevPath = path
        }
    ' "$trace")

    rm -f -- "$trace"
}

_pc_static_source() {
    local dir="$1" hits
    hits="$(grep -lF -- "$dir" "${CONFIG_FILES[@]}" 2>/dev/null | paste -sd, - || true)"
    printf '%s' "$hits"
    return 0
}

# Human-readable source description for a directory.
_pc_describe_source() {
    local dir="$1" f l guess
    f="${SRC_FILE["$dir"]:-__unset__}"
    if [ "$f" != "__unset__" ] && [ -n "$f" ]; then
        printf '%s:%s' "$f" "${SRC_LINE["$dir"]}"
        return
    fi
    guess="$(_pc_static_source "$dir")"
    if [ -n "$guess" ]; then
        printf 'environment/session (referenced in %s)' "$guess"
    else
        printf 'environment/session'
    fi
}

# --- comment out a specific line in a startup file (reversible) --------------
declare -A BACKED_UP
_pc_backup_once() {
    local f="$1"
    [ -n "${BACKED_UP["$f"]+x}" ] && return
    cp -- "$f" "$f.bak.path_cleaner.$(date +%Y%m%d%H%M%S)"
    BACKED_UP["$f"]=1
    printf '  backup: %s.bak.path_cleaner.*\n' "$f" >&2
}
_pc_comment_rc_line() {
    local f="$1" ln="$2" tmp
    [ -f "$f" ] || {
        printf '  ! cannot edit (not a file): %s\n' "$f" >&2
        return 1
    }
    case "$ln" in '' | *[!0-9]*) return 1 ;; *) ;; esac
    _pc_backup_once "$f"
    _pc_mktemp
    tmp="$_pc_tmp"
    awk -v ln="$ln" '
        NR==ln && $0 !~ /^[[:space:]]*#/ { $0 = "# [path_cleaner removed] " $0 }
        { print }
    ' "$f" >"$tmp"
    mv -- "$tmp" "$f"
    printf '  commented %s:%s\n' "$f" "$ln" >&2
}

# --- reports / outputs -------------------------------------------------------
_pc_print_report() {
    printf '\n'
    printf '%sPATH cleanup (report only)%s\n\n' "$C_HDR" "$C_RST"
    printf '%sKept (%d):%s\n' "$C_HDR" "${#KEPT[@]}" "$C_RST"
    for dir in ${KEPT[@]+"${KEPT[@]}"}; do printf '  %s%s%s\n' "$C_OK" "$dir" "$C_RST"; done
    if [ "${#REMOVED_MISSING[@]}" -gt 0 ]; then
        printf '\n%sWould remove — does not exist (%d):%s\n' "$C_HDR" "${#REMOVED_MISSING[@]}" "$C_RST"
        for dir in ${REMOVED_MISSING[@]+"${REMOVED_MISSING[@]}"}; do printf '  %s%s%s\n' "$C_BAD" "$dir" "$C_RST"; done
    fi
    if [ "${#REMOVED_DUP[@]}" -gt 0 ]; then
        printf '\n%sWould remove — duplicate (%d):%s\n' "$C_HDR" "${#REMOVED_DUP[@]}" "$C_RST"
        for dir in ${REMOVED_DUP[@]+"${REMOVED_DUP[@]}"}; do printf '  %s%s%s\n' "$C_DUP" "$dir" "$C_RST"; done
    fi
    printf '\n%sCleaned PATH:%s\n%s\n' "$C_HDR" "$C_RST" "$CLEAN_PATH"
    printf '\n'
}

_pc_apply_session() {
    if [ "$SOURCED" -eq 1 ]; then
        PATH="$CLEAN_PATH"
        export PATH
        _pc_rehash
        printf 'Current session PATH cleaned: kept %d, removed %d missing, %d duplicate.\n' \
            "${#KEPT[@]}" "${#REMOVED_MISSING[@]}" "${#REMOVED_DUP[@]}" >&2
        return 0
    fi
    printf 'Cannot change the current shell from a child process.\n' >&2
    printf 'Source this script instead:\n' >&2
    printf '  source %s\n' "$SCRIPT_PATH" >&2
    return 1
}

# --- permanent purge of startup lines adding non-existent dirs ---------------
_pc_do_purge() {
    _pc_build_source_map
    declare -A TO_COMMENT # key "file\tline" -> 1
    local orphan=()       # non-existent, no rc line we can edit
    local dir f l

    for dir in ${REMOVED_MISSING[@]+"${REMOVED_MISSING[@]}"}; do
        f="${SRC_FILE["$dir"]:-__unset__}"
        l="${SRC_LINE["$dir"]:-}"
        if [ "$f" != "__unset__" ] && [ -n "$f" ] && [ -n "$l" ]; then
            TO_COMMENT["$f"$'\t'"$l"]=1
        else
            orphan+=("$dir")
        fi
    done

    if [ "${#TO_COMMENT[@]}" -eq 0 ]; then
        printf 'Nothing to purge: no startup-file lines add a missing directory.\n' >&2
    else
        printf '%sThe following startup-file lines add directories that do not exist:%s\n' \
            "$C_HDR" "$C_RST" >&2
        local key file line
        for key in "${!TO_COMMENT[@]}"; do
            file="${key%%$'\t'*}"
            line="${key#*$'\t'}"
            printf '  %s%s:%s%s\n' "$C_BAD" "$file" "$line" "$C_RST" >&2
        done
        if [ "$ASSUME_YES" -ne 1 ]; then
            printf 'Comment out these lines (a backup is made)? [y/N] ' >&2
            local ans
            read -r ans </dev/tty 2>/dev/null || read -r ans
            case "$ans" in y | Y | yes | YES) ;; *)
                printf 'Aborted; no changes made.\n' >&2
                return
                ;;
            esac
        fi
        for key in "${!TO_COMMENT[@]}"; do
            file="${key%%$'\t'*}"
            line="${key#*$'\t'}"
            _pc_comment_rc_line "$file" "$line" || true
        done
        printf '%sDone. Changes take effect in new shells.%s\n' "$C_OK" "$C_RST" >&2
    fi

    if [ "${#orphan[@]}" -gt 0 ]; then
        printf '\n%sNot purgeable (set before any startup file — login manager / session / launcher):%s\n' \
            "$C_HDR" "$C_RST" >&2
        for dir in ${orphan[@]+"${orphan[@]}"}; do printf '  %s%s%s\n' "$C_DUP" "$dir" "$C_RST" >&2; done
    fi

    # Also tidy the current session if we can.
    [ "$SOURCED" -eq 1 ] && {
        PATH="$CLEAN_PATH"
        export PATH
        _pc_rehash
    }
}

# --- interactive: decide per entry -------------------------------------------
_pc_do_interactive() {
    _pc_build_source_map
    local new_kept=() dir exists src ans
    declare -A COMMENTED

    printf '%sInteractive PATH cleanup%s\n' "$C_HDR" "$C_RST" >&2
    printf 'For each entry choose: [s]kip (keep)  [r]emove from session  [d]elete permanently  [q]uit\n\n' >&2

    _pc_split_path "$PATH"
    for dir in ${pc_parts[@]+"${pc_parts[@]}"}; do
        [ -z "$dir" ] && continue
        if [ -d "$dir" ]; then exists="${C_OK}exists${C_RST}"; else exists="${C_BAD}MISSING${C_RST}"; fi
        src="$(_pc_describe_source "$dir")"
        printf '%s%s%s  [%s]\n    %s<- %s%s\n' "$C_HDR" "$dir" "$C_RST" "$exists" "$C_SRC" "$src" "$C_RST" >&2
        printf '  [s/r/d/q]? ' >&2
        read -r ans </dev/tty 2>/dev/null || read -r ans
        case "$ans" in
            r | R) printf '  -> removed from session\n\n' >&2 ;; # just don't keep it
            d | D)
                local f="${SRC_FILE["$dir"]:-__unset__}" l="${SRC_LINE["$dir"]:-}"
                if [ "$f" != "__unset__" ] && [ -n "$f" ] && [ -n "$l" ]; then
                    if [ -z "${COMMENTED["$f"$'\t'"$l"]+x}" ]; then
                        _pc_comment_rc_line "$f" "$l" || true
                        COMMENTED["$f"$'\t'"$l"]=1
                    fi
                    printf '  -> deleted permanently (and from session)\n\n' >&2
                else
                    printf '  -> no startup-file line to edit (environment/session); removed from session only\n\n' >&2
                fi
                ;; # not kept
            q | Q)
                printf '  -> quit\n' >&2
                break
                ;;
            *)
                new_kept+=("$dir")
                printf '  -> kept\n\n' >&2
                ;;
        esac
    done

    # Rebuild session PATH from kept entries (dedup, keep order).
    local rebuilt="" d
    declare -A seen2
    for d in ${new_kept[@]+"${new_kept[@]}"}; do
        [ -n "${seen2["$d"]+x}" ] && continue
        seen2["$d"]=1
        rebuilt="${rebuilt:+$rebuilt:}$d"
    done
    if [ "$SOURCED" -eq 1 ]; then
        PATH="$rebuilt"
        export PATH
        _pc_rehash
        printf '%sSession PATH updated.%s\n' "$C_OK" "$C_RST" >&2
    else
        printf '\n%sSession not changed (run via the path_cleaner function or source).%s\n' "$C_DUP" "$C_RST" >&2
        printf 'Resulting session PATH would be:\n%s\n' "$rebuilt" >&2
    fi
}

# --- install a path_cleaner shell function -----------------------------------
_pc_install_function() {
    local rc="$RC_OVERRIDE"
    if [ -z "$rc" ]; then
        case "$(basename -- "${SHELL:-bash}")" in
            zsh) rc="$HOME/.zshrc" ;;
            bash) rc="$HOME/.bashrc" ;;
            *) rc="$HOME/.profile" ;;
        esac
    fi
    [ -e "$rc" ] || : >"$rc"
    _pc_backup_once "$rc"

    local start="# >>> path_cleaner function >>>"
    local end="# <<< path_cleaner function <<<"
    local tmp
    _pc_mktemp
    tmp="$_pc_tmp"
    awk -v s="$start" -v e="$end" '
        $0==s {skip=1} skip {if ($0==e) skip=0; next} {print}
    ' "$rc" >"$tmp"
    [ -s "$tmp" ] && [ "$(tail -c1 -- "$tmp")" != "" ] && printf '\n' >>"$tmp"
    {
        printf '\n%s\n' "$start"
        printf 'path_cleaner() { source %q "$@"; }\n' "$SCRIPT_PATH"
        printf '%s\n' "$end"
    } >>"$tmp"
    mv -- "$tmp" "$rc"

    printf "Installed 'path_cleaner' function into: %s\n" "$rc" >&2
    printf "Open a new shell (or run: source %s), then use:\n" "$rc" >&2
    printf '  path_cleaner            # clean current session\n' >&2
    printf '  path_cleaner -i         # interactive\n' >&2
    printf '  path_cleaner --purge    # permanently remove dead PATH lines\n' >&2
}

# --- dispatch ----------------------------------------------------------------
_pc_status=0
case "$MODE" in
    help) _pc_usage ;;
    error) _pc_status=2 ;;
    quiet) printf '%s\n' "$CLEAN_PATH" ;;
    export) printf 'export PATH=%q\n' "$CLEAN_PATH" ;;
    report) _pc_print_report ;;
    session) _pc_apply_session || _pc_status=1 ;;
    purge) _pc_do_purge ;;
    interactive) _pc_do_interactive ;;
    install) _pc_install_function ;;
    *)
        printf '%s: unknown mode %s\n' "$PROGNAME" "$MODE" >&2
        _pc_status=1
        ;;
esac

# Drop helpers/globals (keep PATH) and restore the caller's options when sourced.
_pc_rm_temps
if [ -n "${_pc_saved_trap:-}" ]; then
    eval "$_pc_saved_trap"
else
    trap - EXIT
fi
if [ "$SOURCED" -eq 1 ]; then
    if [ "$_pc_had_lc_all" -eq 1 ]; then
        LC_ALL="$_pc_old_lc_all"
        export LC_ALL
    else
        unset LC_ALL
    fi
fi
unset -f \
    _pc_mktemp \
    _pc_rm_temps \
    _pc_rehash \
    _pc_run_with_timeout \
    _pc_split_path \
    _pc_usage \
    _pc_unrecognized_option \
    _pc_build_source_map \
    _pc_static_source \
    _pc_describe_source \
    _pc_backup_once \
    _pc_comment_rc_line \
    _pc_print_report \
    _pc_apply_session \
    _pc_do_purge \
    _pc_do_interactive \
    _pc_install_function \
    2>/dev/null || true
unset \
    pc_parts SEEN KEPT REMOVED_MISSING REMOVED_DUP CLEAN_PATH \
    CONFIG_FILES SRC_FILE SRC_LINE SRC_MAP_BUILT BACKED_UP \
    MODE RC_OVERRIDE ASSUME_YES \
    C_OK C_BAD C_DUP C_HDR C_SRC C_RST \
    SCRIPT_PATH PROGNAME _self arg dir \
    _pc_temp_files _pc_tmp _pc_saved_trap TRACE_TIMEOUT \
    _pc_had_lc_all _pc_old_lc_all \
    2>/dev/null || true
if [ "$SOURCED" -eq 1 ]; then
    if [ -n "${ZSH_VERSION:-}" ]; then
        [ "$_pc_had_errexit" -eq 0 ] && unsetopt errexit
        [ "$_pc_had_nounset" -eq 0 ] && unsetopt nounset
        [ "$_pc_had_pipefail" -eq 0 ] && unsetopt pipefail
    else
        [ "$_pc_had_errexit" -eq 0 ] && set +e
        [ "$_pc_had_nounset" -eq 0 ] && set +u
        [ "$_pc_had_pipefail" -eq 0 ] && set +o pipefail
    fi
fi
_pc_was_sourced="$SOURCED"
unset _pc_had_errexit _pc_had_nounset _pc_had_pipefail SOURCED
if [ "$_pc_was_sourced" -eq 1 ]; then
    unset _pc_was_sourced
    return "$_pc_status"
fi
unset _pc_was_sourced
exit "$_pc_status"
