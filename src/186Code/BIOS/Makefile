JWASM_DIR=.
AS=$(JWASM_DIR)/jwasm

all: Next186.ROM

Next186.ROM: BIOS_Next186.BIN
	mv BIOS_Next186.BIN Next186.ROM 

clean:
	rm $(PRJ).186
	rm $(PRJ).BIN

$(AS):
	make -C $(JWASM_DIR) -f GccUnix.mak

%.BIN : %.asm $(AS)
	$(AS) -bin $<
	
