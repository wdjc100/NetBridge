# NetBridge
Work In Progress.
A script for easily routing traffic between network adapters. Designed and tested on Raspberry Pi 3 Model B.

Currently supports WiFi and Ethernet, with partial Bluetooth PAN support. Cellular support planned.

Possible use cases:
* Ethernet available in hotel/meeting room but no WiFi - plug Pi into Ethernet socket and route from eth0 to wlan0. Instant WiFi hotspot.
* TV/Games Console hasn't got WiFi - plug Pi into TV/Console Ethernet socket and route from wlan0 to eth0. Instant WiFi bridge.
