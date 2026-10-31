# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

The Next186 core (an 80186 PC SoC by Nicolae Dumitrache, opencores.org project next186) for the Karabas Go, Mini and Mini G boards: Xilinx Spartan-6 XC6SLX25-2 FTG256, ISE 14.7 (XST). The README calls it a port of the ZXDOS+ Next186. It has 32 MB SDRAM, USB keyboard and mouse emulated as PS/2 devices (the MCU sends `CMD_PS2_SCANCODE`, the core answers with `PS2_COMMAND`), Adlib (jtopl), Tandy sound (`sn76489`) and the BIOS loaded from the core file. The repo is MIT licensed (LICENSE), the BIOS source keeps its own copyright notice.

The core is on branch `master`. It uses `karabas-go-modules` as the submodule `modules/` (its `master`) and mounts HDD and floppy images.

## Layout

- `src/rtl/karabas_186.v`: the machine (clocks from the `dcm` / `dcm_dsp` IP cores, the CPU unit, SDRAM, `kg_mcu`, `kg_soft_switches`, `bios_loader`, `overlay`, `img_sdc` + `hdf_ata` for the HDD images and `fdd_port` for the floppy drives, sound). Its parameter `BURST_MAX_MHZ` goes to `kg_mcu`, `PHYS_FDD` (Go: 1) to `fdd_port`.
- `src/rtl/fdd`: `fdd_port.v`, the floppy drives A / B at 3F0h-3F5h: a sector port for the BIOS (LBA, command, 512-byte buffer, status, geometry), not a 765 (the SoC has no DMA). Images: slots 2 / 3 of `img_sdc`. Go: a slot mapped to a physical drive goes to `pcxt_fdd_phys.v` (+ `mfm_rx.v`, `mfm_tx.v`, copies from karabas-go-core-pcxt `src/rtl/fdd`).
- `src/rtl/karabas_go_top.v` (VGA out), `karabas_mini_top.v` and `karabas_minig_top.v` (HDMI through `rtl/hdmi/zhdmi_top.v`): the board tops around `karabas_186`.
- `src/rtl/Next186`: the CPU. Also in `src/rtl`: `unit186.v`, `ddr_186.v`, `cache_controller.v`, `sdram.v`, `vga.v`, `PIC_8259.v`, `timer8253.v`, `KB_8042.v`, `jtopl`, `sn76489`, `uart`, `midi`, `fifo`.
- `modules/rtl`: the shared code, listed in the `.prj` files as `../modules/rtl/...`: `mcu` (`kg_mcu`, `kg_burst_rx`, `img_sdc`, `hdf_ata`), `ctl` (`kg_soft_switches`, `kg_sync`), `video/osd` (`overlay`, `pix_doubler`), `video/hdmi` (`zhdmi_*`, `dvi`), `mem/kg_fifo.v`.
- `src/ipcore_dir`: the CoreGen IP (`dcm`, `dcm_cpu`, `dcm_dsp`, block RAMs and fifos such as `cache`, `DAC_SRAM`, `datamem16`, `sndfifo`). Sound (Tandy `sn76489_top`, `jtopl2`) is instantiated in `ddr_186.v`.
- `src/sim`: `tb_ata.v` (ISim, `run_ata_sim.sh`): `hdf_ata` + `img_sdc` with a model of the MCU, BIOS-style reads before and after a CPU reset; ends with `tb_ata: 0 errors`. `tb_fdd.v` (`run_fdd_sim.sh`): `fdd_port` + `img_sdc`, the port steps of the BIOS (read, write, format, no disk); ends with `tb_fdd: 0 errors`.
- `src/186Code`: the x86 side. `BIOS/` has the BIOS source and its build, plus DOS tools and notes (`How to create FreeDos bootable SD card with a big FAT32 partition.txt`).

## Build

- `src/Makefile` (ISE 14.7 command line): `make go|mini|minig`, steps `<board>-xst`, `-impl`, `-core`, `make <board>-report`. Inputs per board: `karabas_<board>_top.prj`, `.xst`, `.ut`, `karabas_<board>.ucf`. The results are `src/karabas_<board>_top.bin` and `src/next186.kg1` / `kg2` / `kg3`; ISE writes its other outputs into `src/` (in `.gitignore`). There are no `.xise` projects.
- Packing: `src/make_core.py` is a symlink to `../../karabas-go-tools/make_core/make_core.py`, so the tools repo must sit next to this one. It packs `core.json` (Go), `core_mini.json`, `core_minig.json`. The `.bin` and `.kg*` files are committed.
- BIOS: `cd src/186Code/BIOS && make` builds `BIOS_Next186.com` from `BIOS_Next186.asm` with jwasm. The Makefile builds jwasm first from `jwasm/` (`GccUnix.mak`). The `.com` is the ROM of the core files (`186Code/BIOS/BIOS_Next186.com` at address 0), so rebuild the `.kg*` after a BIOS change.

## MCU link

- `type: osd`, `eeprom_bank: 255`, `spi_freq` 16 (Go, Mini) and 32 (Mini G). The OSD items: Speed, ISA Wait, Fake 286, Joy swap, MIDI, Adlib, HDD0 Mode, Boot (A: then C: / C: then A:, the BIOS reads it at port 06h bit 0), the file slots HDD0 / HDD1 / FDD A / FDD B (Go: `physical`), NMI and Reset (Ctrl+Alt+Del). The switch index is the item position counting the file slots too (Boot 7, HDD0 8, HDD1 9, FDD A 10, FDD B 11, NMI 12, Reset 13); register n of `softsw_regs` in `karabas_186.v` is item n.
- The BIOS comes in through the ROM loader (`CMD_ROMBANK` / `CMD_ROMDATA` / `CMD_ROMLOADER`) to `bios_loader` (`rtl/bios_loader_mist.v`, module `bios_loader`).
- Bursts: `kg_mcu` answers `CMD_CAPS` with `BURST_MAX_MHZ`: 0 on Go and Mini (bursts at the link clock), 32 on Mini G (`karabas_minig_top.v`).
- HDD images: slots 0 and 1 go through `img_sdc` to `hdf_ata` (ATA at the IDE ports of the system, `SYNC_BUS=1`). HDD0 Mode: Auto (image device 0 and the FPGA SD card), Image (the SD card chip select is held off), SD2 card (image device 0 off). The BIOS has an ATA PIO driver for it (`ataread` / `atawrite` / `ataverify`): drive 80h is the ATA master or the SD card, 81h the ATA slave (HDD1).
- Floppy: slots 2 / 3 (FDD A / B) through `img_sdc` to `fdd_port`; the BIOS floppy driver (`fdxfer`, INT 13h DL 0 / 1, 1.44M drive type, no change line) talks to the port. Boot order from the OSD Boot item (`tryboot` in INT 19h).
- The x86 SD card is the FPGA's own SD slot (`SD_*` pins of the top). It is not the MCU's card.

## Release

- The Go file is in the release repo `karabas-go` as `cores/next186.kg1`; the copy there is the same file as `src/next186.kg1`.

## Memory

The Claude Code memory of this repo is shared with all karabas-go repos: `~/.claude/projects/<this project>/memory` is a symlink to `../karabas-go-notes` (private repo `andykarpov/karabas-go-notes`, `link.sh` there makes the links). Its `MEMORY.md` is split by repo; commit and push it after every memory change.
