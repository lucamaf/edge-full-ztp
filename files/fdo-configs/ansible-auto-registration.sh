#!/bin/bash
conn_name=$(nmcli con show | grep -v UUID | head -n 1 | awk '{print $1}')
IP_ADDRESS=$(nmcli conn show $conn_name | grep ip_address | awk '{print $4}')

#MAC_ADDRESS=\$(ip addr | grep wlp -A 1 | grep link | awk '{print \$2}' | sed 's/://g')
MAC_ADDRESS=$(ip addr | grep $conn_name -A 1 | grep link | awk '{print $2}' | sed 's/://g')


if [ -z "$IP_ADDRESS" ] || [ -z "$MAC_ADDRESS" ] ; then
    echo "One or more required variables are empty. Script failed."
    exit 1
fi

JSON="{\
\"ip_address\": \"$IP_ADDRESS\", \
\"mac_address\": \"$MAC_ADDRESS\" \
}"

/usr/bin/curl -H 'Content-Type: application/json' --data "$JSON" http://eda.<ANSIBLE_HOST>/endpoint

