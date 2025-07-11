#!/bin/bash --posix

# ------------------------------------------------------------------------------
# Copyright (C) 2025 Atrate
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
# ------------------------------------------------------------------------------


# ------------------------------------------------------------------------------
# This script installs a 5-band fq_codel leaf queue based on the DSCP field in
# IP packets. Meant to be used in combination with the qubes-qos-mangle.sh
# script, but it could also come in handy as a standalone script. Enable via the
# provided systemd service, it will only execute on ProxyVMs. The interface is
# automatically picked to be the first interface that does not match the filter
# "lo|vif*|eth*". This is done to make the service work with VPNs. If there are
# no interfaces like that, it defaults to "eth0". Interface detection relies on
# nmcli, so you need to have your VPN managed by NetworkManager.
# --------------------
# Version: 0.1.0
# --------------------
# Exit code listing:
#   0: All good
#   1: Unspecified
#   2: Error in environment configuration or arguments
# ------------------------------------------------------------------------------

## -----------------------------------------------------------------------------
## SECURITY SECTION
## NO EXECUTABLE CODE CAN BE PRESENT BEFORE THIS SECTION
## -----------------------------------------------------------------------------

# Set POSIX-compliant mode for security and unset possible overrides
# NOTE: This does not mean that we are restricted to POSIX-only constructs
# ------------------------------------------------------------------------
POSIXLY_CORRECT=1
set -o posix
readonly POSIXLY_CORRECT
export POSIXLY_CORRECT

# Set IFS explicitly. POSIX does not enforce whether IFS should be inherited
# from the environment, so it's safer to set it expliticly
# --------------------------------------------------------------------------
IFS=$' \t\n'
export IFS

# ------------------------------------------------------------------------------
# For additional security, you may want to specify hard-coded values for:
#   SHELL, PATH, HISTFILE, ENV, BASH_ENV
# They will be made read-only by set -r later in the script.
# ------------------------------------------------------------------------------

# Populate this array with **all** commands used in the script for security.
# The following builtins do not need to be included, POSIX mode handles that:
# break : . continue eval exec exit export readonly return set shift trap unset
# The following keywords are also supposed not to be overridable in bash itself
# ! case  coproc  do done elif else esac fi for function if in
# select then until while { } time [[ ]]
# ------------------------------------------------------------------------------
UTILS=(
    '['
    '[['
    'awk'
    'cat'
    'command'
    'declare'
    'echo'
    'false'
    'hash'
    'local'
    'logger'
    'modprobe'
    'nmcli'
    'pgrep'
    'qubesdb-read'
    'read'
    'tc'
    'tee'
    'true'
)

# Unset all commands used in the script - prevents exported functions
# from overriding them, leading to unexpected behavior
# -------------------------------------------------------------------
for util in "${UTILS[@]}"
do
    \unset -f -- "$util"
done

# Clear the command hash table
# ----------------------------
hash -r

# Set up fd 3 for discarding output, necessary for set -r
# -------------------------------------------------------
exec 3>/dev/null

# ------------------------------------------------------------------------------
# Options description:
#   -o pipefail: exit on error in any part of pipeline
#   -eE:         exit on any error, go through error handler
#   -u:          exit on accessing uninitialized variable
#   -r:          set bash restricted mode for security
#   -p:          set bash privileged mode for security
# The restricted mode option necessitates the usage of tee
# instead of simple output redirection when writing to files
# ------------------------------------------------------------------------------
set -o pipefail -eEupr

## -----------------------------------------------------------------------------
## END OF SECURITY SECTION
## Make sure to populate the $UTILS array above
## -----------------------------------------------------------------------------

# Speed up script by not using unicode
# ------------------------------------
export LC_ALL=C
export LANG=C

# Uplink interface (usually towards sys-net)
# ------------------------------------------
IFACE="eth0"


# Print to stderr and user.info
# -----------------------------
inform()
{
    printf '%s\n' "$@" >&2
    logger --priority user.info --tag -- "$@" || true
}


# Print to stderr and user.warn
# -----------------------------
warn()
{
    printf '%s\n' "$@" >&2
    logger --priority user.warning --tag -- "$@" || true
}


# Print to stderr and user.err
# ----------------------------
err()
{
    printf '%s\n' "$@" >&2
    logger --priority user.err --tag -- "$@" || true
}


# Simple yes/no prompt
# --------------------
yes_or_no()
{
    while true
    do
        read -r -p "$* [y/n]: " yn
        case $yn in
            [Yy]*) return 0  ;;
            [Nn]*) err "Aborted" ; return 1 ;;
        esac
    done
}


# Check the environment the script is running in
# ----------------------------------------------
check_environment()
{
    # Check whether running as root
    # -----------------------------
    if (( EUID != 0 ))
    then
        err "This script must be executed as root!"
        exit 3
    fi

    # Check available utilities
    # -------------------------
    for util in "${UTILS[@]}"
    do
        command -v -- "$util" >&3 || { err "This script requires $util to be installed and in PATH!"; exit 2; }
    done

    # Check whether running in a ProxyVM
    # ----------------------------------
    if ! qubesdb-read /qubes-vm-type | grep '^ProxyVM$'
    then
        inform "Not running in a ProxyVM, exiting!"
        exit 0
    fi

    return
}


# Main program functionality
# --------------------------
main()
{
    # Set interface as the first found non-eth non-lo non-vif interface,
    # otherwise keep it as eth0 (workaround for VPN issues)
    # ------------------------------------------------------------------
    if int="$(nmcli dev | cut -d' ' -f1 | grep -vE '^vif|^lo$|^DEVICE$|^eth0$')"
    then
        IFACE="$int"
    fi
    inform "Detected upstream interface: $IFACE"

    # Modprobe modules, just in case
    # ------------------------------
    modprobe sch_prio sch_fq_codel cls_u32

    # Delete existing prio mappings
    # -----------------------------
    tc qdisc del dev "$IFACE" root 2>&3 || true

    # Priority bands
    # --------------
    tc qdisc add dev "$IFACE" root handle 1: prio bands 5 \
           priomap 2 4 3 3 1 1 0 0 2 2 2 2 2 2 2 2

    # Leaf queues (highest to lowest)
    # -------------------------------
    tc qdisc add dev "$IFACE" parent 1:1 handle 10: fq_codel   # band 0 - highest
    tc qdisc add dev "$IFACE" parent 1:2 handle 20: fq_codel   # band 1 - high
    tc qdisc add dev "$IFACE" parent 1:3 handle 30: fq_codel   # band 2 - default
    tc qdisc add dev "$IFACE" parent 1:4 handle 40: fq_codel   # band 3 - low
    tc qdisc add dev "$IFACE" parent 1:5 handle 50: fq_codel   # band 4 - lowest

    # DS Field (mask 0xFC strips the two ECN bits)
    # --------------------------------------------
    tc filter add dev "$IFACE" protocol ip parent 1:0 prio 1 u32 \
            match ip dsfield 0xB8 0xFC flowid 1:1      # EF
    tc filter add dev "$IFACE" protocol ip parent 1:0 prio 2 u32 \
            match ip dsfield 0xA0 0xFC flowid 1:2      # CS5
    # (CS0 / untagged traffic falls through -> band 2)
    tc filter add dev "$IFACE" protocol ip parent 1:0 prio 3 u32 \
            match ip dsfield 0x40 0xFC flowid 1:4      # CS2
    tc filter add dev "$IFACE" protocol ip parent 1:0 prio 4 u32 \
            match ip dsfield 0x20 0xFC flowid 1:5      # CS1

    inform "5-band QoS ready on $IFACE (EF>CS5>default>CS2>CS1)"
    return
}


check_environment
main


## END OF FILE #################################################################
# vim: set tabstop=4 softtabstop=4 expandtab shiftwidth=4 smarttab:
# End:
