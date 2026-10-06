#!@bash@/bin/bash
# Populate a writable Witty Pi home directory.
#
# The upstream scripts locate their siblings, logs and schedule.wpi relative
# to their own directory, so they are symlinked from the store into a
# writable directory and run from there.
set -eu

share=@share@
home="${1:-${WITTYPI_HOME:-/var/lib/wittypi}}"

mkdir -p "$home"

for f in daemon.sh runScript.sh wittyPi.sh utilities.sh schedules; do
  ln -sfn "$share/$f" "$home/$f"
done

# User hook scripts: seed with the (empty) upstream templates if absent.
for f in afterStartup.sh beforeScript.sh beforeShutdown.sh; do
  if [ -L "$home/$f" ] && [ ! -e "$home/$f" ]; then
    rm "$home/$f"
  fi
  if [ ! -e "$home/$f" ]; then
    install -m 0755 "$share/$f" "$home/$f"
  fi
done

touch "$home/wittyPi.log" "$home/schedule.log"
