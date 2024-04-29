#!/bin/bash

conn_name=$(nmcli con show | grep -v UUID | head -n 1 | awk '{print $1}')
IP_ADDRESS=$(nmcli conn show $conn_name | grep ip_address | awk '{print $4}')

MAC_ADDRESS=$(ip addr | grep $conn_name -A 1 | grep link | awk '{print $2}' | sed 's/://g')

if [ $(hostname --short) == "localhost" ]
then
this_hostname=$MAC_ADDRESS


hostnamectl set-hostname edge-${this_hostname}
hostnamectl --pretty set-hostname edge-${this_hostname}




cat <<EOF > /etc/hosts
127.0.0.1   edge-${this_hostname} localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         edge-${this_hostname} localhost localhost.localdomain localhost6 localhost6.localdomain6
EOF

fi