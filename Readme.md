# Tom's Easy Wireguard Setup Script (for Debian-based Systems)

This script will install wireguard, generate configs for a specified number of
clients, and enable IP forwarding for all connected clients. This script is
idempotent, meaning you can run it multiple times without destroying your
existing config. If you need to add another VPN client, just tell the script you
need 4 clients instead of 3, etc.

## Prerequisites

* A Debian-based (Debian/Ubuntu) system with a public IPv4 address
* Root access

## Instructions

* Download this script to your system: `curl https://raw.githubusercontent.com/samurailink3/TomsEasyWireguardSetupScript/main/install-wireguard.bash > install-wireguard.bash`
* Make the script executable: `chmod +x install-wireguard.bash`
* Run the script: `./install-wireguard.bash`

## Automation

If you'd like to use this script in further automation/without user prompting,
you'll need to set the following environment variables:
* `ENDPOINT_IP`
* `NUMBER_OF_CLIENTS`

## Advanced Features

* Set the `WIREGUARD_INTERFACE` variable to set up new/existing Wireguard tunnels.
  * Example: `export WIREGUARD_INTERFACE=wg1 && /bin/bash install-wireguard.bash`
  * Default: `wg0`
  * You can use this to run multiple wireguard tunnels on a single host
* Set the `WIREGUARD_INTERNAL_IP_PARTIAL` variable to control the IP range of the
  network created
  * Example: `export WIREGUARD_INTERNAL_IP_PARTIAL=10.72.72 && /bin/bash install-wireguard.bash`
  * Default: `10.11.12`
  * **Note:** The network address will end in `.0`
  * **Note:** The network defaults to a `/24`
  * **Note:** The server address will end in `.1`
* Set the `WIREGUARD_LISTEN_PORT` variable to control what port wireguard will
  listen for incoming connections on.
  * Example: `export WIREGUARD_LISTEN_PORT=12345 && /bin/bash install-wireguard.bash`
  * Default: `51820`

## License

Public Domain - [The Unlicense](https://unlicense.org/)

You may use this code however you'd like, wherever you'd like, without any
requirements, forever.

## References and Sources

* [The complete guide to setting up a multi-peer WireGuard VPN - Door jeroen](https://www.jeroenbaten.nl/the-complete-guide-to-setting-up-a-multi-peer-wireguard-vpn/)
    * Most of this script wouldn't be possible without the steps listed in this
      article...
* [dddma's firewall post on Reddit](https://www.reddit.com/r/WireGuard/comments/fnqm8h/can_ping_wireguard_clients_but_not_ssh/flb56vk/)
    * ... and specifically this post by `dddma`, without this step, traffic
      cannot be properly forwarded between clients.
