# Karabas Go Next186 Core

A port of the Next186 core (from ZXDOS+) to the Karabas Go hardware

## What's done:

- 32 MB SDRAM at 80 MHz
- CPU at 50 MHz
- USB keyboard and mouse emulated as PS/2 devices (emulated keyboard supports scancodeset 1 and 2)
- BIOS loaded by the core (no need to write it at the end of SD card anymore)
- Adlib OPL2

## TODO:

- RS232 over USB
- MIDI via MPU401 + ADC
- CF card as HDD
- Joystick support
- Mouse wheel
