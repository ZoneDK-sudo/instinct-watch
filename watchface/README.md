# Ride Ready watch face (Instinct 2X Solar)

Big time, a step-goal ring around the edge, live heart rate and HR zone in the round
subscreen, and a strip of the last ~4 hours of heart rate along the bottom.

Not compiled yet: this PC has no Connect IQ SDK or Java.

## Build it

1. Install a Java runtime (Temurin 17 or newer).
2. Install the Connect IQ SDK Manager from developer.garmin.com/connect-iq/sdk/,
   sign in with your Garmin account, download the latest SDK and the **Instinct 2X Solar** device.
3. Make a developer key once:
   ```powershell
   openssl genrsa -out developer_key.pem 4096
   openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem -out developer_key.der -nocrypt
   ```
4. Build from this folder:
   ```powershell
   monkeyc -f monkey.jungle -d instinct2x -y developer_key.der -o RideReady.prg
   ```
5. Try it in the simulator (`connectiq`, then `monkeydo RideReady.prg instinct2x`), or copy
   `RideReady.prg` to `D:\GARMIN\Apps\` with the watch plugged in, unplug, and pick
   **Ride Ready** under watch faces.
