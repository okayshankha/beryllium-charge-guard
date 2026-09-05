# Beryllium Charge Guard

An ICL-based charging guard for postmarketOS and Qualcomm power-supply
interfaces. It limits USB input current according to battery capacity instead
of toggling charging on and off.

This repository is a fork of
[laxdog/qcom-battery](https://github.com/laxdog/qcom-battery), adapted for the
Xiaomi Poco F1 (codename: beryllium).

## Poco F1 support

The Poco F1 configuration tested by this project uses:

- Snapdragon 845 / SDM845
- Qualcomm PMI8998 charger
- `qcom_smbx` / SMB2 charger driver
- Charger power supply: `/sys/class/power_supply/pmi8998-charger/`
- Writable input-current property: `current_max`

The guard supports both common Qualcomm property names:

- `input_current_limit`
- `current_max`

For the Poco F1, `current_max` is expressed in microamps and uses 25,000-uA
steps. The guard does not modify battery charge current, battery voltage, or
the charger's `online` property.

## How it works

The systemd timer runs the guard periodically. With the default configuration:

- At 65% or above, it sets the input limit to 100 mA by default.
- At 35% or below, it restores the normal input limit saved at boot.
- Between 35% and 65%, it keeps the current mode to avoid rapid switching.
- While the charger is offline, it skips the update.

The low limit is intended to prevent net battery charging during normal phone
use. It is not a hardware charge-disable control; the battery may still charge
slowly if the phone consumes less power than the configured low limit.

## Included files

- `charge_icl_guard.sh` - capacity-based input-current guard.
- `battinfo.sh` - battery and charger status display.
- `icl-menu.sh` - interactive manual ICL control.
- `charge_monitor.sh` - repeated battery and charger current monitor.
- `fix-line-endings.sh` - converts copied Windows CRLF files to Unix LF.
- `charge-icl-guard.service` - oneshot systemd service.
- `charge-icl-guard.timer` - periodic systemd timer.
- `override.conf` - systemd threshold configuration.
- `install.sh` - installer and uninstaller.

Installed commands are `charge-icl-guard`, `battinfo`, and `icl-menu`.
`charge_monitor.sh` and `fix-line-endings.sh` are run from the repository.

The runtime file `/run/charge-icl.high` stores the normal input limit for the
current boot and is not part of the repository.

## Installation

From the repository directory on the phone:

```sh
sh ./fix-line-endings.sh && sh -n charge_icl_guard.sh && sh -n battinfo.sh && sh -n icl-menu.sh && sh -n install.sh && sudo sh ./install.sh
```

The installer copies scripts to `/usr/local/bin`, installs the systemd units,
reloads systemd, and enables the timer.

Requirements: systemd, a POSIX shell such as BusyBox `ash`, `awk`, and either
`doas` or `sudo`.

If the fixer itself was copied with CRLF, run this bootstrap command first:

```sh
sed -i 's/\r$//' fix-line-endings.sh
sh ./fix-line-endings.sh
```

## Configuration

Edit `override.conf` before installation or reinstall after changing it:

```ini
[Service]
Environment=STOP_THRESHOLD=65
Environment=START_THRESHOLD=35
Environment=ICL_LOW=100000
```

Apply an installed configuration change with:

```sh
sudo systemctl daemon-reload
sudo systemctl restart charge-icl-guard.timer
```

The guard accepts positive input limits in microamps, in 25,000-uA increments.
For the Poco F1, `ICL_LOW=100000` (100 mA) is a tested hold-mode setting that
usually makes the battery slowly discharge under normal use. Use 500 mA when
slow charging above the stop threshold is preferred.

## Monitoring

Display a single status snapshot:

```sh
sudo /usr/local/bin/battinfo
```

Monitor battery and charger currents for six samples at 30-second intervals:

```sh
sh ./charge_monitor.sh
```

The monitor displays current values in mA. Use shorter tests with:

```sh
SAMPLES=3 INTERVAL=10 sh ./charge_monitor.sh
```

For this Poco F1 configuration:

- Positive battery current indicates battery charging.
- Negative battery current indicates battery discharging.
- Charger `current_now` is USB input current, not battery current.
- `status=Charging` means the charger is enabled, but battery current shows
  whether power is actually flowing into or out of the battery.

Check the service and timer:

```sh
sudo systemctl status charge-icl-guard.timer --no-pager
sudo journalctl -u charge-icl-guard.service -n 20 --no-pager
```

## Manual ICL control

Run the interactive menu from the repository or use the installed command:

```sh
sudo /usr/local/bin/icl-menu
```

The menu supports 25 mA increments up to 4,800 mA, subject to the charger
driver, power adapter, cable, and device thermal limits.

## Uninstall

```sh
sudo sh ./install.sh --uninstall
```

## Safety notes

- Input-current limiting does not replace the charger IC's battery protection.
- A low limit can make the battery discharge while USB remains connected.
- A high limit can increase adapter, cable, connector, and phone temperature.
- The guard verifies current-limit readback and skips writes while offline.
- Test new limits while monitoring battery current and temperature.
