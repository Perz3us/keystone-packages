# keystone-alerts changelog

## 0.1.1

- When signal history began counting partway through the billing period, the "runs out on" warning measures the pace from that day instead of the start of the period.

## 0.1.0

- First release. Logs outages, weak signal, new devices, data use and restarts, each set to buzz, log or off.
- Phones check in the background without logging in, with a key they prove they hold and a signed answer.
- The background check also sends online state, RSRP, SINR, the bands in use and the active data plan, for the home-screen widgets.
