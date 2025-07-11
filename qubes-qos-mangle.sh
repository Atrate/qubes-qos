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
# This script grabs the DSCP value from vm-config.dscp and sets it for all
# outgoing packets in the VM. Prioritisation happens later, e.g. with the
# qubes-qos-tc.sh script (or other methods, as DSCP is standardised).
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
    'getopt'
    'hash'
    'local'
    'logger'
    'nft'
    'pgrep'
    'qubesdb-read'
    'read'
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
# The restricted mode option necessitates the usage of tee
# instead of simple output redirection when writing to files
# ------------------------------------------------------------------------------
set -o pipefail -eEur

## -----------------------------------------------------------------------------
## END OF SECURITY SECTION
## Make sure to populate the $UTILS array above
## -----------------------------------------------------------------------------

# Speed up script by not using unicode
# ------------------------------------
export LC_ALL=C
export LANG=C


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

    return
}


# Main program functionality
# --------------------------
main()
{
    # Grab DSCP value from vm-config.dscp and set it for outbound packets
    # -------------------------------------------------------------------
    if dscp="$(qubesdb-read /vm-config/dscp | grep '^[[:alnum:]]\{1,\}')"
    then
        nft add table ip mangle
        nft add chain ip mangle output '{ type filter hook output priority mangle; }'
        nft add rule  ip mangle output ip dscp set "$dscp"
        inform "DSCP detected and set to: $dscp"
    else
        inform "No vm-config.dscp value set, exiting!"
    fi
    return
}


check_environment
main

## END OF FILE #################################################################
# vim: set tabstop=4 softtabstop=4 expandtab shiftwidth=4 smarttab:
# End:
