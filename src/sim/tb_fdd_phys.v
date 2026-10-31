`timescale 1ns / 1ps

// The physical floppy drive of the Karabas Go through the port of Next186: fdd_port.v (PHYS 1,
// the CPU bus as karabas_186.v connects it) + pcxt_fdd_phys (the times made short) + a drive model
// (fdd_model.v, from karabas-go-core-pcxt) on DS1, mapped to drive A by CMD_IMG_PHYS (slot 2,
// DS1). The port steps as the BIOS (fdxfer) does them: the geometry of the probe, a read, a write
// and its read back, a sector of an unformatted track (error 1), a format of it (the buffer of F6,
// command 3 on each sector) and a read of it, the write protect, an image mounted over the drive.
// Ends with "tb_fdd_phys: N errors". Run: src/sim/run_fdd_phys_sim.sh (iverilog, a few minutes).

module tb_fdd_phys;

reg clk = 1'b0;
always #10 clk = ~clk;

reg reset = 1'b1;
integer errors = 0;
task check(input [255:0] what, input [31:0] got, input [31:0] exp);
	if (got !== exp) begin
		$display("ERROR %0s: %h, expected %h", what, got, exp);
		errors = errors + 1;
	end
endtask

// ---------------- the I/O bus of the CPU ----------------

reg cs = 1'b0, we = 1'b0;
reg [2:0] a = 3'd0;
reg [7:0] din = 8'd0;
wire [7:0] dout;

task io_wr(input [2:0] port, input [7:0] d);
	begin
		@(negedge clk); a <= port; cs <= 1'b1; we <= 1'b1; din <= d;
		@(negedge clk); cs <= 1'b0; we <= 1'b0;
		repeat (3) @(negedge clk);
	end
endtask
reg [7:0] rdata;
task io_rd(input [2:0] port);
	begin
		@(negedge clk); a <= port; cs <= 1'b1; we <= 1'b0;
		@(posedge clk); rdata = dout;
		@(negedge clk); cs <= 1'b0;
		repeat (3) @(negedge clk);
	end
endtask

// ---------------- fdd_port, the drive ----------------

reg [1:0] img_mounted = 2'b00;
reg [63:0] img_size = 64'd0;
reg img_phys_wr = 1'b0;
reg [15:0] img_phys = 16'd0;
wire [3:0] fdd_in;
wire [7:0] fdd_out;

fdd_port #(.PHYS(1)) dut(
	.clk(clk), .reset(reset),
	.cs(cs), .we(we), .a(a), .din(din), .dout(dout),
	.img_mounted(img_mounted), .img_size(img_size),
	.sdc_rd(), .sdc_wr(), .sdc_sector(),
	.sdc_busy(1'b0), .sdc_done(1'b0), .sdc_error(1'b0),
	.sdc_byte_in_strobe(1'b0), .sdc_byte_addr(9'd0), .sdc_byte_in_data(8'd0), .sdc_byte_out_data(),
	.img_phys_wr(img_phys_wr), .img_phys(img_phys),
	.fdd_in(fdd_in), .fdd_out(fdd_out)
);
defparam dut.g_phys.u_phys.STEP_US = 20;
defparam dut.g_phys.u_phys.SETTLE_US = 50;
defparam dut.g_phys.u_phys.SPIN_US = 500;
defparam dut.g_phys.u_phys.NOIDX_US = 60000;
defparam dut.g_phys.u_phys.OP_US = 400000;
defparam dut.g_phys.u_phys.CELL_500 = 7'd10;
defparam dut.g_phys.u_phys.CELL_300 = 7'd17;
defparam dut.g_phys.u_phys.CELL_250 = 7'd20;

// 500 kbit/s, 6 sectors, 2 heads
fdd_model #(.DS(1), .CELL(10), .SPT(6), .HEADS(2), .TRK_BYTES(4200), .SPEED(1.01), .CYL0(3)) drv(
	.fdd_out(fdd_out), .fdd_in(fdd_in));

function [7:0] pat(input integer c, input integer h, input integer r, input integer i);
	pat = (c * 7 + h * 13 + r * 3 + i) & 255;
endfunction

// ---------------- the BIOS ----------------

task wait_ready;
	integer t;
	begin
		t = 0;
		io_rd(3'd0);
		while (rdata[7] && t < 20000000) begin io_rd(3'd0); t = t + 1; end
		if (rdata[7]) begin $display("ERROR busy timeout"); errors = errors + 1; end
	end
endtask

task command(input [15:0] lba, input [1:0] op);
	begin
		io_wr(3'd0, lba[7:0]);
		io_wr(3'd1, lba[15:8]);
		io_wr(3'd4, { 6'd0, op });
		wait_ready;
		$display("%0t: command %0d LBA %0d: status %h", $time, op, lba, rdata);
	end
endtask

reg [7:0] sec [0:511];
task read_buf;
	integer i;
	for (i = 0; i < 512; i = i + 1) begin
		io_rd(3'd3);
		sec[i] = rdata;
	end
endtask

integer i, errs0, t;
initial begin
	repeat (10) @(posedge clk);
	reset = 1'b0;
	repeat (10) @(posedge clk);
	drv.unfmt_c = 9;

	// the mcu: slot 2 (A) size 0, then CMD_IMG_PHYS 46 02 02 (DS1)
	@(posedge clk); img_size <= 64'd0; img_mounted <= 2'b01;
	@(posedge clk); img_mounted <= 2'b00;
	repeat (20) @(posedge clk);
	@(posedge clk); img_phys <= 16'h0202; img_phys_wr <= 1'b1;
	@(posedge clk); img_phys_wr <= 1'b0;
	io_wr(3'd2, 8'h10);            // A, motor A
	t = 0;
	io_rd(3'd0);
	while (!rdata[4] && t < 2000000) begin io_rd(3'd0); t = t + 1; end
	check("A status", rdata, 8'h50);
	io_rd(3'd1); check("A spt", rdata, 6);
	io_rd(3'd2); check("A cylinders", rdata, 80);
	$display("%0t: A probed: status %h", $time, rdata);

	// C 2 H 1 R 5 = LBA (2 * 2 + 1) * 6 + 4 = 34
	command(16'd34, 2'd1);
	check("read status", rdata, 8'h50);
	read_buf;
	errs0 = errors;
	for (i = 0; i < 512; i = i + 1)
		if (errors < errs0 + 4) check("read byte", sec[i], pat(2, 1, 5, i));

	// write C 4 H 0 R 2 = LBA 49, read back
	io_wr(3'd4, 8'h00);
	for (i = 0; i < 512; i = i + 1)
		io_wr(3'd3, (i * 3 + 7) & 255);
	command(16'd49, 2'd2);
	check("write status", rdata, 8'h50);
	command(16'd49, 2'd1);
	read_buf;
	errs0 = errors;
	for (i = 0; i < 512; i = i + 1)
		if (errors < errs0 + 4) check("read back byte", sec[i], (i * 3 + 7) & 255);

	// C 9 (unformatted): not found; format C 9 H 0 (LBA 108..113), read R 4
	command(16'd108, 2'd1);
	check("unformatted status", rdata, 8'h51);
	io_wr(3'd4, 8'h00);
	for (i = 0; i < 512; i = i + 1)
		io_wr(3'd3, 8'hF6);
	io_wr(3'd5, 8'h06);            // 500 kbit/s, 6 sectors
	for (i = 0; i < 6; i = i + 1)
		command(108 + i, 2'd3);
	check("format status", rdata, 8'h50);
	check("format IDs", drv.fmt_ids, 6);
	drv.unfmt_c = 255;
	command(16'd111, 2'd1);
	check("formatted status", rdata, 8'h50);
	read_buf;
	check("formatted byte", sec[300], 8'hF6);

	// write protected: probe again (the mcu maps the slot again)
	drv.wprot = 1'b1;
	@(posedge clk); img_phys <= 16'h0202; img_phys_wr <= 1'b1;
	@(posedge clk); img_phys_wr <= 1'b0;
	repeat (100) @(posedge clk);
	while (dut.g_phys.u_phys.st != 0) @(posedge clk);
	repeat (100) @(posedge clk);
	io_rd(3'd0);
	check("wp status", rdata, 8'h70);

	// an image over it: 1.44M from the size
	@(posedge clk); img_size <= 64'd1474560; img_mounted <= 2'b01;
	@(posedge clk); img_mounted <= 2'b00;
	repeat (40) @(posedge clk);
	io_rd(3'd1); check("image spt", rdata, 18);
	check("image map", dut.map0, 0);

	if (drv.crc_errs != 0) begin
		$display("ERROR: %0d CRC errors in the written fields", drv.crc_errs);
		errors = errors + 1;
	end
	$display("tb_fdd_phys: %0d errors", errors);
	$finish;
end

initial begin
	#2000000000;
	$display("ERROR timeout");
	$display("tb_fdd_phys: %0d errors", errors + 1);
	$finish;
end

endmodule
