# Fuel Guide CIQ data field

Experimental Connect IQ data field for Forerunner 265. Garmin invokes `compute()` once per second; the field keeps a five-second, 120-sample rolling window and posts an optional relay payload every 60 seconds (minimum configurable interval: 30 seconds).

For personal sideloading, run `pnpm build:personal` using the gitignored `.personal.json` and the relay token from `.env`. The mobile Connect IQ settings screen does not work for sideloaded apps. The standard store build can use Connect IQ app settings. The URL and token default to empty, so no network request is made until configured. The field always sends `temperatureC: null`.

The field only presents experimental trend and relay candidate text. Relay responses show `MOCK` or `JEV` mode. It does not make audio notifications, clinical claims, or automatic alarms.

Build with:

```sh
CIQ_SDK_HOME=/path/to/connectiq-sdk \
CIQ_DEVELOPER_KEY=/path/to/developer_key \
./scripts/build-ciq.sh
```
