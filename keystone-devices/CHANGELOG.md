# keystone-devices changelog

## 0.1.1

- With nlbwmon, a reboot or restart no longer adds the month so far again. Totals were growing by a month each time.

## 0.1.0

- First release. Data used per device per billing period, from nlbwmon or its own nftables counters. Keeps the last 3 periods.
