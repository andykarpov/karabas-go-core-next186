`timescale 1ns / 1ps

// The virtual HDD of Next186: hdf_ata.v (SYNC_BUS, the one clock I/O strobes of the CPU as
// karabas_186.v connects them) + img_sdc.v, with a model of the mcu firmware on the IMG_* ports
// (from tb_hdf.v of the nanomig core).
// - a mount, IDENTIFY, READ SECTORS of LBA 0 and 63 as the BIOS (ataread) does them;
// - a CHS read (cylinder 1, the IDENTIFY geometry) and the same sector by LBA: the same data;
// - the reset of the CPU (ata_reset: reset button, OSD Reset, Ctrl+Alt+Del) after the mount,
//   then the same reads again: they must reach the mcu and give the data.
// Ends with "tb_ata: N errors".

module tb_ata;

reg clk = 1'b0;
always #10 clk = ~clk; // 50 MHz, clk_cpu

reg reset = 1'b1;     // areset
reg ata_reset = 1'b1; // the CPU reset
integer errors = 0;
task check(input [255:0] what, input [31:0] got, input [31:0] exp);
	if (got !== exp) begin
		errors = errors + 1;
		if (errors < 30) $display("%t ERROR %0s: %0x, expected %0x", $time, what, got, exp);
	end
endtask

// ---------------- the I/O bus of the CPU ----------------

reg [2:0] a = 3'd0;
reg [1:0] cs_n = 2'b11;
reg rd_n = 1'b1, wr_n = 1'b1;
reg [15:0] din = 16'd0;
wire [15:0] dout;

// a port access: the strobe is one clock, the CPU takes the data at its end
task io_wr(input [2:0] port, input [7:0] d);
	begin
		@(negedge clk); a <= port; cs_n <= 2'b10; wr_n <= 1'b0; din <= { 8'd0, d };
		@(negedge clk); cs_n <= 2'b11; wr_n <= 1'b1;
		repeat (4) @(negedge clk);
	end
endtask
reg [15:0] rdata;
task io_rd(input [2:0] port);
	begin
		@(negedge clk); a <= port; cs_n <= 2'b10; rd_n <= 1'b0;
		@(posedge clk); rdata = dout;
		@(negedge clk); cs_n <= 2'b11; rd_n <= 1'b1;
		repeat (4) @(negedge clk);
	end
endtask

// ---------------- hdf_ata + img_sdc + mcu firmware model ----------------

wire [7:0] sdc_img_mounted;
wire [63:0] sdc_img_size;
wire [1:0] hdf_rd, hdf_wr;
wire [31:0] sdc_sector;
wire sdc_busy, sdc_done, sdc_error;
wire [2:0] sdc_slot;
wire sdc_byte_in_strobe;
wire [8:0] sdc_byte_addr;
wire [7:0] sdc_byte_in_data, sdc_byte_out_data;

hdf_ata #(.DEF_HEADS(5'd16), .DEF_SPT(8'd63), .SYNC_BUS(1)) hdf(
	.clk(clk), .reset(reset), .ata_reset(ata_reset), .dev0_en(1'b1), .dev(), .dev1_here(),
	.a(a), .cs_n(cs_n), .rd_n(rd_n), .wr_n(wr_n), .din(din), .dout(dout),
	.img_mounted(sdc_img_mounted[1:0]), .img_size(sdc_img_size),
	.sdc_rd(hdf_rd), .sdc_wr(hdf_wr), .sdc_sector(sdc_sector),
	.sdc_busy(sdc_busy), .sdc_done(sdc_done), .sdc_error(sdc_error),
	.sdc_byte_in_strobe(sdc_byte_in_strobe), .sdc_byte_addr(sdc_byte_addr),
	.sdc_byte_in_data(sdc_byte_in_data), .sdc_byte_out_data(sdc_byte_out_data),
	.led()
);

reg [7:0] img_mounted = 8'd0;
reg [63:0] img_size = 64'd0;
reg img_data_wr = 1'b0, img_result_wr = 1'b0;
reg [8:0] img_data_addr = 9'd0;
reg [7:0] img_data = 8'd0, img_result = 8'd0;
reg [15:0] img_sum = 16'd0;
wire img_q_wr;
wire [23:0] img_q_di;
reg img_q_ack = 1'b0;

img_sdc #(.OUT_LATENCY(3), .TIMEOUT(24'd20000), .RETRIES(2'd3)) img(
	.clk(clk), .reset(reset),
	.img_mounted(img_mounted), .img_size(img_size),
	.img_data_wr(img_data_wr), .img_data_addr(img_data_addr), .img_data(img_data),
	.img_result_wr(img_result_wr), .img_result(img_result), .img_sum(img_sum),
	.img_q_wr(img_q_wr), .img_q_di(img_q_di), .img_q_ack(img_q_ack),
	.sdc_img_mounted(sdc_img_mounted), .sdc_img_size(sdc_img_size),
	.sdc_rd({ 6'd0, hdf_rd }), .sdc_wr({ 6'd0, hdf_wr }), .sdc_sector(sdc_sector),
	.sdc_busy(sdc_busy), .sdc_done(sdc_done), .sdc_error(sdc_error), .sdc_slot(sdc_slot),
	.sdc_byte_in_strobe(sdc_byte_in_strobe), .sdc_byte_addr(sdc_byte_addr),
	.sdc_byte_in_data(sdc_byte_in_data), .sdc_byte_out_data(sdc_byte_out_data),
	.active()
);

localparam DISK_SECTORS = 2000;
function [7:0] dbyte(input [31:0] lba, input [8:0] i);
	dbyte = lba[7:0] ^ i[7:0] ^ 8'h5A ^ { 7'd0, i[8] };
endfunction
integer mcu_reads = 0;

// the frames of img_sdc, taken a few clocks after they are put up
reg [31:0] q_lba = 0;
reg [7:0] q_slot = 0, q_op = 0;
reg q_sec = 0;
always @(posedge clk) begin
	img_q_ack <= 1'b0;
	if (img_q_wr && !img_q_ack) begin
		img_q_ack <= 1'b1;
		case (img_q_di[23:16])
			8'h42: q_lba[img_q_di[9:8]*8 +: 8] = img_q_di[7:0];
			8'h43: begin q_slot = img_q_di[15:8]; q_op = img_q_di[7:0]; q_sec = 1; end
			default: ;
		endcase
	end
end

task mcu_result(input [7:0] r);
	begin
		@(posedge clk); img_result <= r; img_result_wr <= 1'b1;
		@(posedge clk); img_result_wr <= 1'b0;
	end
endtask

// the firmware: a read request (IMG_SEC), the sector bytes and their sum, the result
reg [7:0] b;
integer k;
reg [15:0] s;
initial begin : mcu_model
	forever begin
		@(posedge clk);
		if (q_sec && q_op == 8'd1) begin
			q_sec = 0;
			#20000;
			if (q_slot == 0) mcu_reads = mcu_reads + 1;
			s = 0;
			for (k = 0; k < 512; k = k + 1) begin
				b = dbyte(q_lba, k);
				s = s + b;
				@(posedge clk); img_data_wr <= 1'b1; img_data_addr <= k; img_data <= b;
				@(posedge clk); img_data_wr <= 1'b0;
			end
			img_sum <= s;
			mcu_result(8'd1);
		end
	end
end

task mount(input [63:0] size);
	begin
		@(posedge clk); img_size <= size; img_mounted <= 8'h01;
		@(posedge clk); img_mounted <= 8'h00;
	end
endtask

// ---------------- the BIOS ----------------

task wait_bsy;
	integer n;
	begin
		n = 0;
		io_rd(3'd7);
		while (rdata[7] && n < 100000) begin io_rd(3'd7); n = n + 1; end
		if (rdata[7]) begin $display("%t ERROR BSY stays", $time); errors = errors + 1; end
	end
endtask

// the geometry of IDENTIFY (words 3 and 6), for the CHS reads
integer id_heads = 0, id_spt = 0;

task identify;
	begin
		io_wr(3'd6, 8'hE0);
		io_wr(3'd7, 8'hEC);
		wait_bsy;
		for (k = 0; k < 256; k = k + 1) begin
			io_rd(3'd0);
			if (k == 3) id_heads = rdata;
			if (k == 6) id_spt = rdata;
		end
	end
endtask

// ataread of one sector: BSY, the task file (LBA, or CHS of the IDENTIFY geometry), READ SECTORS, DRQ or ERR, 256 words
task ataread(input [31:0] lba, input chs, input [255:0] what);
	integer n, i;
	reg [15:0] w;
	integer bad;
	integer c, h, sec;
	begin
		wait_bsy;
		if (chs) begin
			sec = lba % id_spt + 1;
			h = (lba / id_spt) % id_heads;
			c = lba / (id_spt * id_heads);
			io_wr(3'd6, 8'hA0 | h[3:0]);
			io_wr(3'd2, 8'd1);
			io_wr(3'd3, sec[7:0]);
			io_wr(3'd4, c[7:0]);
			io_wr(3'd5, c[15:8]);
		end
		else begin
			io_wr(3'd6, 8'hE0 | lba[27:24]);
			io_wr(3'd2, 8'd1);
			io_wr(3'd3, lba[7:0]);
			io_wr(3'd4, lba[15:8]);
			io_wr(3'd5, lba[23:16]);
		end
		io_wr(3'd7, 8'h20);
		n = 0;
		io_rd(3'd7);
		while ((rdata[7] || !(rdata[3] || rdata[0])) && n < 100000) begin io_rd(3'd7); n = n + 1; end
		if (rdata[0] || !rdata[3]) begin
			io_rd(3'd1);
			$display("%t ERROR %0s: lba %0d, error %02x", $time, what, lba, rdata[7:0]);
			errors = errors + 1;
		end
		else begin
			bad = 0;
			for (i = 0; i < 256; i = i + 1) begin
				io_rd(3'd0);
				w = { dbyte(lba, 2 * i + 1), dbyte(lba, 2 * i) };
				if (rdata !== w) bad = bad + 1;
			end
			check(what, bad, 0);
		end
	end
endtask

integer r0;
initial begin
	repeat (10) @(posedge clk);
	reset <= 1'b0;
	repeat (100) @(posedge clk);
	ata_reset <= 1'b0; // the BIOS is loaded: the CPU runs

	// the firmware mounts the image after the BIOS is loaded
	repeat (1000) @(posedge clk);
	r0 = mcu_reads;
	mount(DISK_SECTORS * 512);
	// the mount reads sector 0 for the geometry without BSY: a command in that time races it
	wait (mcu_reads != r0);
	repeat (100) @(posedge clk);
	wait_bsy;

	identify;
	$display("geometry: %0d heads, %0d sectors", id_heads, id_spt);

	r0 = mcu_reads;
	ataread(0, 0, "read lba 0");
	ataread(63, 0, "read lba 63");
	check("mcu reads", mcu_reads - r0, 2);

	// CHS: cylinder 1 and a head and a sector above 1, the same data as the LBA reads
	ataread(id_heads * id_spt + 2 * id_spt + 4, 1, "read chs");
	ataread(id_heads * id_spt + 2 * id_spt + 4, 0, "read the chs sector by lba");
	check("mcu reads chs", mcu_reads - r0, 4);

	// the CPU reset (OSD Reset, Ctrl+Alt+Del): the CPU is held ~5 ms, then the BIOS starts again
	ata_reset <= 1'b1;
	repeat (5000) @(posedge clk);
	ata_reset <= 1'b0;
	repeat (100) @(posedge clk);

	identify;

	r0 = mcu_reads;
	ataread(0, 0, "read lba 0 after reset");
	ataread(63, 0, "read lba 63 after reset");
	check("mcu reads after reset", mcu_reads - r0, 2);

	$display("tb_ata: %0d errors", errors);
	$finish;
end

endmodule
