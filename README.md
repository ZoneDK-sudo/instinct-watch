# Instinct 2X projects

Watch faces and data tools for a Garmin Instinct 2X Solar.

| Folder | What it is |
| --- | --- |
| [`workday/`](workday/) | **Workday** watch face for desk days: Body Battery, hours moved, sitting timer, stress, watch battery days and unread notifications |
| [`watchface/`](watchface/) | **Ride Ready**, an earlier watch face: step ring, heart rate and zone, 4-hour heart-rate strip |
| [`dashboard/`](dashboard/) | Instinct Logbook web page: route map, ride replay, Health Snapshots, today's data |
| [`workout/`](workout/) | E-Bike Zone Builder interval workout (.FIT) |
| [`tools/`](tools/) | Scripts: read the watch's .FIT files, build the workout, render the clock font, build and screenshot in the simulator |

Personal data (`garmin-data/`, `dashboard/data.json`) and build output are git-ignored.

## Workday watch face

```
 WED 25        ( 64 )   date              Body Battery
 [bat]5d [msg]2 (BODY)   watch battery     unread notifications
 STRESS 35               stress now
 3h24 LEFT               time left in the workday (WEEKEND / PRE-WORK / OFF WORK)
      12:59
 [][][][][]. . .  5/8    one box per work hour: solid = walked 250+ steps that hour
 SIT 14m   5PM ~31       sitting time; Body Battery forecast for end of day
```

- **Hour boxes:** solid = goal hit, hollow = missed, thick border = this hour (fills as you walk), dot = later today.
- **Sitting:** minutes since you last walked 30+ steps in a minute. Turns into a black **MOVE** bar after the limit during work hours.
- **Forecast:** where Body Battery lands at the end of the workday if it keeps changing at the rate of the last 1-2 hours. Appears after about an hour of history.
- **Weekends:** shows WEEKEND and today's steps instead of the hour boxes (unless weekend tracking is on).
- **Unread count** includes every notification your phone forwards to the watch, not only texts.
- Steps and sitting are only counted while Workday is the active watch face.

### Settings (Garmin Connect app → Device → Activities & Apps → Workday → Settings)

| Setting | Default |
| --- | --- |
| Workday starts / ends (24-hour clock, up to 12 hours) | 9 / 17 |
| Steps that count an hour as moved | 250 |
| Show MOVE after sitting (minutes) | 50 |
| Track Saturday and Sunday too | off |

## Building

Needs Java 17+ and the Connect IQ SDK (install through Garmin's SDK Manager, plus the Instinct 2X Solar device).

Make a signing key once and keep it outside the repo. You need the same key for future updates:

```powershell
mkdir $HOME\.garmin
openssl genrsa -out $HOME\.garmin\developer_key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER -in $HOME\.garmin\developer_key.pem -out $HOME\.garmin\developer_key.der -nocrypt
```

Build Workday, run it in the simulator and save a screenshot:

```powershell
.\tools\build-sim.ps1
```

Install: plug in the watch, copy `workday\bin\Workday.prg` to `GARMIN\Apps\` on the watch, unplug, then choose **Workday** under Watch Face.

### Clock font

The clock digits are a 1-bit bitmap font rendered from [Barlow Condensed](https://github.com/jpt/barlow) Bold by `tools/make-font.ps1`. Barlow is licensed under the SIL Open Font License 1.1 ([`workday/resources/fonts/OFL.txt`](workday/resources/fonts/OFL.txt)).

To re-render from a .ttf file or an installed font:

```powershell
.\tools\make-font.ps1 -FontFile .\BarlowCondensed-Bold.ttf -DigitHeight 56
.\tools\make-font.ps1 -Family "Some Installed Font" -DigitHeight 56
```

## Watch data tools

```powershell
cd tools
npm install
node extract.mjs        # reads ..\garmin-data into ..\dashboard\data.json
node make-workout.mjs   # writes ..\workout\EBIKEZN.FIT
```

Copy the watch's `GARMIN\Activity`, `Monitor`, `Records` and `Totals` folders into `garmin-data\` first. The dashboard stores GPS positions only relative to your usual start point, never as coordinates.
