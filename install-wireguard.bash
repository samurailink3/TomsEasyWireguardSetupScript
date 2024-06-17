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

# Ask the user for the public IP address. If you are using this
# script in further automation, you can set this variable beforehand.
if [ -z $ENDPOINT_IP ]; then
    read -p "What is the public IP address of your server? " ENDPOINT_IP
fi

# Create server keypair
if [ ! -f /etc/wireguard/server.priv ]; then
    wg genkey | tee /etc/wireguard/server.priv | wg pubkey > /etc/wireguard/server.pub
fi
SERVER_PRIVATE_KEY=$(< /etc/wireguard/server.priv)
SERVER_PUBLIC_KEY=$(< /etc/wireguard/server.pub)

# Create wireguard config file
if [ ! -f /etc/wireguard/wg0.conf ]; then
    cat << EOF > /etc/wireguard/wg0.conf
[Interface]
PrivateKey = $SERVER_PRIVATE_KEY
Address = 10.11.12.1/24
ListenPort = 51820

#Allow forwarding of ports
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE; ip6tables -A FORWARD -i wg0 -j ACCEPT; ip6tables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE; ip6tables -D FORWARD -i wg0 -j ACCEPT; ip6tables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

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
    if [ ! -f /etc/wireguard/client_$i.priv ]; then
        # Create a client keypair
        wg genkey | tee /etc/wireguard/client_$i.priv | wg pubkey > /etc/wireguard/client_$i.pub
    fi
    CLIENT_PRIVATE_KEY=$(< /etc/wireguard/client_$i.priv)
    CLIENT_PUBLIC_KEY=$(< /etc/wireguard/client_$i.pub)

    # Add the peer information to the server config file
    if ! grep -q "# Client $i" /etc/wireguard/wg0.conf; then
        echo "# Client $i" >> /etc/wireguard/wg0.conf
        echo "[Peer]" >> /etc/wireguard/wg0.conf
        echo "PublicKey = $CLIENT_PUBLIC_KEY" >> /etc/wireguard/wg0.conf
        echo "AllowedIPs = 10.11.12.$(($i+1))/32" >> /etc/wireguard/wg0.conf
        echo "" >> /etc/wireguard/wg0.conf
    fi

    # Create wireguard config for client
    if [ ! -f /etc/wireguard/client_$i.conf ]; then
        echo "[Interface]" >> /etc/wireguard/client_$i.conf
        echo "PrivateKey = $CLIENT_PRIVATE_KEY" >> /etc/wireguard/client_$i.conf
        echo "Address = 10.11.12.$(($i+1))/32" >> /etc/wireguard/client_$i.conf
        echo "" >> /etc/wireguard/client_$i.conf
        echo "[Peer]" >> /etc/wireguard/client_$i.conf
        echo "PublicKey = $SERVER_PUBLIC_KEY" >> /etc/wireguard/client_$i.conf
        echo "AllowedIPs = 10.11.12.0/24" >> /etc/wireguard/client_$i.conf
        echo "Endpoint = $ENDPOINT_IP:51820" >> /etc/wireguard/client_$i.conf
        echo "PersistentKeepalive = 15" >> /etc/wireguard/client_$i.conf
        echo "" >> /etc/wireguard/client_$i.conf
    fi
done

# Enable IP forwarding for running system
echo 1 > /proc/sys/net/ipv4/ip_forward
# Enable IP forwarding on startup
sysctl -w net.ipv4.ip_forward=1

# Start wireguard service
systemctl start wg-quick@wg0
# Enable wireguard service on startup
systemctl enable wg-quick@wg0

echo "Done! You now have a pile of 'client_x.conf' files in /etc/wireguard now."
