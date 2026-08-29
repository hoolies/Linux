#!/usr/bin/env bash
# appimage-launcher-setup.sh
#
# Generate a "cursor"-style launcher + updater for any AppImage-based app.
# The generated command supports:
#   <app>                 launch latest (output hidden, detached)
#   <app> -v|--verbose    launch latest with full terminal output
#   <app> -u|--update     download/install latest (keeps newest N versions)
#   <app> --update --force re-download even if up to date
#   <app> --version       list current + available versions
#   <app> --version X.Y.Z launch a specific installed version
#   <app> -h|--help       help
#
# Configuration can be supplied interactively, or via a JSON / TOML / YAML file:
#   appimage-launcher-setup.sh config.json
#   appimage-launcher-setup.sh config.toml
#   appimage-launcher-setup.sh config.yaml
#
# Required keys:  name, api_url, install_dir, appimage_name
# Optional keys:  version_key (.version), download_url_key (.downloadUrl),
#                 bin_dir (~/.local/bin), keep (4)
#
# 'appimage_name' MUST contain the placeholder {version}
#   e.g.  Cursor-{version}-x86_64.AppImage
#
# The api_url must return JSON; 'version_key' and 'download_url_key' are jq
# filters selecting the version string and the AppImage download URL.
set -euo pipefail
export LC_ALL=C
unalias -a 2>/dev/null || true
unset -f rm mv cp grep awk sed cat chmod mkdir curl jq find sort 2>/dev/null || true

readonly PROGNAME="${0##*/}"
PROG=$PROGNAME
declare -A CFG

log() { printf '%s: %s\n' "$PROGNAME" "$*" >&2; }
die() {
    log "error: $*"
    exit 1
}
need() { command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"; }

unrecognized_option() {
    printf '%s: unrecognized option %s\n' "$PROGNAME" "$1" >&2
    printf "Try '%s --help' for more information.\n" "$PROGNAME" >&2
}

usage() {
    cat <<EOF
Usage: $PROGNAME [OPTION]... [CONFIG_FILE]
Generate a launcher and updater for an AppImage-based app.

Mandatory arguments to long options are mandatory for short options too.

      --example[=FORMAT]  print a sample config (json, toml, or yaml)
  -h, --help              display this help and exit

With no CONFIG_FILE, you are prompted for each value.
Required keys: name, api_url, install_dir, appimage_name.
appimage_name must contain {version}.
EOF
}

print_example() {
    case "${1:-json}" in
        toml)
            cat <<'EOF'
name = "cursor"
api_url = "https://cursor.com/api/download?platform=linux-x64&releaseTrack=stable"
install_dir = "/opt/Cursor"
appimage_name = "Cursor-{version}-x86_64.AppImage"
version_key = ".version"
download_url_key = ".downloadUrl"
bin_dir = "$HOME/.local/bin"
keep = 4
EOF
            ;;
        yaml | yml)
            cat <<'EOF'
name: cursor
api_url: "https://cursor.com/api/download?platform=linux-x64&releaseTrack=stable"
install_dir: "/opt/Cursor"
appimage_name: "Cursor-{version}-x86_64.AppImage"
version_key: ".version"
download_url_key: ".downloadUrl"
bin_dir: "$HOME/.local/bin"
keep: 4
EOF
            ;;
        *)
            cat <<'EOF'
{
  "name": "cursor",
  "api_url": "https://cursor.com/api/download?platform=linux-x64&releaseTrack=stable",
  "install_dir": "/opt/Cursor",
  "appimage_name": "Cursor-{version}-x86_64.AppImage",
  "version_key": ".version",
  "download_url_key": ".downloadUrl",
  "bin_dir": "$HOME/.local/bin",
  "keep": 4
}
EOF
            ;;
    esac
}

parse_config() {
    # Emits "key<TAB>value" lines for recognized keys.
    need python3
    python3 - "$1" <<'PY'
import sys, os
path = sys.argv[1]
ext = os.path.splitext(path)[1].lower()
with open(path, 'rb') as fh:
    raw = fh.read()
def j(): import json; return json.loads(raw.decode('utf-8'))
def t(): import tomllib; return tomllib.loads(raw.decode('utf-8'))
def y(): import yaml; return yaml.safe_load(raw.decode('utf-8'))
loaders = {'.json':[j], '.toml':[t], '.yaml':[y], '.yml':[y]}.get(ext, [j, t, y])
data, err = None, None
for fn in loaders:
    try:
        data = fn(); break
    except Exception as e:
        err = e
if data is None:
    sys.stderr.write(f"could not parse config: {err}\n"); sys.exit(2)
if not isinstance(data, dict):
    sys.stderr.write("config root must be a mapping/object\n"); sys.exit(2)
for k in ("name","api_url","install_dir","appimage_name",
          "version_key","download_url_key","bin_dir","keep"):
    if data.get(k) is not None:
        v = data[k]
        if isinstance(v, bool): v = str(v).lower()
        sys.stdout.write(f"{k}\t{v}\n")
PY
}

ask() { # ask VAR "Question" ["default"]
    local __var=$1 q=$2 def=${3-} ans
    if [[ ! -t 0 ]]; then
        [[ -n "$def" ]] && {
            printf -v "$__var" '%s' "$def"
            return
        }
        die "no value for '$__var' and input is not interactive"
    fi
    if [[ -n "$def" ]]; then
        read -r -p "$q [$def]: " ans
        ans=${ans:-$def}
    else
        read -r -p "$q: " ans
    fi
    printf -v "$__var" '%s' "$ans"
}

# normalize a leading ~ to the literal text $HOME so it expands at runtime
# in the generated launcher. The literal '$HOME' is intentional here, so the
# usual "tilde/expansion in single quotes" warnings do not apply.
tilde_to_home() {
    # shellcheck disable=SC2088,SC2016
    case "$1" in
        "~/"*) printf '$HOME/%s' "${1#"~/"}" ;;
        "~") printf '$HOME' ;;
        *) printf '%s' "$1" ;;
    esac
}

# ---- args -----------------------------------------------------------------
CONFIG_FILE=''
case "${1-}" in
    -h | --help)
        usage
        exit 0
        ;;
    --example)
        print_example "${2-json}"
        exit 0
        ;;
    --example=*)
        print_example "${1#--example=}"
        exit 0
        ;;
    '')
        :
        ;;
    -*)
        unrecognized_option "$1"
        exit 2
        ;;
    *)
        CONFIG_FILE=$1
        if [ "$#" -gt 1 ]; then
            unrecognized_option "$2"
            exit 2
        fi
        ;;
esac

# ---- load config file if provided -----------------------------------------
if [[ -n "$CONFIG_FILE" ]]; then
    [[ -f "$CONFIG_FILE" ]] || die "config file not found: $CONFIG_FILE"
    # Capture first so a parse failure (bad file, missing python3) aborts here,
    # instead of being hidden inside a process substitution.
    parsed=$(parse_config "$CONFIG_FILE") || die "failed to parse config: $CONFIG_FILE"
    while IFS=$'\t' read -r k v; do
        [[ -n "$k" ]] && CFG[$k]=$v
    done <<<"$parsed"
    log "loaded config from $CONFIG_FILE"
fi

# ---- resolve values (config -> prompt -> default) -------------------------
name=${CFG[name]:-}
api_url=${CFG[api_url]:-}
install_dir=${CFG[install_dir]:-}
appimage_name=${CFG[appimage_name]:-}
version_key=${CFG[version_key]:-.version}
download_key=${CFG[download_url_key]:-.downloadUrl}
bin_dir=${CFG[bin_dir]:-}
keep=${CFG[keep]:-4}

[[ -n "$name" ]] || ask name "Command name (e.g. cursor)"
[[ -n "$api_url" ]] || ask api_url "API URL returning JSON metadata"
[[ -n "$install_dir" ]] || ask install_dir "Install directory for AppImages" "\$HOME/Downloads/${name^}"
[[ -n "$appimage_name" ]] || ask appimage_name "AppImage name (must contain {version})" "${name^}-{version}-x86_64.AppImage"
[[ -n "${CFG[version_key]:-}" ]] || ask version_key "jq filter for version" "$version_key"
[[ -n "${CFG[download_url_key]:-}" ]] || ask download_key "jq filter for download URL" "$download_key"
[[ -n "$bin_dir" ]] || ask bin_dir "Directory to install the '$name' command" "\$HOME/.local/bin"
[[ -n "${CFG[keep]:-}" ]] || ask keep "How many versions to keep" "$keep"

# ---- validate -------------------------------------------------------------
[[ -n "$name" ]] || die "name is required"
[[ -n "$api_url" ]] || die "api_url is required"
[[ -n "$install_dir" ]] || die "install_dir is required"
[[ -n "$appimage_name" ]] || die "appimage_name is required"
[[ "$appimage_name" == *"{version}"* ]] || die "appimage_name must contain the {version} placeholder"
[[ "$keep" =~ ^[1-9][0-9]*$ ]] || die "keep must be a positive integer (got: $keep)"
[[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || die "name must be a simple command name"

install_dir=$(tilde_to_home "$install_dir")
bin_dir=$(tilde_to_home "$bin_dir")

# ---- derive glob + version regex from the template ------------------------
appimage_glob="${appimage_name//\{version\}/*}"
appimage_regex=$(printf '%s' "$appimage_name" |
    sed -E 's/[][(){}.^$*+?|\\]/\\&/g' |
    sed -E 's/\\\{version\\\}/([0-9]+\\.[0-9]+\\.[0-9]+)/')

# ---- write the launcher ---------------------------------------------------
out="$bin_dir/$name"
mkdir -p "$bin_dir"
if [[ -e "$out" && ! -f "$out" ]]; then
    die "$out exists and is not a regular file"
fi
[[ -e "$out" ]] && log "overwriting existing $out"

{
    printf '#!/usr/bin/env bash\n'
    printf '# %s launcher + updater. Generated by %s on %s\n' "$name" "$PROG" "$(date -Iseconds 2>/dev/null || date)"
    printf 'set -euo pipefail\n\n'
    printf 'APP_NAME=%q\n' "$name"
    printf 'API_URL=%q\n' "$api_url"
    printf 'INSTALL_DIR="%s"\n' "$install_dir"
    printf 'KEEP=%q\n' "$keep"
    printf 'VERSION_KEY=%q\n' "$version_key"
    printf 'DOWNLOAD_KEY=%q\n' "$download_key"
    printf 'APPIMAGE_TEMPLATE=%q\n' "$appimage_name"
    printf 'APPIMAGE_GLOB=%q\n' "$appimage_glob"
    printf 'APPIMAGE_REGEX=%q\n' "$appimage_regex"
    printf '\n'
    cat <<'LAUNCHER'
DO_UPDATE=0
SHOW_VERSION=0
PICK_VERSION=''
FORCE=0
VERBOSE=0
PASSTHRU=()

log() { printf '%s: %s\n' "$APP_NAME" "$*" >&2; }
die() { log "error: $*"; exit 1; }

usage() {
  cat <<USAGE
Usage: $APP_NAME [options] [-- args passed to the app]

  (no options)        Launch the latest installed version (output hidden)
  -v, --verbose       Launch with full output shown in the terminal
  -u, --update        Download and install the latest version (keeps newest $KEEP)
  -f, --force         With --update: re-download even if up to date
      --version       List current version and versions in the install folder
      --version X.Y.Z Launch a specific installed version
  -h, --help          Show this help

Install dir: $INSTALL_DIR
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -u|--update) DO_UPDATE=1; shift ;;
    -f|--force) FORCE=1; shift ;;
    -v|--verbose) VERBOSE=1; shift ;;
    --version)
      SHOW_VERSION=1; shift
      if [[ $# -gt 0 && "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        PICK_VERSION=$1; shift
      fi
      ;;
    -h|--help) usage; exit 0 ;;
    --) shift; PASSTHRU+=("$@"); break ;;
    *) PASSTHRU+=("$1"); shift ;;
  esac
done

mkdir -p "$INSTALL_DIR"

ver_of() {
  local f=$1
  [[ "$f" =~ $APPIMAGE_REGEX ]] && printf '%s\n' "${BASH_REMATCH[1]}"
}

list_appimages() {
  find "$INSTALL_DIR" -maxdepth 1 -name "$APPIMAGE_GLOB" -type f 2>/dev/null | sort -V
}

latest_appimage() {
  local all
  mapfile -t all < <(list_appimages)
  [[ ${#all[@]} -gt 0 ]] && printf '%s\n' "${all[-1]}"
}

appimage_for() {
  local p="$INSTALL_DIR/${APPIMAGE_TEMPLATE/\{version\}/$1}"
  [[ -f "$p" ]] && printf '%s\n' "$p"
}

launch() {
  local app=$1; shift
  [[ -x "$app" ]] || chmod +x "$app" 2>/dev/null || true
  if [[ "$VERBOSE" -eq 1 ]]; then
    log "launching $app (verbose)"
    exec "$app" "$@"
  else
    nohup "$app" "$@" >/dev/null 2>&1 < /dev/null &
    disown 2>/dev/null || true
  fi
}

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }

prune_old() {
  local all
  mapfile -t all < <(list_appimages)
  local total=${#all[@]}
  if (( total > KEEP )); then
    local i remove=$(( total - KEEP ))
    for (( i = 0; i < remove; i++ )); do
      log "pruning old version: $(ver_of "${all[i]}")"
      rm -f "${all[i]}"
    done
  fi
}

do_update() {
  need_cmd curl
  need_cmd jq

  local current local_ver=''
  current=$(latest_appimage || true)
  [[ -n "$current" ]] && local_ver=$(ver_of "$current")
  log "local:  ${local_ver:-none}"

  local meta remote_ver download_url
  meta=$(curl -fsSL "$API_URL") || die "failed to fetch release metadata"
  remote_ver=$(jq -r "$VERSION_KEY" <<<"$meta")
  download_url=$(jq -r "$DOWNLOAD_KEY" <<<"$meta")
  [[ -n "$remote_ver" && "$remote_ver" != null ]] || die "invalid API response (version)"
  [[ -n "$download_url" && "$download_url" != null ]] || die "invalid API response (download url)"
  log "remote: $remote_ver"

  if [[ "$local_ver" == "$remote_ver" && "$FORCE" -eq 0 ]]; then
    log "already up to date."
    prune_old
    return 0
  fi

  local dest="$INSTALL_DIR/${APPIMAGE_TEMPLATE/\{version\}/$remote_ver}"
  local tmp="${dest}.part.$$"
  log "downloading $remote_ver ..."
  curl -fL --progress-bar "$download_url" -o "$tmp"
  file "$tmp" | grep -q 'ELF 64-bit' || { rm -f "$tmp"; die "download is not a valid AppImage"; }
  chmod +x "$tmp"
  rm -f "$dest"
  mv "$tmp" "$dest"
  log "installed: $dest"
  prune_old
}

# ---- dispatch -------------------------------------------------------------
if [[ "$DO_UPDATE" -eq 1 ]]; then
  do_update
  exit 0
fi

if [[ "$SHOW_VERSION" -eq 1 && -z "$PICK_VERSION" ]]; then
  current=$(latest_appimage || true)
  current_ver=''
  [[ -n "$current" ]] && current_ver=$(ver_of "$current")
  if [[ -z "$current_ver" ]]; then
    log "no versions installed in $INSTALL_DIR (run: $APP_NAME --update)"
    exit 1
  fi
  printf 'Current: %s\n' "$current_ver"
  printf 'Available in %s:\n' "$INSTALL_DIR"
  while IFS= read -r f; do
    v=$(ver_of "$f")
    if [[ "$v" == "$current_ver" ]]; then
      printf '  %s  *\n' "$v"
    else
      printf '  %s\n' "$v"
    fi
  done < <(list_appimages | sort -rV)
  exit 0
fi

if [[ -n "$PICK_VERSION" ]]; then
  app=$(appimage_for "$PICK_VERSION" || true)
  if [[ -z "$app" ]]; then
    log "version $PICK_VERSION not found in $INSTALL_DIR"
    log "available: $(list_appimages | while IFS= read -r f; do ver_of "$f"; done | sort -rV | paste -sd' ' -)"
    exit 1
  fi
  launch "$app" "${PASSTHRU[@]}"
  exit 0
fi

app=$(latest_appimage || true)
[[ -n "$app" ]] || die "no $APP_NAME installed in $INSTALL_DIR (run: $APP_NAME --update)"
launch "$app" "${PASSTHRU[@]}"
LAUNCHER
} >"$out"

chmod +x "$out"

log "generated launcher: $out"
log "  app name     : $name"
log "  api url      : $api_url"
log "  install dir  : $install_dir"
log "  appimage     : $appimage_name"
log "  keep         : $keep versions"
case ":$PATH:" in
    *":$bin_dir:"*) : ;;
    *) log "note: $bin_dir is not on your PATH; add it to use '$name' directly" ;;
esac
log "next: run '$name --update' to download the first version"
