#!/bin/bash

brightmod() {

echo "$1" > /sys/class/backlight/intel_backlight/brightness
}

brightness=$(brightmod $1)
