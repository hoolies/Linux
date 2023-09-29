#!/bin/bash

echo $(expr 50 + $(cat /sys/class/backlight/intel_backlight/brightness)) > /sys/class/backlight/intel_backlight/brightness
