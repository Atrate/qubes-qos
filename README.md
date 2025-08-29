# Qubes QoS

[![License: AGPL v3](https://img.shields.io/badge/License-AGPLv3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0.en.html) 

## Description

This script is designed for QubesOS. It allows the user to "easily" prioritise
the network traffic of certain VMs. It works by setting the
[DSCP](https://en.wikipedia.org/wiki/Differentiated_services) code point for
outgoing traffic in a VM and processing it in ProxyVMs. VMs with a more critical
traffic class have their traffic handled first, then VMs with a lower class. The
script allows for 5 traffic classes by default, but this could be changed
without much effort. The `tc` script takes care of prioritisation, while the
`mangle` script tags VMs' traffic with the correct DSCP field based on the
`vm-config.dscp` feature.

## Usage

1. Download all the `.sh` and `.service` files from this repo.

2. Copy `qubes-qos-mangle.sh` and `qubes-qos-mangle.service` to the TemplateVMs
   of VMs whose traffic you want to (de-)prioritise. The `.sh` file should go to
   `/usr/bin/`, the `.service` file should go to `/etc/systemd/system`.

3. Make sure `/usr/bin/qubes-qos-mangle.sh` is executable (`sudo chmod +x
   /usr/bin/qubes-qos-mangle.sh`).

4. Enable the service in the TemplateVMs (`sudo systemctl daemon-reload; sudo
   systemctl enable qubes-qos-mangle`)

5. Copy `qubes-qos-tc.sh` and `qubes-qos-tc.service` to the TemplateVMs of your
   ProxyVMs (so of `sys-firewall`, etc.). (This can also just be all
   TemplateVMs, as the script will exit if it's not running inside a ProxyVM). The
   `.sh` file should go to `/usr/bin/`, the `.service` file should go to
   `/etc/systemd/system`.

6. Make sure `/usr/bin/qubes-qos-tc.sh` is executable (`sudo chmod +x
   /usr/bin/qubes-qos-tc.sh`).

7. Enable the service in the TemplateVMs (`sudo systemctl daemon-reload; sudo
   systemctl enable qubes-qos-tc`)

8. Apply priorities to VMs. For each VM you want to change the traffic priority
   of, execute this in `dom0`: `qvm-features VMNAME vm-config.dscp CLASS`. 

CLASS can be one of:

- `ef`

- `cs5`

- `cs0`

- `cs2`

- `cs1`

The `ef` class is the highest priority, the `cs1` class is the lowest priority.
The `cs0` class is also the default one, so you don't really need to set it on
VMs explicitly. You'll most probably want `ef` or `cs5` for real-time
audio/video conversations and `cs1` for very background tasks, like non-priority
file sync.

## Limitations

The DSCP field gets reset when it passes through a VPN qube. This can be worked
around in the following ways:

1. Use the OpenVPN `passtos` option to preserve the field

2. Perform some `nftables` black magic to achieve the same for Wireguard

3. Prioritise the traffic of the *whole* VPN qube as well as inside. The traffic
   entering the qube will get handled by the `tc` script, and the traffic
   leaving the qube will have a static DSCP value set by the `mangle` script.

## Other Utilities

See [the qubes-utils repo](https://github.com/Atrate/qubes-utils) for links to other utilities I've written for Qubes.

## License

This project is licensed under the [AGPL-3.0-or-later](https://www.gnu.org/licenses/agpl-3.0.html).

[![License: AGPLv3](https://www.gnu.org/graphics/agplv3-with-text-162x68.png)](https://www.gnu.org/licenses/agpl-3.0.html)
