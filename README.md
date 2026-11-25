# Keystone helper

Collects signal, ping and traffic history on the router for the Keystone app, so the app can draw graphs for the last 7 days.

## What it does

Every 2 minutes it records one reading: RSRP, SINR, PCI, EARFCN and band, plus a ping. The signal values come from the 5G Modem app if it is installed, otherwise from QModem. With neither, only the ping is recorded.

The ping is bound to the mobile interface, so Passwall or a VPN does not change it. The target is 8.8.8.8, change it with `uci set keystone.main.ping_target=1.1.1.1; uci commit keystone`.

Traffic is the byte count of the mobile interface, added up per month.

Readings are kept in /tmp and copied to /etc/keystone once an hour, never more than about 1 MB. The app reads them through the ubus object `keystone` (`info` and `history`).

## Install

The Keystone app can do this for you. By hand, copy the package to /tmp on the router, then:

    apk add --allow-untrusted /tmp/keystone-helper-0.1.0.apk

or on older firmware:

    opkg install /tmp/keystone-helper_0.1.0_all.ipk

To remove it, use `apk del keystone-helper` or `opkg remove keystone-helper`. The saved history in /etc/keystone stays until you delete it.

## Build

With the OpenWrt 25.12 SDK in the owrt-sdk-cache Docker volume:

    docker run --rm -v owrt-sdk-cache:/cache -v "$PWD:/src" owrt-sdk-env sh /src/build.sh

Pushing a tag like v0.1.0 builds the packages on GitHub and adds them to a release.

## Tests

    busybox sh tests/test.sh

## License

GPL 3.0
