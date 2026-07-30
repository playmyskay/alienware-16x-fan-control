# Alienware 16X Aurora Fan Control for Linux

A fan speed controller for the Alienware 16X Aurora (AC16251) on Linux,
achieved through reverse engineering of the ACPI/WMI interface.

> **Note:** This is a fork of the original project by
> [Hugo2049](https://github.com/Hugo2049/alienware-16x-fan-control). Since
> pull requests to the upstream repository have unfortunately gone
> unanswered for a while, I'm continuing development here, so the codebase
> will likely diverge from upstream over time.
>
> Changes made in this fork so far:
> - Live RPM and temperature graphing in the GUI
> - Automatic hwmon detection (coretemp/dell_ddv) with improved GPU temperature reading
> - Custom application icon and window settings
> - Relative helper script path, independent of the current working directory
> - Added GPL-2.0 license file
> - Live active-profile readout (`fan_helper.sh status`) via a genuine ACPI get-call, not just the effect on fans/temps
> - Discovered and added the 2 missing hardware thermal profiles (`cool`, true `performance`) and corrected the mislabeled `performance` → `balanced-performance`, in both the CLI and the GUI presets
> - Resizable main window

<img width="1115" height="1515" alt="Screenshot_20260617_194439" src="https://github.com/user-attachments/assets/de70f447-9db1-4158-9e1e-5ed985a75544" />


## Hardware
- Machine: Alienware 16X Aurora AC16251
- CPU: Intel Core Ultra 9 275HX
- GPU: NVIDIA GeForce RTX 5070 Laptop
- Tested on: Ubuntu 26.04 LTS, kernel 7.0.0-22-generic

## How it works

Dell/Alienware exposes fan control through a proprietary WMI interface
(AWCCWmiMethodFunction) implemented in ACPI SSDT table AWCCTABL.

By decompiling the ACPI tables and reverse engineering the WMAX method,
we discovered the following protocol:

### Fan Control Commands (via /proc/acpi/call)

The WMI interface exposes two separate WMAX methods: `0x15` is a **write-only
control method** (set fan speed, activate a profile) and `0x14` is a
**read-only information method** (query current profile, RPM, resource IDs).
Only `0x15` was known when this fork started; `0x14` was reverse engineered
afterwards (see [Discovery Method](#discovery-method)).

CPU fan speed (0-100%):
```bash
echo '\_SB.AMWW.WMAX 0 0x15 {0x02,0x32,SPEED,0x00}' > /proc/acpi/call
```

GPU fan speed (0-100%):
```bash
echo '\_SB.AMWW.WMAX 0 0x15 {0x02,0x33,SPEED,0x00}' > /proc/acpi/call
```

Thermal profiles — activate:
```bash
echo '\_SB.AMWW.WMAX 0 0x15 {0x01,ID,0x00,0x00}' > /proc/acpi/call
```

Where `SPEED` is a hex value from `0x00` (0%) to `0x64` (100%).

### Fan IDs
- 0x32 = CPU fan
- 0x33 = GPU fan

### Thermal Profile IDs

There are 6 profiles that can actually be activated on this hardware. 5 of
them live in the firmware's own thermal-profile table; Game Shift is a 6th,
separate special mode that sits outside that table but is activated the same
way. IDs were confirmed by activating each one and cross-checking both the
kernel's `/sys/firmware/acpi/platform_profile` and our own raw ACPI readback
(see below) — note the kernel's generic profile-name strings don't map 1:1
onto these IDs (e.g. both `0xA4` and `0xAB` read back as `performance` in
`platform_profile`, and `0xA1` reads back as `balanced-performance`, not
`performance`):

| ID   | Profile name (this project) | `platform_profile` string | In firmware's profile table? |
|------|------------------------------|----------------------------|-------------------------------|
| 0xA0 | Balanced                     | `balanced`                 | yes |
| 0xA1 | Balanced Performance         | `balanced-performance`     | yes |
| 0xA2 | Cool                         | `cool`                     | yes |
| 0xA3 | Quiet                        | `quiet`                    | yes |
| 0xA4 | Performance                  | `performance`              | yes |
| 0xAB | Game Shift                   | `performance`              | no (separate special mode) |

### Reading Values Back (via /proc/acpi/call)

Unlike `0x15`, method `0x14` can be safely called repeatedly with no side
effects — it only queries state.

Get the currently active thermal profile ID (returns one of the IDs above):
```bash
echo '\_SB.AMWW.WMAX 0 0x14 {0x0B,0x00,0x00,0x00}' > /proc/acpi/call
cat /proc/acpi/call
```

Get current RPM for a given fan (byte 1 = fan ID):
```bash
echo '\_SB.AMWW.WMAX 0 0x14 {0x05,FAN_ID,0x00,0x00}' > /proc/acpi/call
cat /proc/acpi/call
```

Get system description (byte 3 of the returned dword = number of profiles in
the firmware's table, i.e. 5):
```bash
echo '\_SB.AMWW.WMAX 0 0x14 {0x02,0x00,0x00,0x00}' > /proc/acpi/call
cat /proc/acpi/call
```

Enumerate resource IDs by index (fans first, then temp sensors, then thermal
profile IDs, all in one flat list — byte 1 = index, starting at 0; returns
`AE_AML_PACKAGE_LIMIT` once the index runs past the end):
```bash
echo '\_SB.AMWW.WMAX 0 0x14 {0x03,INDEX,0x00,0x00}' > /proc/acpi/call
cat /proc/acpi/call
```

On this hardware that enumeration returns, in order: `0x32`, `0x33` (fan
IDs), `0x101`, `0x106` (temperature sensor IDs), then `0xA0`..`0xA4` (the 5
thermal profile IDs from the table above).

There is **no equivalent get-call for the fan speed percentage** set via
`0x15`/`0x02` — the firmware only exposes the resulting RPM (`0x14`/`0x05`,
same value already visible via hwmon), not the originally commanded percent.
Ops `0x04`, `0x06`, `0x07`, `0x0C`–`0x0E` under `0x14` were also probed and
returned either `0xffffffff`/`0xfffffffe` (unsupported) or values unrelated to
fan percent.

`fan_helper.sh status` now surfaces the live profile readout as an `Active
Profile` section, sourced directly from `0x14`/`0x0B` rather than the kernel's
`platform_profile` abstraction, so it always matches this project's own
profile names 1:1.

## Dependencies

Arch Linux:
```bash
sudo pacman -S acpi_call-lts python-gobject gtk4 libadwaita
```

Load module:
```bash
sudo modprobe acpi_call
```

Auto-load on boot:
```bash
echo 'acpi_call' | sudo tee /etc/modules-load.d/acpi_call.conf
```

## Installation

```bash
git clone https://github.com/Hugo2049/alienware-16x-fan-control
cd alienware-16x-fan-control
```

Add sudoers rule:
```bash
echo "$USER ALL=(ALL) NOPASSWD: $(pwd)/fan_helper.sh" | sudo tee /etc/sudoers.d/fancontroller
sudo chmod 440 /etc/sudoers.d/fancontroller
chmod +x fan_helper.sh
```

Run:
```bash
python fan_control.py
```

## CLI Usage

```bash
sudo ./fan_helper.sh cpu 75
sudo ./fan_helper.sh gpu 50
sudo ./fan_helper.sh both 80 60
sudo ./fan_helper.sh profile <balanced|balanced-performance|cool|quiet|performance|gameshift>
sudo ./fan_helper.sh status
```

## Discovery Method

1. Dumped ACPI tables with acpidump
2. Decompiled SSDT tables with iasl
3. Found AWCCTABL SSDT containing AWCCWmiMethodFunction implementation
4. Reverse engineered WMAX method and AX24/AX26 sub-functions
5. Identified EC register writes via ECW1(0x21, speed) and ECW1(0x39, fan_id)
6. Confirmed via acpi_call kernel module

### Discovering the read-only `0x14` method

The upstream Linux kernel docs for the `alienware-wmi` driver
(https://docs.kernel.org/wmi/devices/alienware-wmi.html) document operation
`0x0B` under the Thermal Information method as "get current thermal profile
ID". That pointed at method `0x14` as this hardware's read counterpart to the
`0x15` control method already in use here (the kernel docs describe a newer
USTT-generation numbering scheme with different method/profile IDs that
didn't match this machine's behavior directly, so the exact method/op numbers
below were confirmed empirically rather than assumed from the docs):

1. Called `WMAX 0x14 {0x0B,...}` while cycling through known profiles
   (`quiet`/`performance`/`balanced` via `fan_helper.sh profile ...`) and
   cross-checked the returned ID against `/sys/firmware/acpi/platform_profile`
   — confirmed exact match (0xA3/0xA1/0xA0).
2. Called `WMAX 0x14 {0x02,...}` ("system description") and decoded the
   returned dword's byte 3 as a profile count (5) — matched enumerating 5
   distinct profile IDs.
3. Called `WMAX 0x14 {0x03,INDEX,...}` for increasing INDEX to enumerate all
   resource IDs (fans, temp sensors, thermal profiles) in one flat list,
   stopping once it returned `AE_AML_PACKAGE_LIMIT`. This is what revealed
   the previously-unknown `0xA2` (Cool) and `0xA4` (Performance) profile IDs.
4. Activated the two newly discovered IDs (`0xA2`, `0xA4`) via the existing,
   already-proven-safe `0x15`/`0x01` "activate profile" operation and
   confirmed their names via `platform_profile` (`cool`, `performance`).
5. Probed neighboring ops (`0x04`-`0x0E`) under `0x14` with a fan ID argument
   to look for a "get commanded fan %" readback; only `0x05` (RPM) returned
   a meaningful, fan-dependent value — no percent-readback exists.

All of the above used only the read-only `0x14` method (or the
already-established `0x15`/`0x01` activate-profile call with real,
firmware-reported IDs); no undocumented arguments were sent to the `0x15`
fan-speed sub-function (`0x02`), since that risks unintended fan-speed writes.

## Credits

Originally developed by Hugo ([Hugo2049](https://github.com/Hugo2049)) with
assistance from Claude (Anthropic). The reverse engineering methodology,
ACPI analysis, and protocol discovery were worked out collaboratively
through an iterative process of dumping tables, reading ASL source,
probing WMI interfaces on Windows, and testing on Linux via acpi_call.

Many thanks to Hugo for this groundwork — without it, this fork wouldn't exist.

Claude: https://claude.ai
Anthropic: https://anthropic.com

## License
GPL-2.0
