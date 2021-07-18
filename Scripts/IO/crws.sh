#!/bin/bash
# Script to collect the read / write speeds

# Check if our folders exists if not creates them
DIRR="/var/log/IORead"
DIRW="/var/log/IOWrite"

[ -d "$DIRR" ] || mkdir -p "$DIRR"
[ -d "$DIRW" ] || mkdir -p "$DIRW"

# Create / Empty the iotop logfile
echo "" > /var/log/iotop

# iotop is a tool that provide the total and the current Reads and Writes on the disk
# b Non interactive mode
# o only threads that are doing I/O
# d seconds of delay between the interactions
# K use kilobytes
# qq column names are never printed
# the following argument will provide only the current output and append it at iotop

iotop -boqqk -n 590 -d 0.1 | grep -i Current |grep -iv grep >> /var/log/iotop

# The next 2 commands are going to break the iotop file in IORead & IOWrite

cat /var/log/iotop | cut -c 19-28 | sort -ur | head -n 10 | grep '[0-9][0-9][0-9][0-9]\.' > "$DIRR"/$(date +"%H:%M")
cat /var/log/iotop | cut -c 56-65 | sort -ur | head -n 10 | grep '[0-9][0-9][0-9][0-9]\.' > "$DIRW"/$(date +"%H:%M")

# the following command will compress the IORead & IOWrite every day at midnight

if [[$(date +"%H%M") == '0000']]
then
        tar -zcvf $(date +"%D%M").tar.gz "$DIRR"
        tar -zcvf $(date +"%D%M").tar.gz "$DIRW"
fi
