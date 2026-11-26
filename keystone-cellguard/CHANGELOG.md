# keystone-cellguard changelog

## 0.1.0

- First release. Watches a cell lock set from the Keystone app and removes it if the modem can't connect within 2 minutes, the cell drops, is much slower, or has a much weaker and unusable signal than the cell before it, or if the modem receives nothing for 5 minutes later on.
- Works with ping blocked by the carrier and with Passwall or a VPN running: it uses ping, a TCP connect over the modem, and the data the modem receives.
- Removes the lock with the 5G Modem scripts, falls back to AT commands when they refuse, and uses QModem on QModem firmware. Never locks again by itself.
