# Device discovery (modular v2.0.0)

Run from the parent directory:

```sh
./device_discovery.sh [options]
./device_discovery.monolithic.sh [options]   # self-contained copy
```

## Layout

| Path | Role |
|------|------|
| `../device_discovery.sh` | Entry point |
| `config.sh` | Globals, CLI, help |
| `load.sh` | Source order |
| `main.sh` | Temp files, orchestration |
| `scan.sh` | Collector run order |
| `emit.sh` | JSON and human reports |
| `lib/common.sh` | `glob_has_dirs` helper |
| `lib/` | paths, sysfs, json, registry, … |
| `collectors/` | One module per bus |
| `tools/build-monolithic.sh` | Regenerate monolithic edition |

## Collectors

`usb`, `serial`, `bluetooth`, `wifi`, `network`, `storage`, `input`, `pci`, `thunderbolt`, `wwan`, `can`, `nfc`, `display`, `audio`, `camera`, `sensor`, `infiniband`, `fibre_channel`, `iscsi`, `power`, `firewire`, `platform`, `i2c`, `spi`, `mtp`, `kernel`, `full_dump`

## Flags

| Flag | Effect |
|------|--------|
| `-v` / `-vv` | Names list / full diagnostics |
| `--json` | JSON only on stdout |
| `--no-prompt` | No sudo prompt |
| `--pci-all` | Include PCI bridges (default: endpoints) |
| `--physical-only` | Drop virtual devices |

## Design notes

- **Stable IDs** from bus + sysfs path (`usb__bus_usb_devices_1-7`)
- **Dedupe** by stable id (same path is not recorded twice)
- **PATH cache** via awk lookup; **driver cache** tab-separated
- Empty sysfs sections are skipped (`glob_has_dirs`)
- Human tables sorted by bus then name

Regenerate monolithic: `sh device_discovery/tools/build-monolithic.sh`
