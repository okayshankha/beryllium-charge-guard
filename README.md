# Beryllium Charge Guard

A lightweight charging guard for **postmarketOS on the Xiaomi Poco F1**.

Beryllium Charge Guard controls the phone's **USB input current based on battery capacity**. Instead of repeatedly switching charging on and off it lowers the input-current limit when your chosen battery threshold gets reached then restores normal input later.

This project is a fork of [`laxdog/qcom-battery`](https://github.com/laxdog/qcom-battery) adapted for the **Xiaomi Poco F1 (codename: `beryllium`)**.

---

# Quick Start

Want everything running without reading about how it works?

From your repository directory run:

```sh
sudo sh ./install.sh
```

The installer copies the required files installs the systemd service and timer then enables the timer.

Check that the timer started:

```sh
sudo systemctl status charge-icl-guard.timer --no-pager
```

That's all you need for the default setup.

### Default behavior

With the default configuration:

| Battery level | USB input behavior |
|---|---|
| **65% or above** | Limit input to **100 mA** |
| **35% or below** | Restore normal input limit |
| **35%–65%** | Keep the current mode |
| **Charger disconnected** | Skip the update |

The default `100 mA` setting normally keeps battery drain very slow during everyday phone use. Actual behavior depends on how much power your phone consumes at any given moment.

### Watch battery current

Run:

```sh
sh ./charge_monitor.sh
```

For a shorter test:

```sh
SAMPLES=3 INTERVAL=10 sh ./charge_monitor.sh
```

Positive battery current means **charging**.

Negative battery current means **discharging**.

### Need a different low-current limit?

Edit:

```text
override.conf
```

For example:

```ini
[Service]
Environment=STOP_THRESHOLD=65
Environment=START_THRESHOLD=35
Environment=ICL_LOW=500000
```

Then apply the change:

```sh
sudo systemctl daemon-reload
sudo systemctl restart charge-icl-guard.timer
```

`500000` means **500 mA**.

For most users the default configuration can simply be installed and left alone.

---

# What does Beryllium Charge Guard actually do?

A phone normally keeps drawing power from USB while charging. Depending on your workload this can mean your battery spends long periods sitting near a high state of charge.

Beryllium Charge Guard takes a different approach.

When battery capacity reaches a configurable upper threshold the guard reduces USB input current to a low value. When capacity later falls below a configurable lower threshold the original input limit gets restored.

This creates a **hysteresis window** instead of switching modes every time battery percentage moves by one point.

For example:

```text
100% ─────────────────────────
             LOW CURRENT
65%  ────────┐
             │
35%  ────────┘
             NORMAL CURRENT
0%   ─────────────────────────
```

With the default settings the guard switches to low-current mode at **65%** and keeps that mode until battery capacity reaches **35%**.

---

# How it works

A systemd timer periodically starts:

```text
charge-icl-guard.service
```

The service runs the charging guard as a oneshot task.

During startup the guard determines the phone's normal USB input-current limit and stores it for the current boot in:

```text
/run/charge-icl.high
```

This runtime file is temporary. It does not belong in the repository and disappears across reboots.

Once battery capacity reaches `STOP_THRESHOLD` the guard writes `ICL_LOW` into the charger input-current property.

When capacity reaches `START_THRESHOLD` the saved normal input-current limit gets restored.

Between both thresholds nothing changes.

While USB power remains offline the guard skips updates.

---

# What it does not do

Beryllium Charge Guard controls **USB input current**.

It does not directly control the battery charger in the same way as a hardware charge-disable feature.

The guard does **not** modify:

- Battery charge current
- Battery voltage
- Charger `online` state

This distinction matters.

A low input limit can still allow some battery charging when phone power consumption becomes lower than available USB input power.

For example if USB input gets limited to 100 mA while your phone only consumes 60 mA then roughly 40 mA remains available for charging under those conditions.

Therefore:

> **Beryllium Charge Guard is an input-current limiter rather than a hardware charge-disable switch.**

---

# Poco F1 support

This project was developed around the Qualcomm charging implementation found on the Xiaomi Poco F1.

### Tested configuration

- **Device:** Xiaomi Poco F1
- **Codename:** `beryllium`
- **SoC:** Snapdragon 845 / SDM845
- **Charger IC:** Qualcomm PMI8998
- **Charger driver:** `qcom_smbx` / SMB2
- **Charger power supply:** `/sys/class/power_supply/pmi8998-charger/`
- **Input-current property:** `current_max`

The guard supports both common Qualcomm property names:

```text
input_current_limit
current_max
```

On this Poco F1 configuration:

```text
current_max
```

uses **microamps** and accepts values in **25,000 µA increments**.

Different Qualcomm devices may expose different power-supply paths or property names. They may also use different units and current steps.

Do not assume Poco F1 values will work unchanged elsewhere.

---

# Installation

Clone or copy this repository onto your Poco F1.

Enter the repository directory:

```sh
cd beryllium-charge-guard
```

Then run:

```sh
sudo sh ./install.sh
```

The installer:

1. Installs the command-line scripts into `/usr/local/bin`
2. Installs the systemd service
3. Installs the systemd timer
4. Reloads systemd
5. Enables the timer

After installation the following commands become available:

```text
charge-icl-guard
battinfo
icl-menu
```

The repository tools below remain available from the repository itself:

```text
charge_monitor.sh
fix-line-endings.sh
```

---

# Requirements

Beryllium Charge Guard requires:

- `systemd`
- A POSIX-compatible shell such as BusyBox `ash`
- `awk`
- Either `sudo` or `doas`

---

# Windows / CRLF line endings

If repository files were copied through Windows tooling they may contain **CRLF line endings**.

The project includes:

```text
fix-line-endings.sh
```

Run:

```sh
sh ./fix-line-endings.sh
```

This converts copied Windows-style line endings into Unix LF format.

### If the fixer itself has CRLF

Bootstrap it first:

```sh
sed -i 's/\r$//' fix-line-endings.sh
sh ./fix-line-endings.sh
```

Then continue with installation.

---

# Configuration

Configuration lives in:

```text
override.conf
```

Default configuration:

```ini
[Service]
Environment=STOP_THRESHOLD=65
Environment=START_THRESHOLD=35
Environment=ICL_LOW=100000
```

## `STOP_THRESHOLD`

Battery percentage where low-current mode gets activated.

Default:

```text
65
```

Example:

```ini
Environment=STOP_THRESHOLD=70
```

Low-current mode would then begin at 70%.

---

## `START_THRESHOLD`

Battery percentage where normal input current gets restored.

Default:

```text
35
```

Example:

```ini
Environment=START_THRESHOLD=40
```

Normal current would return at 40%.

---

## `ICL_LOW`

USB input-current limit used during low-current mode.

The value uses **microamps**.

Default:

```text
100000
```

which equals:

```text
100 mA
```

Common values:

| Configuration value | Current |
|---:|---:|
| `100000` | 100 mA |
| `250000` | 250 mA |
| `500000` | 500 mA |
| `1000000` | 1 A |
| `1500000` | 1.5 A |
| `2000000` | 2 A |
| `4000000` | 4 A |

For this Poco F1 configuration values should use **25,000 µA increments**.

For example:

```text
100000
125000
150000
175000
...
```

---

# Choosing `ICL_LOW`

A lower current limit does not necessarily mean zero battery charging.

Phone workload matters.

With:

```ini
Environment=ICL_LOW=100000
```

the Poco F1 generally consumes enough power during normal use that battery capacity slowly falls while USB remains connected.

This makes `100 mA` useful as a **hold-mode** setting.

For users who prefer slow charging instead of gradual discharge use something like:

```ini
Environment=ICL_LOW=500000
```

which gives the charger approximately **500 mA** of input current.

There is no universal best value.

Your workload adapter cable battery condition and thermals all affect the result.

---

# Applying configuration changes

After editing `override.conf` run:

```sh
sudo systemctl daemon-reload
sudo systemctl restart charge-icl-guard.timer
```

You can also reinstall the project:

```sh
sudo sh ./install.sh
```

The timer does not need to be manually invoked after installation.

---

# Monitoring

Beryllium Charge Guard includes several tools for checking charging behavior.

## Battery status snapshot

Run:

```sh
sudo /usr/local/bin/battinfo
```

This displays a single battery and charger status snapshot.

---

## Continuous current monitor

From the repository run:

```sh
sh ./charge_monitor.sh
```

The default monitor collects:

```text
6 samples
30 seconds between samples
```

For a short test:

```sh
SAMPLES=3 INTERVAL=10 sh ./charge_monitor.sh
```

The monitor reports current values in **mA**.

---

# Understanding battery and charger current

There are two current measurements worth distinguishing.

### Battery current

Battery current describes power flowing into or out of the battery.

For this configuration:

```text
positive  → battery charging
negative  → battery discharging
```

### Charger `current_now`

Charger `current_now` describes **USB input current**.

It does not directly represent battery charging current.

This difference can produce seemingly confusing results.

For example:

```text
charger_current = 100 mA
battery_current = -250 mA
status = Charging
```

This means USB remains connected and the charger remains enabled. However the phone consumes more power than USB currently provides.

The battery therefore supplies the difference.

Likewise:

```text
charger_current = 100 mA
battery_current = +30 mA
status = Charging
```

means approximately 30 mA reaches the battery after the phone's own consumption.

---

# Checking the systemd timer

Check timer status:

```sh
sudo systemctl status charge-icl-guard.timer --no-pager
```

Check the service:

```sh
sudo systemctl status charge-icl-guard.service --no-pager
```

View recent service logs:

```sh
sudo journalctl -u charge-icl-guard.service -n 20 --no-pager
```

Follow logs live:

```sh
sudo journalctl -u charge-icl-guard.service -f
```

---

# Manual ICL control

The project includes an interactive utility for manually changing the input-current limit.

Run:

```sh
sudo /usr/local/bin/icl-menu
```

The menu supports current selection in **25 mA increments** up to **4,800 mA**.

Actual usable limits depend on:

- Charger IC
- Kernel driver
- Power adapter
- USB cable
- Connector condition
- Device temperature
- Hardware limitations

A value being selectable does not guarantee that hardware will deliver that current.

---

# Included files

| File | Description |
|---|---|
| `charge_icl_guard.sh` | Battery-capacity-based input-current guard |
| `battinfo.sh` | Battery and charger status display |
| `icl-menu.sh` | Interactive manual ICL control |
| `charge_monitor.sh` | Repeated battery and charger current monitor |
| `fix-line-endings.sh` | Converts CRLF files into Unix LF format |
| `charge-icl-guard.service` | systemd oneshot service |
| `charge-icl-guard.timer` | Periodic systemd timer |
| `override.conf` | systemd environment configuration |
| `install.sh` | Installer and uninstaller |

---

# Runtime files

During operation the guard creates:

```text
/run/charge-icl.high
```

This file stores the normal input-current limit captured during the current boot.

It lives under `/run` so the value remains temporary.

It is **not part of the repository**.

---

# Troubleshooting

## The timer is not running

Check:

```sh
sudo systemctl status charge-icl-guard.timer --no-pager
```

Then inspect service logs:

```sh
sudo journalctl -u charge-icl-guard.service -n 50 --no-pager
```

---

## The current limit does not change

Check whether the charger exposes the expected interface:

```sh
ls -l /sys/class/power_supply/pmi8998-charger/
```

Read the current limit:

```sh
cat /sys/class/power_supply/pmi8998-charger/current_max
```

Also inspect charger status:

```sh
cat /sys/class/power_supply/pmi8998-charger/uevent
```

Then review guard logs:

```sh
sudo journalctl -u charge-icl-guard.service -n 20 --no-pager
```

---

## Battery still charges at 100 mA

This can be expected.

`ICL_LOW=100000` limits USB input rather than disabling battery charging.

If phone power consumption drops below 100 mA then remaining USB power may still flow into the battery.

Try a heavier normal workload while monitoring:

```sh
sh ./charge_monitor.sh
```

Battery current provides a better indication of actual battery behavior than charger `status`.

---

## Battery keeps switching around one threshold

This should not happen with normal hysteresis configuration.

For example:

```ini
Environment=STOP_THRESHOLD=65
Environment=START_THRESHOLD=35
```

means:

```text
65% → switch into low-current mode
35% → restore normal current
35–65% → keep current mode
```

Using thresholds too close together can make switching more frequent.

---

## The phone discharges while plugged in

This can be intentional.

A low `ICL_LOW` value can provide less USB power than your phone consumes.

For example:

```ini
Environment=ICL_LOW=100000
```

may result in:

```text
USB input       100 mA
Phone usage     400 mA
Battery         -300 mA
```

In that situation the battery continues discharging even though USB remains connected.

Increase `ICL_LOW` when slow charging or slower discharge is preferred.

---

# Safety notes

Input-current limiting does not replace protection built into the charger IC or battery-management system.

Keep these points in mind:

- Very low input current can cause battery discharge while USB remains connected.
- Higher input current can increase temperature.
- Adapter and cable quality can affect achievable current.
- Connector condition can affect charging behavior.
- Kernel-driver limitations may override requested values.
- Current limits should remain within hardware capabilities.
- Always watch battery current during initial testing.
- Monitor device temperature when experimenting with higher limits.

Start conservatively.

---

# Important limitation

Beryllium Charge Guard was developed specifically around the **Xiaomi Poco F1 / beryllium** Qualcomm charging implementation.

Other Qualcomm devices may expose:

- Different power-supply paths
- Different property names
- Different units
- Different current-step sizes
- Different charger-driver behavior

Consequently this project should **not** be considered universally compatible with Qualcomm devices.

---

# Uninstall

From the repository directory run:

```sh
sudo sh ./install.sh --uninstall
```

This removes the installed Beryllium Charge Guard components.

---

# Project origin

Beryllium Charge Guard started as a fork of:

https://github.com/laxdog/qcom-battery

The code and behavior have been adapted around the Xiaomi Poco F1's Qualcomm charging interface.

See the upstream repository for its original implementation.
