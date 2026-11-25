# Keystone packages

Router packages for the Keystone app, one package per feature. The app talks to each of them over ubus on the router.

## Packages

| Package | What it does |
| --- | --- |
| keystone-history | Records signal, ping and traffic history for the last 7 days so the app can draw graphs. |

## keystone-history

Every 2 minutes it records one reading: RSRP, SINR, PCI, EARFCN and band, plus a ping. The signal values come from the 5G Modem app if it is installed, otherwise from QModem. With neither, only the ping is recorded.

The ping is bound to the mobile interface, so Passwall or a VPN does not change it. The target is 8.8.8.8, change it with `uci set keystone-history.main.ping_target=1.1.1.1; uci commit keystone-history`.

Traffic is the byte count of the mobile interface, added up per month.

Readings are kept in /tmp/keystone-history and copied to /etc/keystone-history once an hour, never more than about 1 MB. The app reads them through the ubus object `keystone.history` (`info` and `history`).

## Install

The Keystone app can do this for you. By hand, copy the package to /tmp on the router, then:

    apk add --allow-untrusted /tmp/keystone-history-0.1.0.apk

or on older firmware:

    opkg install /tmp/keystone-history_0.1.0_all.ipk

To remove it, use `apk del keystone-history` or `opkg remove keystone-history`. The saved history in /etc/keystone-history stays until you delete it.

## Build

With the OpenWrt 25.12 SDK in the owrt-sdk-cache Docker volume, this builds every package folder, or just one if you pass its name:

    docker run --rm -v owrt-sdk-cache:/cache -v "$PWD:/src" owrt-sdk-env sh /src/build.sh [keystone-history]

The packages end up in dist/. Pushing a tag like v0.1.0 builds all packages on GitHub and adds them to a release. Each package keeps its own version in its Makefile.

## Tests

    busybox sh keystone-history/tests/test.sh

## License

GPL 3.0
