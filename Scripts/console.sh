#!/bin/env bash

# Function to display usage
show_usage() {
    printf "\nUsage:\n"
    printf "  ./console.sh <device> <port speed> <stop bits> <parity>\n\n"
    printf "Parameters:\n"
    printf "  device      - Serial device (e.g., /dev/ttyS0)\n"
    printf "  port speed  - Baud rate (e.g., 9600)\n"
    printf "  stop bits   - Number of stop bits: 1 or 2\n"
    printf "  parity      - Parity type: even or odd\n\n"
    printf "Example:\n"
    printf "  ./console.sh /dev/ttyS0 9600 1 even\n\n"
}

# Check for --help flag
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    show_usage
    exit 0
fi

# Check if all required parameters are provided
if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
    printf "\nError: All parameters are required.\n"
    show_usage
    exit 1
fi

# Validate stop bits parameter
case "$3" in
    1) stopb="-cstopb";;
    2) stopb="cstopb";;
    *) 
        printf "\nError: Invalid stop bits value '$3'. Must be 1 or 2.\n"
        show_usage
        exit 1
        ;;
esac

# Validate parity parameter
if [ "$4" = "even" ]; then
    par="-parodd"
elif [ "$4" = "odd" ]; then
    par="parodd"
else
    printf "\nError: Invalid parity value '$4'. Must be 'even' or 'odd'.\n"
    show_usage
    exit 1
fi

printf "\nThen stty -F $1 $2 $stopb $par\n"

# Set up device
stty -F "$1" "$2" "$stopb" "$par" -icrnl

# Check if error ocurred
if [ "$?" -ne 0 ]; then
    printf "\n\nError ocurred, stty exited $?\n\n"
    exit 1;
fi

# Let cat read the device $1 in the background
cat -v "$1" &

# Capture PID of background process so it is possible to terminate it when done
bgPid="$!"

# Read commands from user, send them to device $1
while [ "$cmd" != "exit" ]
do
   read cmd
   echo -e "\x08$cmd\x0D" > "$1" #strip off the \n that read puts and adds \r for windows like LF

done

# Terminate background read process
kill "$bgPid"
