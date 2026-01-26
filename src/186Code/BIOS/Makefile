JWASM_DIR=.
AS=$(JWASM_DIR)/jwasm
PRJ=BIOS_Next186

all: $(PRJ).com

$(PRJ).com: $(PRJ).BIN
	mv $(PRJ).BIN $(PRJ).com

clean:
	rm $(PRJ).err
	rm $(PRJ).com

$(AS):
	make -C $(JWASM_DIR) -f GccUnix.mak

%.BIN : %.asm $(AS)
	$(AS) -bin $<
	
