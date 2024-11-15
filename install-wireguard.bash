#!/bin/bash

# Tom's Easy Wireguard Setup Script (for Debian-based Systems)
#
# This script will install wireguard, generate configs for a specified number of
# clients, and enable IP forwarding for all connected clients. This script is
# idempotent, meaning you can run it multiple times without destroying your
# existing config. If you need to add another VPN client, just tell the script
# you need 4 clients instead of 3, etc.

# Since we're going to be configuring a VPN and setting a bunch of systemd
# service files, we need root.
# ref: https://stackoverflow.com/a/18216122
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

# Install Wireguard
apt update
apt install -y wireguard

# If the user hasn't set the WIREGUARD_INTERFACE variable, assume wg0.
if [ -z $WIREGUARD_INTERFACE ]; then
    export WIREGUARD_INTERFACE=wg0
fi

# If the user hasn't set an IP address, assume default.
if [ -z $WIREGUARD_INTERNAL_IP_PARTIAL ]; then
    export WIREGUARD_INTERNAL_IP_PARTIAL=10.11.12
fi

# If the user hasn't set a listen port, assume default.
if [ -z $WIREGUARD_LISTEN_PORT ]; then
    export WIREGUARD_LISTEN_PORT=51820
fi

# Ask the user for the public IP address. If you are using this
# script in further automation, you can set this variable beforehand.
if [ -z $ENDPOINT_IP ]; then
    read -p "What is the public IP address of your server? " ENDPOINT_IP
fi

# Create the directory to store interface config files
mkdir -p /etc/wireguard/$WIREGUARD_INTERFACE

# Create interface keypair
if [ ! -f /etc/wireguard/$WIREGUARD_INTERFACE/server.priv ]; then
    wg genkey | tee /etc/wireguard/$WIREGUARD_INTERFACE/server.priv | wg pubkey > /etc/wireguard/$WIREGUARD_INTERFACE/server.pub
fi
SERVER_PRIVATE_KEY=$(< /etc/wireguard/$WIREGUARD_INTERFACE/server.priv)
SERVER_PUBLIC_KEY=$(< /etc/wireguard/$WIREGUARD_INTERFACE/server.pub)

# Create wireguard config file
if [ ! -f /etc/wireguard/$WIREGUARD_INTERFACE.conf ]; then
    cat << EOF > /etc/wireguard/$WIREGUARD_INTERFACE.conf
[Interface]
PrivateKey = $SERVER_PRIVATE_KEY
Address = $WIREGUARD_INTERNAL_IP_PARTIAL.1/24
ListenPort = $WIREGUARD_LISTEN_PORT

#Allow forwarding of ports
PostUp = iptables -A FORWARD -i $WIREGUARD_INTERFACE -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE; ip6tables -A FORWARD -i $WIREGUARD_INTERFACE -j ACCEPT; ip6tables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i $WIREGUARD_INTERFACE -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE; ip6tables -D FORWARD -i $WIREGUARD_INTERFACE -j ACCEPT; ip6tables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

EOF
fi

# If the number of clients has not been set, ask the user. If you are using this
# script in further automation, you can set this variable beforehand.
if [ -z $NUMBER_OF_CLIENTS ]; then
    read -p "How many people need a VPN profile (including you)? " NUMBER_OF_CLIENTS
fi

# Make sure the user-provided variable is an integer
# ref: https://stackoverflow.com/a/806923
re='^[0-9]+$'
if ! [[ $NUMBER_OF_CLIENTS =~ $re ]] ; then
   echo "error: you must enter a number" >&2; exit 1
fi

# For each client...
for i in $(seq 1 $NUMBER_OF_CLIENTS); do
    if [ ! -f /etc/wireguard/$WIREGUARD_INTERFACE/client_$i.priv ]; then
        # Create a client keypair
        wg genkey | tee /etc/wireguard/$WIREGUARD_INTERFACE/client_$i.priv | wg pubkey > /etc/wireguard/$WIREGUARD_INTERFACE/client_$i.pub
    fi
    CLIENT_PRIVATE_KEY=$(< /etc/wireguard/$WIREGUARD_INTERFACE/client_$i.priv)
    CLIENT_PUBLIC_KEY=$(< /etc/wireguard/$WIREGUARD_INTERFACE/client_$i.pub)

    # Add the peer information to the server config file
    if ! grep -q "# Client $i" /etc/wireguard/$WIREGUARD_INTERFACE.conf; then
        echo "# Client $i" >> /etc/wireguard/$WIREGUARD_INTERFACE.conf
        echo "[Peer]" >> /etc/wireguard/$WIREGUARD_INTERFACE.conf
        echo "PublicKey = $CLIENT_PUBLIC_KEY" >> /etc/wireguard/$WIREGUARD_INTERFACE.conf
        echo "AllowedIPs = $WIREGUARD_INTERNAL_IP_PARTIAL.$(($i+1))/32" >> /etc/wireguard/$WIREGUARD_INTERFACE.conf
        echo "" >> /etc/wireguard/$WIREGUARD_INTERFACE.conf
    fi

    # Create wireguard config for client
    if [ ! -f /etc/wireguard/$WIREGUARD_INTERFACE/client_$i.conf ]; then
        echo "[Interface]" >> /etc/wireguard/$WIREGUARD_INTERFACE/client_$i.conf
        echo "PrivateKey = $CLIENT_PRIVATE_KEY" >> /etc/wireguard/$WIREGUARD_INTERFACE/client_$i.conf
        echo "Address = $WIREGUARD_INTERNAL_IP_PARTIAL.$(($i+1))/32" >> /etc/wireguard/$WIREGUARD_INTERFACE/client_$i.conf
        echo "" >> /etc/wireguard/$WIREGUARD_INTERFACE/client_$i.conf
        echo "[Peer]" >> /etc/wireguard/$WIREGUARD_INTERFACE/client_$i.conf
        echo "PublicKey = $SERVER_PUBLIC_KEY" >> /etc/wireguard/$WIREGUARD_INTERFACE/client_$i.conf
        echo "AllowedIPs = $WIREGUARD_INTERNAL_IP_PARTIAL.0/24" >> /etc/wireguard/$WIREGUARD_INTERFACE/client_$i.conf
        echo "Endpoint = $ENDPOINT_IP:$WIREGUARD_LISTEN_PORT" >> /etc/wireguard/$WIREGUARD_INTERFACE/client_$i.conf
        echo "PersistentKeepalive = 15" >> /etc/wireguard/$WIREGUARD_INTERFACE/client_$i.conf
        echo "" >> /etc/wireguard/$WIREGUARD_INTERFACE/client_$i.conf
    fi
done

# Enable IP forwarding for running system
echo 1 > /proc/sys/net/ipv4/ip_forward
# Enable IP forwarding on startup
sysctl -w net.ipv4.ip_forward=1

# Start wireguard service
systemctl start wg-quick@$WIREGUARD_INTERFACE
# Enable wireguard service on startup
systemctl enable wg-quick@$WIREGUARD_INTERFACE

echo "Done! You now have a pile of 'client_x.conf' files in /etc/wireguard/$WIREGUARD_INTERFACE now."
