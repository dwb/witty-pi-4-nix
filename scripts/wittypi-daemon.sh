#!@bash@/bin/bash
# Witty Pi daemon: syncs time, applies the schedule and waits for shutdown.
set -eu
home="${WITTYPI_HOME:-/var/lib/wittypi}"
@out@/bin/wittypi-setup-home "$home"
exec @bash@/bin/bash "$home/daemon.sh" "$@"
