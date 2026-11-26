# keystone-history changelog

## 0.3.1

- Data used this month now includes traffic from before the package was installed, taken from the firmware's own monthly counter (5G Modem app) or vnstat. Totals were far too low when it was installed mid-month.
- Plans say which day counting began when it began inside the period, so the app can say "since" instead of "this month".

## 0.3.0

- Records every band in use, primary first, so carrier aggregation shows up (B3+B1+B40).
- Reads RSRP and SINR from ModemManager on routers without the 5G Modem app or QModem, and turns its signal polling on if it was off.
- Counts traffic per day and per SIM, not only per month. An upgrade counts the month so far as its first day.
- Saves a data plan per SIM: unlimited, capped or fair use, with an allowance and billing day (`set_plan`). `info` gives usage for the current billing period.
- Carries the check that keeps scheduled restarts from running during an upgrade, a call or the first hour after boot.

## 0.2.0

- Keeps 1 to 30 days of history, set with `keep_days` or from the app.
- Falls back to the TCP connect time when ICMP is blocked.

## 0.1.0

- First release: signal, ping and monthly traffic every 2 minutes.
