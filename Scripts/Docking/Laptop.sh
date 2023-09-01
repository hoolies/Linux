#!/bin/sh
xrandr --output eDP-1 --primary --mode 1920x1080 --pos 0x0 --rotate normal --output DP-1 --off --output HDMI-1 --off --output DP-2 --off --output HDMI-2 --off --output DP-1-1 --off --output DP-1-2 --off --output DP-1-3 --off

# Kill conky and nitrogen
pkill conky && pkill nitrogen

# Restart conky and nitrogen
nitrogen --restore && conky -c ~/.config/conky/conky.config 2> /dev/null
