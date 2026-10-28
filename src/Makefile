# Command line build of the Next186 core for the three boards: the steps and options of the ISE 14.7
# project navigator (the .xise projects of the boards).
#
#   make                 all three boards (next186.kg1, next186.kg2, next186.kg3)
#   make go|mini|minig   one board: synthesis, implementation, bitstream, .kg file
#   make minig-xst       one step: <board>-xst (.ngc), <board>-impl (.bin), <board>-core (.kg)
#   make minig-report    LUTs, slices, block RAMs and the timing result of the last build
#   make clean           the intermediate files (not the .bin / .kg files, they are in git)
#
# Inputs per board: karabas_<board>_top.prj, .xst, karabas_<board>.ucf, karabas_<board>_top.ut.
# A step runs again when one of its inputs is newer than its output.
# The boards share xst/ and _ngo/, so they are built one after the other.

ISE_SETTINGS ?= /opt/Xilinx/14.7/ISE_DS/settings64.sh
PART = xc6slx25-ftg256-2
BOARDS = go mini minig

SHELL = /bin/bash
.SHELLFLAGS = -e -o pipefail -c
.NOTPARALLEL:
# settings64.sh takes the arguments of the shell that sources it: none here
XIL = source $(ISE_SETTINGS) > /dev/null;

KG_go = next186.kg1
KG_mini = next186.kg2
KG_minig = next186.kg3
JSON_go = core.json
JSON_mini = core_mini.json
JSON_minig = core_minig.json

# map / par options (as the .xise projects had them)
MAP_go = -logic_opt off -ol high -xe n -t 1 -xt 3 -register_duplication off -r 4 -global_opt off -mt off -ir off -pr b -lc off -power off
PAR_go = -ol high -xe n -mt off
MAP_mini = -logic_opt off -ol high -t 1 -xt 3 -register_duplication off -r 4 -global_opt off -mt off -ir off -pr off -lc off -power off
PAR_mini = -ol high -mt off
MAP_minig = $(MAP_mini)
PAR_minig = $(PAR_mini)

# included by the sources, not in the prj
INCLUDES = $(wildcard rtl/*.mem rtl/jtopl/ver/verilator/mmr.lut) 186Code/BIOS/BIOS_Next186.com

.PHONY: all clean $(BOARDS) $(BOARDS:=-xst) $(BOARDS:=-impl) $(BOARDS:=-core) $(BOARDS:=-report)

all: $(BOARDS)

define board
SRC_$(1) := $$(shell sed -n 's/^[a-z]* work "\(.*\)"/\1/p' karabas_$(1)_top.prj)

karabas_$(1)_top.ngc: karabas_$(1)_top.prj karabas_$(1)_top.xst $$(SRC_$(1)) $(INCLUDES)
	mkdir -p xst/projnav.tmp
	$(XIL) xst -intstyle ise -ifn karabas_$(1)_top.xst -ofn karabas_$(1)_top.syr

karabas_$(1)_top.bin: karabas_$(1)_top.ngc karabas_$(1).ucf karabas_$(1)_top.ut
	$(XIL) ngdbuild -intstyle ise -dd _ngo -sd ipcore_dir -nt timestamp -uc karabas_$(1).ucf -p $(PART) karabas_$(1)_top.ngc karabas_$(1)_top.ngd
	$(XIL) map -intstyle ise -p $(PART) -w $(MAP_$(1)) -o karabas_$(1)_top_map.ncd karabas_$(1)_top.ngd karabas_$(1)_top.pcf
	$(XIL) par -w -intstyle ise $(PAR_$(1)) karabas_$(1)_top_map.ncd karabas_$(1)_top.ncd karabas_$(1)_top.pcf
	$(XIL) trce -intstyle ise -v 3 -s 2 -n 3 -fastpaths -xml karabas_$(1)_top.twx karabas_$(1)_top.ncd -o karabas_$(1)_top.twr karabas_$(1)_top.pcf -ucf karabas_$(1).ucf
	$(XIL) bitgen -intstyle ise -f karabas_$(1)_top.ut karabas_$(1)_top.ncd

$(KG_$(1)): karabas_$(1)_top.bin $(JSON_$(1)) 186Code/BIOS/BIOS_Next186.com
	python3 make_core.py $(JSON_$(1)) $$@

$(1): $(KG_$(1))
$(1)-xst: karabas_$(1)_top.ngc
$(1)-impl: karabas_$(1)_top.bin
$(1)-core: $(KG_$(1))
$(1)-report:
	@grep -E "Number of (Slice LUTs|occupied Slices|RAMB16BWERs|RAMB8BWERs):" karabas_$(1)_top_map.mrp
	@grep -E "constraints? (was|were) met|constraints? not met|Timing Score" karabas_$(1)_top.par | sort -u
endef

$(foreach b,$(BOARDS),$(eval $(call board,$(b))))

clean:
	rm -rf _ngo _xmsgs xlnx_auto_0_xdb xst
	rm -f *.bgn *.bit *.drc *.ncd *.ngc *.ngd *.ngr *.pad *.par *.pcf *.ptwx
	rm -f *.unroutes *.xpi *.map *.mrp *.ngm *.xrpt *.twr *.twx *.lso *.syr
	rm -f *.cmd_log *.log *.xml *.html *.xwbt
