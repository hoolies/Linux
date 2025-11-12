#!/usr/bin/env bash

# Create a function to check if an entry is a valid IP address
check_ip() {
  local ip=$1
  local stat=1

  if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    OIFS=$IFS
    IFS='.'
    read -r -a ip_array <<<"$ip"
    IFS=$OIFS
    [[ ${ip_array[0]} -le 255 && ${ip_array[1]} -le 255 && ${ip_array[2]} -le 255 && ${ip_array[3]} -le 255 ]]
    stat=$?
  fi
  return $stat
}

# Read IP addresses until user types stop, validating each one
read_ip_addresses() {
  local valid_ips=()
  local line
  
  while IFS= read -r line; do
    # Check if user wants to stop
    if [[ $line == "stop" ]]; then
      break
    fi
    
    # Skip empty lines
    if [[ -z $line ]]; then
      continue
    fi
    
    # Validate the IP address
    if check_ip "$line"; then
      valid_ips+=("$line")
    else
      continue
    fi
  done
  
  # Return the valid IPs (print to stdout for capture)
  printf '%s\n' "${valid_ips[@]}"
}

main() {
  echo "Enter IP addresses (one per line, type 'stop' to finish):"
  # Read valid IP addresses from user
  mapfile -t ip_array < <(read_ip_addresses)
  for ip in "${ip_array[@]}"; do
      pong=$(ping -c 2 -W 2 "$ip" &>/dev/null && echo "$ip UP" || echo "$ip DOWN") && \
      dns=$(dig -x "$ip" +short 2> /dev/null) && \
      if [[ -z $dns ]]; then
        dns="No DNS record found"
      fi
      echo "IP: $pong DNS: $dns"
  done 
}

main
