all: testbench_top

testbench_top: IVFLAGS+=-I../
testbench_top: kb_tb.v ../KB_8042.v ../fifo/fifo.v

testbench_%:
	iverilog -g2005-sv ${IVFLAGS} -o $@.vvp $^
	vvp $@.vvp
	gtkwave tb.gtkw
	@rm $@.vvp

clean:
	rm -rf *.vcd *.vvp

-include Makefile.local
