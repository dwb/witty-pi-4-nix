# witty-pi-4-nix

Nix flake packaging the client software for the
[UUGear Witty Pi 4](https://github.com/uugear/Witty-Pi-4) (RTC and power
management HAT for the Raspberry Pi), with a NixOS module for the daemon.

## Outputs

- `packages.<system>.wittypi4` (also `default`)
  - `wittypi`: the interactive configuration tool (`wittyPi.sh`)
  - `wittypi-daemon`: the boot daemon (`daemon.sh`)
  - `wittypi-setup-home`: prepares the writable home directory (used by both)
- `overlays.default`: adds `pkgs.wittypi4`
- `nixosModules.wittypi` (also `default`): `services.wittypi`

## How it works

The upstream scripts read `schedule.wpi` from next to themselves,
and run user hooks (`beforeScript.sh`, `afterStartup.sh`, `beforeShutdown.sh`)
from the same directory. The scripts are therefore symlinked from the store
into a writable home, `$WITTYPI_HOME` (default `/var/lib/wittypi`), and run
from there.

Changes to the upstream scripts:

- Runtime dependencies (`i2c-tools`, `libgpiod`, coreutils, etc.) are put on
  `PATH`.
- GPIO access uses libgpiod instead of WiringPi's `gpio`, which refuses to
  run unless it can identify the board from the Raspberry Pi kernel or the
  firmware-provided device tree (not the case with e.g. a mainline kernel and
  U-Boot). The header's GPIO chip is found by its label (`pinctrl-bcm2835`,
  `pinctrl-bcm2711` or `pinctrl-rp1`); if `gpiodetect` shows another, set
  `WITTYPI_GPIO_CHIP`, e.g.
  `systemd.services.wittypi.environment.WITTYPI_GPIO_CHIP = "gpiochip0";`.
- The daemon exits instead of shutting down if waiting for the shutdown
  signal fails.
- `LC_ALL` is `C.UTF-8` instead of `en_GB.UTF-8`, which is usually not built
  on NixOS.
- `sudo` is removed (both tools must run as root anyway).
- Logging goes to syslog/journald with the identifier `wittypi`
  (`journalctl -t wittypi`) instead of the unrotated `wittyPi.log` and
  `schedule.log`. User hook output goes to the service's journal as well.
  Upstream's timestamp prefix is dropped in favour of the journal's.
- `lsb_release` and `dpkg` calls are replaced.

## NixOS usage

```nix
{
  inputs.witty-pi-4.url = "github:dwb/witty-pi-4-nix";

  outputs = { nixpkgs, witty-pi-4, ... }: {
    nixosConfigurations.pi = nixpkgs.lib.nixosSystem {
      modules = [
        witty-pi-4.nixosModules.default
        ({ pkgs, ... }: {
          services.wittypi = {
            enable = true;

            # Optional. When null (default), choose a schedule with `sudo wittypi`.
            schedule = ''
              BEGIN 2024-01-01 00:00:00
              END   2035-12-31 23:59:59
              ON    M5
              OFF   M15
            '';

            beforeShutdown = ''
              ${pkgs.systemd}/bin/systemctl stop my-app.service
            '';
          };
        })
      ];
    };
  };
}
```

Options:

| Option | Default | Description |
| --- | --- | --- |
| `enable` | `false` | Run the daemon at boot and install the `wittypi` tool. |
| `package` | this flake's `wittypi4` | Package to use. |
| `schedule` | `null` | Contents of `schedule.wpi`. `null` leaves it mutable. |
| `beforeScript` | `""` | Commands run after boot, before the schedule is applied. |
| `afterStartup` | `""` | Commands run after boot, once the schedule is applied. |
| `beforeShutdown` | `""` | Commands run before the board-requested shutdown. |

The hook options are always managed declaratively; editing the hook files in
`/var/lib/wittypi` by hand has no lasting effect.

### Requirements and caveats

- **I2C bus 1 must be enabled in the device tree.** The module sets
  `hardware.i2c.enable` (loads `i2c-dev`), but the Pi's I2C controller has to
  be enabled separately, e.g. with nixos-hardware
  (`hardware.raspberry-pi."4".i2c1.enable = true;`) or a device tree overlay.
  Verify with `i2cdetect -y 1`; the board answers at `0x08`.
- GPIO-4 (halt) and GPIO-17 (SYS_UP) are used by the board; do not enable the
  1-Wire overlay on GPIO-4.
- When the RTC has a valid time, the daemon copies it to the system clock.
  Upstream also disables NTP with `timedatectl set-ntp 0`; that is dropped
  here, since it cannot change units on NixOS. `systemd-timesyncd` stays
  under NixOS control and corrects the system clock when the network is up;
  set `services.timesyncd.enable = false;` to make the RTC the only time
  source. The RTC itself is only updated through `wittypi` → "Synchronize
  with network time".
- The service is not restarted by `nixos-rebuild switch`, since it performs
  one-off boot work (time sync, scheduling, the SYS_UP signal). New versions
  take effect at the next boot.
- When the board signals a shutdown, the daemon runs `shutdown -h now`.
  Create `/boot/wittypi.lock` to suppress this once (upstream behaviour).

## Standalone usage

```sh
nix run github:dwb/witty-pi-4-nix          # interactive tool, as root
WITTYPI_HOME=/some/dir wittypi-daemon       # daemon, with a custom home
```

## Updating

Bump `rev`, `hash` and `version` in `package.nix`. Upstream's install script
downloads `https://www.uugear.com/repo/WittyPi4/LATEST`; at the pinned
revision that archive is identical to `Software/wittypi` in the git repo.
