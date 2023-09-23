#!/bin/bash

sudo echo ""

# Message with the requirements
cat << EOF
There are some requirements:
  1. Be on the same network as the devices
  2. The following packages are needed:
    - nmap
    - ssh
    - sshpass
EOF

# Get the IP of the device that runs the script
RSDEVICE=$(ip a | grep -P '\binet\b' | tr -s '\s+' ' ' | cut -d ' ' -f 3 | grep -P '^10|^172|^192' | cut -d. -f1-3 | sort -u)

# Loop through the IPs we found before
for IP in $RSDEVICE; do
    # nmap the network to find the Ubiquity devices
    echo -e "\nScanning $IP.0/24 for Ubiquity devices..."
    # Save the IPs of the ubiquiti devices in a variable
    UBIQUITI=$(sudo nmap -sn $IP.0/24 | grep -B 2 "Ubiquiti" | grep -oP "\d+\.\d+\.\d+\.\d+")
    echo "Scan complete, the devices found are:"
    echo -e $UBIQUITI | tr ' ' '\n' | tee ubiquiti_devices
done


# Enter the IP of the controller
echo -e "\n\nEnter the IP of the controller:"
read CONTROLLER
echo -e "The controller IP is $CONTROLLER\n"

# Loop through the Ubiquiti devices we found before
for IP in $(cat ubiquiti_devices); do
    # Adopt the device
    echo "Connecting to $IP..."
    sudo sshpass -p "ubnt" ssh -o StrictHostKeyChecking=no ubnt@$IP set-inform "http://$CONTROLER:8080/inform"
done

# Remove the file we created before
rm ubiquiti_devices
