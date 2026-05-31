#!/usr/bin/env bash
#
# path_cleaner.sh — clean $PATH: drop non-existent dirs and duplicates.
#
# IMPORTANT: to clean the *current session* you must SOURCE this script. Run
# as `./path_cleaner.sh` it executes in a child process and cannot change your
# current shell's PATH (so the session/interactive actions won't persist).
#
# Actions:
#   (default)            clean the CURRENT session (must be sourced)
#   --purge [rc]         PERMANENTLY comment out startup-file lines that add
#                        directories which do not exist (timestamped backup)
#   -i, --interactive    walk every PATH entry and choose per entry:
#                          skip / remove from session / delete permanently
#   --install [rc]       add a `path_cleaner` shell function to your rc file
#   -r, --report         show what would be cleaned (no changes)
#   -q, --quiet          print only the cleaned PATH string (for scripts)
#   -e, --export         print an `export PATH=...` line (for `eval`)
#   -h, --help           this help
#
# Usage (source it so it affects your current shell):
#   source ./path_cleaner.sh                 # clean current session
#   source ./path_cleaner.sh -i              # interactive, per entry
#   source ./path_cleaner.sh --purge         # permanently remove dead lines
#
# Run directly (no session change; reporting / one-off output / setup):
#   ./path_cleaner.sh -r                     # report what would be cleaned
#   ./path_cleaner.sh --purge                # edit rc files permanently
#   ./path_cleaner.sh --install              # add a `path_cleaner` function

set -u

# --- detect whether we are being sourced -------------------------------------
SOURCED=0
if [ -n "${ZSH_VERSION:-}" ]; then
    case "${ZSH_EVAL_CONTEXT:-}" in *:file*) SOURCED=1 ;; *) ;; esac
elif [ -n "${BASH_VERSION:-}" ]; then
    [ "${BASH_SOURCE[0]}" != "$0" ] && SOURCED=1
fi

# Absolute path to this script (used by --install). In bash when sourced, $0 is
# the shell, so use BASH_SOURCE; in zsh (and when executed) $0 is the script.
if [ -n "${BASH_SOURCE:-}" ]; then
    _self="${BASH_SOURCE[0]}"
else
    _self="$0"
fi
SCRIPT_PATH="$(cd "$(dirname "$_self")" 2>/dev/null && pwd)/$(basename "$_self")"

# --- argument parsing --------------------------------------------------------
MODE="session"
RC_OVERRIDE=""
ASSUME_YES=0
for arg in "$@"; do
    case "$arg" in
        -s|--session)              MODE="session" ;;
        -p|--purge|--permanent)    MODE="purge" ;;
        -i|--menu|--interactive)   MODE="interactive" ;;
        --install)                 MODE="install" ;;
        -r|--report)               MODE="report" ;;
        -q|--quiet)                MODE="quiet" ;;
        -e|--export)               MODE="export" ;;
        -y|--yes)                  ASSUME_YES=1 ;;
        -h|--help)                 MODE="help" ;;
        -*)
            printf 'Unknown option: %s\n' "$arg" >&2
            MODE="help"
            ;;
        *) RC_OVERRIDE="$arg" ;;
    esac
done

# --- colors ------------------------------------------------------------------
if [ -t 1 ] && [ "$MODE" != "quiet" ] && [ "$MODE" != "export" ]; then
    C_OK=$'\033[32m'; C_BAD=$'\033[31m'; C_DUP=$'\033[33m'
    C_HDR=$'\033[1;36m'; C_SRC=$'\033[90m'; C_RST=$'\033[0m'
else
    C_OK=''; C_BAD=''; C_DUP=''; C_HDR=''; C_SRC=''; C_RST=''
fi

# --- compute the auto-cleaned PATH (missing dirs + duplicates) ---------------
declare -A SEEN
KEPT=(); REMOVED_MISSING=(); REMOVED_DUP=()
IFS=':' read -r -a _entries <<< "$PATH"
for dir in "${_entries[@]}"; do
    [ -z "$dir" ] && continue
    if [ ! -d "$dir" ]; then REMOVED_MISSING+=("$dir"); continue; fi
    if [ -n "${SEEN[$dir]+x}" ]; then REMOVED_DUP+=("$dir"); continue; fi
    SEEN["$dir"]=1; KEPT+=("$dir")
done
CLEAN_PATH=""
for dir in "${KEPT[@]}"; do CLEAN_PATH="${CLEAN_PATH:+$CLEAN_PATH:}$dir"; done

# --- config files for static fallback ----------------------------------------
CONFIG_FILES=(
    /etc/profile /etc/profile.d/* /etc/bash.bashrc /etc/bashrc /etc/environment
    /etc/zsh/zshenv /etc/zsh/zprofile /etc/zsh/zshrc /etc/zsh/zlogin
    /etc/zshenv /etc/zprofile /etc/zshrc
    "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"
    "$HOME/.zshenv" "$HOME/.zprofile" "$HOME/.zshrc" "$HOME/.zlogin"
)

# --- source map: attribute each PATH dir to the startup file:line ------------
# Populates SRC_FILE[dir] and SRC_LINE[dir]. Dirs added before any startup file
# (inherited/session) get SRC_FILE="" .
declare -A SRC_FILE SRC_LINE
SRC_MAP_BUILT=0
build_source_map() {
    [ "$SRC_MAP_BUILT" -eq 1 ] && return
    SRC_MAP_BUILT=1
    local shell_name baseline trace marker
    shell_name="$(basename "${SHELL:-/bin/bash}")"
    baseline="/usr/bin:/bin"
    marker='@@PCHK@@'
    trace="$(mktemp)"

    case "$shell_name" in
        zsh)
            PATH="$baseline" PS4="${marker}|%x|%I|\${PATH}|" \
                "${SHELL}" -o promptsubst -x -l -i -c 'true' \
                </dev/null >/dev/null 2>"$trace"
            ;;
        *)
            PATH="$baseline" PS4="${marker}|\${BASH_SOURCE}|\${LINENO}|\${PATH}|" \
                "${SHELL:-/bin/bash}" -x -l -i -c 'true' \
                </dev/null >/dev/null 2>"$trace"
            ;;
    esac

    while IFS=$'\t' read -r f l d; do
        [ -z "$d" ] && continue
        [ -n "${SRC_FILE[$d]+x}" ] && continue
        if [ "$f" = "__BASELINE__" ]; then
            SRC_FILE["$d"]=""; SRC_LINE["$d"]=""
        else
            SRC_FILE["$d"]="$f"; SRC_LINE["$d"]="$l"
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

    rm -f "$trace"
}

static_source() {
    local dir="$1" hits
    hits="$(grep -lF -- "$dir" "${CONFIG_FILES[@]}" 2>/dev/null | paste -sd, -)"
    [ -n "$hits" ] && printf '%s' "$hits"
}

# Human-readable source description for a directory.
describe_source() {
    local dir="$1" f l guess
    f="${SRC_FILE[$dir]:-__unset__}"
    if [ "$f" != "__unset__" ] && [ -n "$f" ]; then
        printf '%s:%s' "$f" "${SRC_LINE[$dir]}"
        return
    fi
    guess="$(static_source "$dir")"
    if [ -n "$guess" ]; then
        printf 'environment/session (referenced in %s)' "$guess"
    else
        printf 'environment/session'
    fi
}

# --- comment out a specific line in a startup file (reversible) --------------
declare -A BACKED_UP
backup_once() {
    local f="$1"
    [ -n "${BACKED_UP[$f]+x}" ] && return
    cp -- "$f" "$f.bak.path_cleaner.$(date +%Y%m%d%H%M%S)"
    BACKED_UP["$f"]=1
    printf '  backup: %s.bak.path_cleaner.*\n' "$f" >&2
}
comment_rc_line() {
    local f="$1" ln="$2" tmp
    [ -f "$f" ] || { printf '  ! cannot edit (not a file): %s\n' "$f" >&2; return 1; }
    case "$ln" in ''|*[!0-9]*) return 1 ;; *) ;; esac
    backup_once "$f"
    tmp="$(mktemp)"
    awk -v ln="$ln" '
        NR==ln && $0 !~ /^[[:space:]]*#/ { $0 = "# [path_cleaner removed] " $0 }
        { print }
    ' "$f" > "$tmp"
    mv -- "$tmp" "$f"
    printf '  commented %s:%s\n' "$f" "$ln" >&2
}

# --- reports / outputs -------------------------------------------------------
print_report() {
    echo ''
    printf '%sPATH cleanup (report only)%s\n\n' "$C_HDR" "$C_RST"
    printf '%sKept (%d):%s\n' "$C_HDR" "${#KEPT[@]}" "$C_RST"
    for dir in "${KEPT[@]}"; do printf '  %s%s%s\n' "$C_OK" "$dir" "$C_RST"; done
    if [ "${#REMOVED_MISSING[@]}" -gt 0 ]; then
        printf '\n%sWould remove — does not exist (%d):%s\n' "$C_HDR" "${#REMOVED_MISSING[@]}" "$C_RST"
        for dir in "${REMOVED_MISSING[@]}"; do printf '  %s%s%s\n' "$C_BAD" "$dir" "$C_RST"; done
    fi
    if [ "${#REMOVED_DUP[@]}" -gt 0 ]; then
        printf '\n%sWould remove — duplicate (%d):%s\n' "$C_HDR" "${#REMOVED_DUP[@]}" "$C_RST"
        for dir in "${REMOVED_DUP[@]}"; do printf '  %s%s%s\n' "$C_DUP" "$dir" "$C_RST"; done
    fi
    printf '\n%sCleaned PATH:%s\n%s\n' "$C_HDR" "$C_RST" "$CLEAN_PATH"
    echo ''
}

apply_session() {
    if [ "$SOURCED" -eq 1 ]; then
        PATH="$CLEAN_PATH"; export PATH
        printf 'Current session PATH cleaned: kept %d, removed %d missing, %d duplicate.\n' \
            "${#KEPT[@]}" "${#REMOVED_MISSING[@]}" "${#REMOVED_DUP[@]}" >&2
    else
        printf 'Cannot change the current shell from a child process.\n' >&2
        printf 'Source this script instead:\n' >&2
        printf '  source %s\n' "$SCRIPT_PATH" >&2
    fi
}

# --- permanent purge of startup lines adding non-existent dirs ---------------
do_purge() {
    build_source_map
    declare -A TO_COMMENT          # key "file\tline" -> 1
    local orphan=()                # non-existent, no rc line we can edit
    local dir f l

    for dir in "${REMOVED_MISSING[@]}"; do
        f="${SRC_FILE[$dir]:-__unset__}"
        l="${SRC_LINE[$dir]:-}"
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
            file="${key%%$'\t'*}"; line="${key#*$'\t'}"
            printf '  %s%s:%s%s\n' "$C_BAD" "$file" "$line" "$C_RST" >&2
        done
        if [ "$ASSUME_YES" -ne 1 ]; then
            printf 'Comment out these lines (a backup is made)? [y/N] ' >&2
            local ans; read -r ans </dev/tty 2>/dev/null || read -r ans
            case "$ans" in y|Y|yes|YES) ;; *) printf 'Aborted; no changes made.\n' >&2; return ;; esac
        fi
        for key in "${!TO_COMMENT[@]}"; do
            file="${key%%$'\t'*}"; line="${key#*$'\t'}"
            comment_rc_line "$file" "$line"
        done
        printf '%sDone. Changes take effect in new shells.%s\n' "$C_OK" "$C_RST" >&2
    fi

    if [ "${#orphan[@]}" -gt 0 ]; then
        printf '\n%sNot purgeable (set before any startup file — login manager / session / launcher):%s\n' \
            "$C_HDR" "$C_RST" >&2
        for dir in "${orphan[@]}"; do printf '  %s%s%s\n' "$C_DUP" "$dir" "$C_RST" >&2; done
    fi

    # Also tidy the current session if we can.
    [ "$SOURCED" -eq 1 ] && { PATH="$CLEAN_PATH"; export PATH; }
}

# --- interactive: decide per entry -------------------------------------------
do_interactive() {
    build_source_map
    local new_kept=() dir exists src ans
    declare -A COMMENTED

    printf '%sInteractive PATH cleanup%s\n' "$C_HDR" "$C_RST" >&2
    printf 'For each entry choose: [s]kip (keep)  [r]emove from session  [d]elete permanently  [q]uit\n\n' >&2

    IFS=':' read -r -a all_entries <<< "$PATH"
    for dir in "${all_entries[@]}"; do
        [ -z "$dir" ] && continue
        if [ -d "$dir" ]; then exists="${C_OK}exists${C_RST}"; else exists="${C_BAD}MISSING${C_RST}"; fi
        src="$(describe_source "$dir")"
        printf '%s%s%s  [%s]\n    %s<- %s%s\n' "$C_HDR" "$dir" "$C_RST" "$exists" "$C_SRC" "$src" "$C_RST" >&2
        printf '  [s/r/d/q]? ' >&2
        read -r ans </dev/tty 2>/dev/null || read -r ans
        case "$ans" in
            r|R) printf '  -> removed from session\n\n' >&2 ;;  # just don't keep it
            d|D)
                local f="${SRC_FILE[$dir]:-__unset__}" l="${SRC_LINE[$dir]:-}"
                if [ "$f" != "__unset__" ] && [ -n "$f" ] && [ -n "$l" ]; then
                    if [ -z "${COMMENTED[$f$'\t'$l]+x}" ]; then
                        comment_rc_line "$f" "$l"; COMMENTED["$f"$'\t'"$l"]=1
                    fi
                    printf '  -> deleted permanently (and from session)\n\n' >&2
                else
                    printf '  -> no startup-file line to edit (environment/session); removed from session only\n\n' >&2
                fi
                ;;  # not kept
            q|Q) printf '  -> quit\n' >&2; break ;;
            *)   new_kept+=("$dir"); printf '  -> kept\n\n' >&2 ;;
        esac
    done

    # Rebuild session PATH from kept entries (dedup, keep order).
    local rebuilt="" d; declare -A seen2
    for d in "${new_kept[@]}"; do
        [ -n "${seen2[$d]+x}" ] && continue; seen2["$d"]=1
        rebuilt="${rebuilt:+$rebuilt:}$d"
    done
    if [ "$SOURCED" -eq 1 ]; then
        PATH="$rebuilt"; export PATH
        printf '%sSession PATH updated.%s\n' "$C_OK" "$C_RST" >&2
    else
        printf '\n%sSession not changed (run via the path_cleaner function or source).%s\n' "$C_DUP" "$C_RST" >&2
        printf 'Resulting session PATH would be:\n%s\n' "$rebuilt" >&2
    fi
}

# --- install a path_cleaner shell function -----------------------------------
install_function() {
    local rc="$RC_OVERRIDE"
    if [ -z "$rc" ]; then
        case "$(basename "${SHELL:-bash}")" in
            zsh)  rc="$HOME/.zshrc" ;;
            bash) rc="$HOME/.bashrc" ;;
            *)    rc="$HOME/.profile" ;;
        esac
    fi
    [ -e "$rc" ] || : > "$rc"
    backup_once "$rc"

    local start="# >>> path_cleaner function >>>"
    local end="# <<< path_cleaner function <<<"
    local tmp; tmp="$(mktemp)"
    awk -v s="$start" -v e="$end" '
        $0==s {skip=1} skip {if ($0==e) skip=0; next} {print}
    ' "$rc" > "$tmp"
    [ -s "$tmp" ] && [ "$(tail -c1 "$tmp")" != "" ] && printf '\n' >> "$tmp"
    {
        printf '\n%s\n' "$start"
        printf 'path_cleaner() { source %q "$@"; }\n' "$SCRIPT_PATH"
        printf '%s\n' "$end"
    } >> "$tmp"
    mv -- "$tmp" "$rc"

    printf "Installed 'path_cleaner' function into: %s\n" "$rc" >&2
    printf "Open a new shell (or run: source %s), then use:\n" "$rc" >&2
    printf '  path_cleaner            # clean current session\n' >&2
    printf '  path_cleaner -i         # interactive\n' >&2
    printf '  path_cleaner --purge    # permanently remove dead PATH lines\n' >&2
}

# --- dispatch ----------------------------------------------------------------
case "$MODE" in
    help)        awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$_self" ;;
    quiet)       printf '%s\n' "$CLEAN_PATH" ;;
    export)      printf 'export PATH=%q\n' "$CLEAN_PATH" ;;
    report)      print_report ;;
    session)     apply_session ;;
    purge)       do_purge ;;
    interactive) do_interactive ;;
    install)     install_function ;;
    *)           printf 'Unknown mode: %s\n' "$MODE" >&2 ;;
esac
