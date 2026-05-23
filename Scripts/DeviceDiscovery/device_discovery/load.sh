# Source all modules (requires DD_ROOT).

_dd_lib() {
    # shellcheck disable=SC1090
    . "$DD_ROOT/lib/$1"
}

_dd_collector() {
    # shellcheck disable=SC1090
    . "$DD_ROOT/collectors/$1"
}

# shellcheck disable=SC1090
. "$DD_ROOT/config.sh"

_dd_lib output.sh
_dd_lib common.sh
_dd_lib json.sh
_dd_lib paths.sh
_dd_lib sysfs.sh
_dd_lib network.sh
_dd_lib registry.sh
_dd_lib privileges.sh
_dd_lib fs.sh
_dd_lib temp.sh

_dd_collector usb.sh
_dd_collector serial.sh
_dd_collector bluetooth.sh
_dd_collector wifi.sh
_dd_collector network.sh
_dd_collector storage.sh
_dd_collector input.sh
_dd_collector pci.sh
_dd_collector thunderbolt.sh
_dd_collector wwan.sh
_dd_collector can.sh
_dd_collector nfc.sh
_dd_collector display.sh
_dd_collector audio.sh
_dd_collector camera.sh
_dd_collector sensor.sh
_dd_collector infiniband.sh
_dd_collector fibre_channel.sh
_dd_collector iscsi.sh
_dd_collector power.sh
_dd_collector firewire.sh
_dd_collector platform.sh
_dd_collector i2c.sh
_dd_collector spi.sh
_dd_collector mtp.sh
_dd_collector kernel.sh
_dd_collector full_dump.sh

# shellcheck disable=SC1090
. "$DD_ROOT/emit.sh"
# shellcheck disable=SC1090
. "$DD_ROOT/scan.sh"
# shellcheck disable=SC1090
. "$DD_ROOT/main.sh"
