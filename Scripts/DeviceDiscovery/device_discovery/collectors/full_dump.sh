collect_full_dev() {
    print_section "/DEV DIRECTORY - ALL DEVICE NODES"
    require_binary find
    require_binary ls
    require_binary awk
    find /dev -mindepth 1 -maxdepth 1 -exec ls -ld {} + 2>/dev/null | awk '
BEGIN { char = 0; block = 0; link = 0; other = 0 }
/^c/ { char++ }
/^b/ { block++ }
/^l/ { link++ }
/^[^cbl-]/ { other++ }
END {
    print "  Character:", char, " Block:", block, " Links:", link, " Other:", other
}'
    print_block ""
    list_dir_long /dev/bus/usb 25
    run_sh_checked 'ls -l /dev/ttyS* /dev/ttyUSB* /dev/ttyACM* 2>/dev/null' ls
    list_dir_long /dev/net 0
    run_sh_checked 'ls -l /dev/sd* /dev/nvme* 2>/dev/null | head -n 20' ls head
    list_dir_long /dev/input 30
    list_dir_long /dev/snd 15
    run_sh_checked 'ls -l /dev/video* 2>/dev/null' ls
    list_dir_long /dev/dri 0
    print_block "Total /dev entries: $(count_dir_entries /dev)"
    print_block ""
}

collect_full_sys() {
    print_section "/SYS DIRECTORY - KERNEL DEVICE TREE"
    list_dir_names /sys/bus
    print_block ""
    list_dir_names /sys/class
    print_block ""
    print_block "USB device count: $(count_dir_entries /sys/bus/usb/devices)"
    print_block "PCI device count: $(count_dir_entries /sys/bus/pci/devices)"
    print_block ""
}
