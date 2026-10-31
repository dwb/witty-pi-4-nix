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
- The daemon exits (and the service fails) if the board does not answer on
  I2C after upstream's five retries, instead of carrying on without it. The
  hooks are not run in that case.
- The 1-Wire conflict check looks at whether the halt pin is already claimed
  (`gpioinfo`) instead of grepping `/boot/config.txt` for `dtoverlay=w1-gpio`,
  since NixOS may apply overlays through `hardware.deviceTree` and keeps
  `config.txt` elsewhere, if at all.
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

            # Optional board settings; unset ones are left as they are.
            settings = {
              defaultOn = true;
              lowVoltageThreshold = 11.5;
              recoveryVoltageThreshold = 12.5;
              overTemperature = { action = "shutdown"; threshold = 70; };
            };
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
| `settings.*` | `null` | Board settings; see below. |

The hook options are always managed declaratively; editing the hook files in
`/var/lib/wittypi` by hand has no lasting effect.

### Board settings

`services.wittypi.settings` covers the settings in the `wittypi` menu
(section 7 of the user manual). Each defaults to `null`, which leaves the
board's value alone so it can still be changed with `wittypi`. The board keeps
these in its EEPROM; the `wittypi-settings` service writes the ones that are
set and differ from the board's, at boot and on `nixos-rebuild switch` when
they change. Values set here overwrite changes made with `wittypi` at the next
boot.

| Option | Menu entry | Values |
| --- | --- | --- |
| `defaultOn` | Default state when powered | bool |
| `defaultOnDelay` | Default ON delay | 0–10 s (firmware revision ≥ 2) |
| `powerCutDelay` | Power cut delay after shutdown | 0.0–25.0 s |
| `pulseInterval` | Pulsing interval during sleep | 1–20 s |
| `whiteLedDuration` | White LED duration | 0–254, 0 = off |
| `dummyLoadDuration` | Dummy load duration | 0–254, 0 = off |
| `vinAdjustment` | Vin adjustment | -1.27–1.27 V |
| `voutAdjustment` | Vout adjustment | -1.27–1.27 V |
| `ioutAdjustment` | Iout adjustment | -1.27–1.27 A |
| `lowVoltageThreshold` | Set low voltage threshold | 0 = off, 2.0–25.0 V (L3V7: 3.0–4.2 V) |
| `recoveryVoltageThreshold` | Set recovery voltage threshold | 0 = off, 2.0–25.0 V (not L3V7) |
| `startOnUsbPower` | Set recovery voltage threshold (L3V7) | bool |
| `overTemperature` | Set over temperature action | `{ action = "none" \| "shutdown" \| "startup"; threshold = -30–80; }` (°C) |
| `belowTemperature` | Set below temperature action | as `overTemperature` |

Settings that the board model or firmware does not support (checked from the
firmware ID and revision) make the service fail without writing anything.

Negative adjustments are stored as two's complement, as the firmware reads
them. `wittypi` encodes them off by one (`255 + value` rather than
`256 + value`), so it shows a negative adjustment set here 0.01 too high, and
one set with `wittypi` takes effect 0.01 lower than entered. -0.01 cannot be
set: the firmware treats the byte `0xFF` in EEPROM as unset and restores the default when it
next starts.

### Requirements and caveats

- **I2C bus 1 must be enabled in the device tree.** The module sets
  `hardware.i2c.enable` (loads `i2c-dev`), but the Pi's I2C controller has to
  be enabled separately, e.g. with nixos-hardware
  (`hardware.raspberry-pi."4".i2c1.enable = true;`) or a device tree overlay.
  Verify with `i2cdetect -y 1`; the board answers at `0x08`. The service
  waits for `/dev/i2c-1` to appear (up to systemd's device timeout) before
  starting.
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
