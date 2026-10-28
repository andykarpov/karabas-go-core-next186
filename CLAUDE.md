# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

The Next186 core (an 80186 PC SoC by Nicolae Dumitrache, opencores.org project next186) for the Karabas Go, Mini and Mini G boards: Xilinx Spartan-6 XC6SLX25-2 FTG256, ISE 14.7 (XST). The README calls it a port of the ZXDOS+ Next186. It has 32 MB SDRAM, USB keyboard and mouse emulated as PS/2 devices (the MCU sends `CMD_PS2_SCANCODE`, the core answers with `PS2_COMMAND`), Adlib (jtopl), Tandy sound (`sn76489`) and the BIOS loaded from the core file. The repo is MIT licensed (LICENSE), the BIOS source keeps its own copyright notice.

The core is on branch `master`. The core is not converted to `karabas-go-modules` yet. It has its own copies of the MCU link and the board modules under `src/rtl`.

## Layout

- `src/rtl/karabas_186.v`: the machine (clocks from the `dcm` / `dcm_dsp` IP cores, the CPU unit, SDRAM, the `mcu` link, `soft_switches`, `bios_loader`, `overlay`, sound). Its parameter `BURST_MAX_MHZ` goes to `mcu`.
- `src/rtl/karabas_go_top.v` (VGA out), `karabas_mini_top.v` and `karabas_minig_top.v` (HDMI through `zhdmi_top`): the board tops around `karabas_186`.
- `src/rtl/Next186`: the CPU. Also in `src/rtl`: `unit186.v`, `ddr_186.v`, `cache_controller.v`, `sdram.v`, `vga.v`, `PIC_8259.v`, `timer8253.v`, `KB_8042.v`, `jtopl`, `sn76489`, `uart`, `midi`, `hdmi`, `zhdmi`, `osd` (`overlay.vhd`, `pix_doubler.vhd`).
- `src/rtl/mcu`: `mcu.vhd`, `burst_rx.vhd`, `soft_switches.vhd`, a local copy of the MCU link.
- `src/ipcore_dir`: the CoreGen IP (`dcm`, `dcm_cpu`, `dcm_dsp`, block RAMs and fifos such as `cache`, `DAC_SRAM`, `datamem16`, `sndfifo`). Sound (Tandy `sn76489_top`, `jtopl2`) is instantiated in `ddr_186.v`.
- `src/186Code`: the x86 side. `BIOS/` has the BIOS source and its build, plus DOS tools and notes (`How to create FreeDos bootable SD card with a big FAT32 partition.txt`).
- `src/sim`: the burst link testbench.

## Build

- ISE GUI projects: `src/karabas_go.xise`, `karabas_mini.xise`, `karabas_minig.xise`. There is no Makefile or command-line flow for the FPGA. The result is `src/karabas_<board>_top.bin`. ISE writes its build outputs into `src/` (they are in `.gitignore`).
- `src/timings.xcf` is tracked but none of the `.xise` files use it.
- Packing: `src/make_core.py` is a symlink to `../../karabas-go-tools/make_core/make_core.py`, so the tools repo must sit next to this one. It packs `core.json` (Go), `core_mini.json`, `core_minig.json` into `src/next186.kg1` / `kg2` / `kg3`. The `.bin` and `.kg*` files are committed.
- BIOS: `cd src/186Code/BIOS && make` builds `BIOS_Next186.com` from `BIOS_Next186.asm` with jwasm. The Makefile builds jwasm first from `jwasm/` (`GccUnix.mak`). The `.com` is the ROM of the core files (`186Code/BIOS/BIOS_Next186.com` at address 0), so rebuild the `.kg*` after a BIOS change.

## MCU link

- `type: osd`, `spi_freq: 8` (the link runs at 8 MHz), `eeprom_bank: 255`. The OSD items are the soft switches: Speed, ISA Wait, Fake 286, Joy swap, MIDI, Adlib, NMI and Reset (Ctrl+Alt+Del). Their order is the switch order in `soft_switches.vhd`.
- The BIOS comes in through the ROM loader (`CMD_ROMBANK` / `CMD_ROMDATA` / `CMD_ROMLOADER`) to `bios_loader` (`rtl/bios_loader_mist.v`, module `bios_loader`).
- Bursts: `mcu.vhd` answers `CMD_CAPS` (0xF7) with caps 0x03 and `BURST_MAX_MHZ`. That is 0 on Go and Mini (bursts at the link clock) and 32 on Mini G (`karabas_minig_top.v`). The second chip select goes to `burst_rx.vhd`.
- The x86 SD card is the FPGA's own SD slot (`SD_*` pins of the top). It is not the MCU's card.

## Simulation

- `src/sim/run_burst_sim.sh [settings64.sh]` (ISim) runs `tb_mcu_burst.vhd`: `spi_slave`, `burst_rx` and `mcu` at a 50 MHz clock, classic frames at 8 MHz, and bursts at 8 / 16 MHz and at 32 MHz with `MAX_MHZ=32`. `fifo1_sim.vhd` is a VHDL model of `rtl/fifo/fifo.v` (`fifo1`) for ISim only. It prints `SIMULATION PASSED`.

## Release

- The Go file is in the release repo `karabas-go` as `cores/next186.kg1`; the copy there is the same file as `src/next186.kg1`.

## Memory

The Claude Code memory of this repo is shared with all karabas-go repos: `~/.claude/projects/<this project>/memory` is a symlink to `../karabas-go-notes` (private repo `andykarpov/karabas-go-notes`, `link.sh` there makes the links). Its `MEMORY.md` is split by repo; commit and push it after every memory change.
