# Keystone packages

Router packages for the Keystone app, one package per feature. The app talks to each of them over ubus on the router.

## Packages

| Package | What it does |
| --- | --- |
| keystone-history | Records signal, ping and traffic history (7 days by default) so the app can draw graphs. |
| keystone-alerts | Watches for outages, weak signal, new devices and data use, and keeps a small log for the app. Needs keystone-history. |
| keystone-devices | Adds up the data each device uses per billing period. Needs keystone-history. |
| keystone-cellguard | Removes a cell lock that leaves the router offline. Needs keystone-history. |

## keystone-history

Every 2 minutes it records one reading: RSRP, SINR, PCI, EARFCN, the main band and every band in use (so carrier aggregation shows as B3+B1+B40), plus a ping. The signal values come from the 5G Modem app if it is installed, then QModem, then ModemManager. ModemManager gives RSRP and SINR but not the bands, and its signal polling is turned on the first time if it was off. With none of them, only the ping is recorded.

The ping is bound to the mobile interface, so Passwall or a VPN does not change it. The target is 8.8.8.8, change it with `uci set keystone-history.main.ping_target=1.1.1.1; uci commit keystone-history`. If ICMP is blocked, it falls back to the TCP connect time to `tcp_target` (default 1.1.1.1, port 80), also bound to the mobile interface.

Traffic is the byte count of the mobile interface, added up per month and per day for each SIM (by ICCID when the modem app reports it). The app reads usage for the current billing period from `info` and saves a SIM's plan (unlimited, capped or fair use, allowance and billing day) with `set_plan`.

Readings are kept in /tmp/keystone-history and copied to /etc/keystone-history once an hour, never more than about 150 KB per kept day (1 to 4 MB). The app reads them through the ubus object `keystone.history` (`info`, `history` and `set`).

Change how many days are kept (1 to 30, default 7) with `uci set keystone-history.main.keep_days=14; uci commit keystone-history`, or from the app.

## keystone-alerts

Checks every 30 seconds and logs:

- the internet going down and coming back
- signal below a set RSRP (-110 dBm by default) for 5 minutes
- a device joining for the first time
- data use passing 80% of a capped plan, or 90% of a fair-use one
- the router or the modem restarting

Each alert type is `buzz` (the phone notifies), `log` (only in the list) or `off`, set from the app or in /etc/config/keystone-alerts.

The log keeps up to 500 events or 30 days. Outages and restarts are written to flash straight away so they survive a power cut. Everything else is copied once an hour, and never more than 100 KB.

The phone checks in the background without logging in. When it pairs, it gets a key, then proves it holds the key on each check without sending it, and the router signs its answer the same way. That background check is the only thing a phone can do without logging in. Pairing again replaces the key, so only the phone that paired last keeps getting alerts. The ubus object is `keystone.alerts`.

## keystone-devices

Counts what each device downloads and uploads in the current billing period, using the billing day from keystone-history. It uses nlbwmon when that is running, otherwise its own nftables counters. The last 3 periods are kept. Flow offloading lets traffic skip the counters, so totals read low when it is on. `info` says so. The ubus object is `keystone.devices`.

## Install

The Keystone app can do this for you. By hand, copy the package to /tmp on the router, then:

    apk add --allow-untrusted /tmp/keystone-history-0.3.0.apk

or on older firmware:

    opkg install /tmp/keystone-history_0.3.0_all.ipk

keystone-alerts and keystone-devices install the same way, after keystone-history.

To remove one, use `apk del <package>` or `opkg remove <package>`. Saved data in /etc stays until you delete it.

## Build

With the OpenWrt 25.12 SDK in the owrt-sdk-cache Docker volume, this builds every package folder, or just one if you pass its name:

    docker run --rm -v owrt-sdk-cache:/cache -v "$PWD:/src" owrt-sdk-env sh /src/build.sh [keystone-history]

The packages are shell scripts, so `pack.sh` can also build them without the SDK. It needs apk-tools 3 (Alpine has it) and root:

    sh pack.sh [keystone-alerts]

Either way the packages end up in dist/.

## Releases

Each package is versioned and released on its own. Its version is `PKG_VERSION` in its Makefile, and what changed is in its CHANGELOG.md.

While a package is below 1.0, its ubus calls can still change. Raise the last number for a fix (0.1.1) and the middle one for anything else (0.2.0). From 1.0.0 on:

- 1.0.1: a fix, nothing new for the app.
- 1.1.0: something new that older apps can ignore, such as a new field.
- 2.0.0: something older apps would break on, such as a changed or removed ubus call.

To release, raise the version in the Makefile, add it to the changelog, and push a tag named after the package:

    git tag keystone-alerts-v0.2.0
    git push origin keystone-alerts-v0.2.0

GitHub builds that package, checks the tag matches the Makefile, and publishes a release with the changelog entry as its notes. A version like `0.2.0_beta1` is published as a pre-release, which the app only offers with experimental features turned on.

## Tests

    for p in common keystone-*; do busybox sh $p/tests/test.sh; done

Run them from a path without spaces.

## License

GPL 3.0

## keystone-cellguard

The app arms it just before it locks a cell. It notes the ping and RSRP of the cell before the lock, then checks the modem every 15 seconds.

For the first 4 minutes it removes the lock if the modem has no internet for 2 minutes, if more than half the checks fail, if the ping is more than twice as slow (and 50 ms slower), or if the signal is 10 dB weaker and at -115 dBm or below. After that it removes the lock only if the modem receives nothing for 5 minutes. A weaker cell that still works is kept, since people lock to quieter towers on purpose.

A check passes on a ping reply, a TCP connect over the modem of 2 ms or more (a faster answer is a local proxy such as Passwall, not the internet), or new bytes received on the modem. Once the trial is over, received data alone is enough, so a working lock costs no extra traffic. If it never saw the internet working, before or after the lock, it leaves the lock alone.

It removes locks with the 5G Modem scripts, then AT commands if those refuse, or QModem. Failed attempts are retried 1, 2, 3 and up to 10 minutes apart. It never locks again by itself. The app reads what happened from the ubus object `keystone.cellguard` (`info`, `arm`, `disarm` and `ack`).
