#!@bash@/bin/bash
# Interactive Witty Pi configuration tool.
set -eu
home="${WITTYPI_HOME:-/var/lib/wittypi}"
@out@/bin/wittypi-setup-home "$home"
exec @bash@/bin/bash "$home/wittyPi.sh" "$@"
