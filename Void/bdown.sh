#!/bin/bash

echo $(expr $(cat /sys/class/backlight/intel_backlight/brightness) - 50) > /sys/class/backlight/intel_backlight/brightness
