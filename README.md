# Linux

Personal collection of settings and scripts I use across different Linux
distributions. Everything here is POSIX/Bash shell tooling — no build step,
just clone and run the script you need.

```
.
├── Scripts/        # General-purpose, distro-agnostic scripts
│   ├── DeviceDiscovery/   # Hardware inventory suite
│   ├── Docking/           # Laptop vs. docking-station screen layouts
│   ├── IO/                # Disk read/write throughput logging
│   ├── Ubiquiti/          # Find & adopt UniFi devices on a network
│   └── Utilities/         # Misc. helpers (serial console, PATH tools, etc.)
└── Void/           # Void Linux specific tweaks (no systemd)
```

---

## Scripts

### DeviceDiscovery

A modular (v2.0.0), **100% POSIX-compliant** hardware inventory tool. It walks
`sysfs` and standard CLI tools to enumerate every device on the machine, then
emits either a human-readable report or JSON.

- `device_discovery.sh` — entry point (sources the modular `device_discovery/`
  tree of libraries and per-bus collectors).
- `device_discovery.monolithic.sh` — a self-contained single-file build with
  identical features (regenerate with
  `device_discovery/tools/build-monolithic.sh`).

Collectors cover: `usb`, `serial`, `bluetooth`, `wifi`, `network`, `storage`,
`input`, `pci`, `thunderbolt`, `wwan`, `can`, `nfc`, `display`, `audio`,
`camera`, `sensor`, `infiniband`, `fibre_channel`, `iscsi`, `power`,
`firewire`, `platform`, `i2c`, `spi`, `mtp`, `kernel`, and a `full_dump`.

```sh
./device_discovery.sh            # human-readable report
./device_discovery.sh --json     # JSON on stdout
./device_discovery.sh -v         # verbose; -vv for full diagnostics
./device_discovery.sh --help     # all flags
```

Useful flags: `--json`, `--no-prompt` (skip sudo prompt), `--pci-all`
(include PCI bridges), `--physical-only` (drop virtual devices). See
`DeviceDiscovery/device_discovery/README.md` for the full design notes.

### Docking

Two `xrandr` scripts to switch monitor layouts without running a background
service that watches for the dock — I just run the relevant script by hand.
Both also restart `conky` and `nitrogen` afterwards.

- `Dockin.sh` — layout for when the laptop is in the docking station (external
  monitors enabled).
- `Laptop.sh` — layout for the laptop screen only (externals off).

### IO

- `crws.sh` — samples `iotop` to record the top read/write throughput
  (KB/s) on the server, splitting results into `/var/log/IORead` and
  `/var/log/IOWrite` and rotating them daily. Helps decide whether an I/O
  problem is the server itself or the SAN's capacity.

### Ubiquiti

- `adopter.sh` — scans the local network with `nmap` for Ubiquiti devices,
  then SSHes into each (default `ubnt`/`ubnt` creds via `sshpass`) and points
  them at your UniFi controller with `set-inform`. Handy for re-adopting
  factory-reset gear. Requires `nmap`, `ssh`, and `sshpass`. The README in
  that folder also documents spinning up a `jacobalberty/unifi` controller
  container.

### Utilities

- `cursor` — launcher + updater for the Cursor AppImage. Launches the latest
  installed version (detached), or `-u`/`--update` to download the newest
  release from Cursor's API, `--version` to list/pick a version, keeping the
  newest 4 builds. Install dir defaults to `~/Downloads/Cursor`
  (`CURSOR_APPIMAGE_DIR`).
- `appimage-launcher-setup.sh` — generalizes the `cursor` script: generates a
  matching launcher/updater for *any* AppImage app from a JSON/TOML/YAML
  config (`name`, `api_url`, `install_dir`, `appimage_name`, …).
- `console.sh` — a minimal serial console. Configures a `/dev/tty*` device with
  `stty` (baud, stop bits, parity) and gives an interactive read/write loop.
  Usage: `./console.sh <device> <speed> <stopbits> <parity>`.
- `ip_dns_check.sh` — reads a list of IPs (one per line, `stop` to finish),
  pings each, and does a reverse-DNS (`dig -x`) lookup, reporting UP/DOWN and
  the PTR record.
- `path_checker.sh` — shows every entry in `$PATH` *and* which startup file/line
  added it (by re-running the login shell under xtrace from a minimal PATH).
  `-d` collapses/flags duplicates.
- `path_cleaner.sh` — cleans `$PATH` by dropping non-existent dirs and
  duplicates. Source it to affect the current session; `--purge` permanently
  comments out dead rc lines (with backup); `-i` interactive; `--install` adds
  a `path_cleaner` shell function; `-r` reports without changing anything.
- `parteh.sh` — fun terminal-cursor color cycling animation (OSC 12 escapes
  through a smooth rainbow palette).

---

## Void

Void Linux lacks `systemd`, so a number of things that "just work" elsewhere
need manual scripts. This folder collects the Void-specific bits.

- `bup.sh` / `bdown.sh` — bump the Intel backlight brightness up/down by 50
  (writes to `/sys/class/backlight/intel_backlight/brightness`).
- `brightmod.sh` — set backlight brightness to an explicit value.
- `conky.config` — my `conky` system-monitor configuration.
- `.files/.bashrc` — shell setup: PATH, history, `nvim` as `$EDITOR`, a colored
  prompt, and assorted aliases.
- `.files/autostart` — session autostart: `picom`, `nitrogen`, `conky`,
  keyboard layout toggle (`us,gr`), `kitty`, and `firefox`.

---

## Requirements

Most scripts are plain POSIX `sh`/Bash. Individual scripts note their extra
dependencies (e.g. DeviceDiscovery uses standard sysfs tooling; `adopter.sh`
needs `nmap`/`ssh`/`sshpass`; `cursor` needs `curl`/`jq`; `crws.sh` needs
`iotop`). Run any script with `-h`/`--help` where available for details.
