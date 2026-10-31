`timescale 1ns / 1ps

// The floppy drives of Next186: fdd_port.v (the one clock I/O strobes of the CPU as karabas_186.v
// connects them, the read data in that clock) + img_sdc.v (slots 2 and 3), with a model of the
// mcu firmware on the IMG_* ports (reads and writes). The port steps as the BIOS (fdxfer) does
// them:
// - mount A 1.44M, B 720K: the geometry and the status of each;
// - a read of A, C 1 H 1 R 3 (LBA 1*36 + 18 + 2 = 56), 512 bytes from the data port;
// - a write of A LBA 78 and the read back;
// - B: the last sector (LBA 1439);
// - a format of B, C 0 H 1 (as the BIOS: the buffer of F6 once, a command 3 per sector);
// - a drive without a disk: error 3; unmount of A.
// Ends with "tb_fdd: N errors".

module tb_fdd;

reg clk = 1'b0;
always #10 clk = ~clk; // 50 MHz, clk_bus

reg reset = 1'b1;
integer errors = 0;
task check(input [255:0] what, input [31:0] got, input [31:0] exp);
	if (got !== exp) begin
		errors = errors + 1;
		if (errors < 30) $display("%t ERROR %0s: %0x, expected %0x", $time, what, got, exp);
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

// ---------------- fdd_port + img_sdc + mcu firmware model ----------------

wire [7:0] sdc_img_mounted;
wire [63:0] sdc_img_size;
wire [1:0] fdd_rd, fdd_wr;
wire [31:0] sdc_sector;
wire sdc_busy, sdc_done, sdc_error;
wire [2:0] sdc_slot;
wire sdc_byte_in_strobe;
wire [8:0] sdc_byte_addr;
wire [7:0] sdc_byte_in_data, sdc_byte_out_data;
wire fdd_own = (sdc_slot[2:1] == 2'b01);

fdd_port #(.PHYS(0)) fdd(
	.clk(clk), .reset(reset),
	.cs(cs), .we(we), .a(a), .din(din), .dout(dout),
	.img_mounted(sdc_img_mounted[3:2]), .img_size(sdc_img_size),
	.sdc_rd(fdd_rd), .sdc_wr(fdd_wr), .sdc_sector(sdc_sector),
	.sdc_busy(sdc_busy & fdd_own), .sdc_done(sdc_done & fdd_own), .sdc_error(sdc_error),
	.sdc_byte_in_strobe(sdc_byte_in_strobe & fdd_own), .sdc_byte_addr(sdc_byte_addr),
	.sdc_byte_in_data(sdc_byte_in_data), .sdc_byte_out_data(sdc_byte_out_data),
	.img_phys_wr(1'b0), .img_phys(16'd0), .fdd_in(4'd0), .fdd_out()
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

img_sdc #(.OUT_LATENCY(3), .TIMEOUT(24'd200000), .RETRIES(2'd3)) img(
	.clk(clk), .reset(reset),
	.img_mounted(img_mounted), .img_size(img_size),
	.img_data_wr(img_data_wr), .img_data_addr(img_data_addr), .img_data(img_data),
	.img_result_wr(img_result_wr), .img_result(img_result), .img_sum(img_sum),
	.img_q_wr(img_q_wr), .img_q_di(img_q_di), .img_q_ack(img_q_ack),
	.sdc_img_mounted(sdc_img_mounted), .sdc_img_size(sdc_img_size),
	.sdc_rd({ 4'd0, fdd_rd, 2'b00 }), .sdc_wr({ 4'd0, fdd_wr, 2'b00 }), .sdc_sector(sdc_sector),
	.sdc_busy(sdc_busy), .sdc_done(sdc_done), .sdc_error(sdc_error), .sdc_slot(sdc_slot),
	.sdc_byte_in_strobe(sdc_byte_in_strobe), .sdc_byte_addr(sdc_byte_addr),
	.sdc_byte_in_data(sdc_byte_in_data), .sdc_byte_out_data(sdc_byte_out_data),
	.active()
);

// the image: a pattern, and up to 32 written sectors over it
function [7:0] dbyte(input [7:0] slot, input [31:0] lba, input [8:0] i);
	dbyte = lba[7:0] ^ i[7:0] ^ 8'h5A ^ { 7'd0, i[8] } ^ { slot[2:0], 5'd0 } ^ lba[15:8];
endfunction
reg [7:0] wsec [0:32*512-1];
reg [31:0] wsec_lba [0:31];
reg [7:0] wsec_slot [0:31];
integer wsec_n = 0;
integer mcu_reads = 0, mcu_writes = 0;
reg [31:0] last_lba = 0;
reg [7:0] last_slot = 0;

function [7:0] ibyte(input [7:0] slot, input [31:0] lba, input [8:0] i);
	integer j;
	begin
		ibyte = dbyte(slot, lba, i);
		for (j = 0; j < wsec_n; j = j + 1)
			if (wsec_lba[j] == lba && wsec_slot[j] == slot)
				ibyte = wsec[j*512 + i];
	end
endfunction

reg [31:0] q_lba = 0;
reg [7:0] q_slot = 0, q_op = 0;
reg q_sec = 0;
reg [7:0] wbuf [0:511];
reg wbank = 0;
reg [15:0] wsum_got = 0, wsum_calc = 0;
reg wdone = 0;
integer k;
always @(posedge clk) begin
	img_q_ack <= 1'b0;
	if (img_q_wr && !img_q_ack) begin
		img_q_ack <= 1'b1;
		case (img_q_di[23:16])
			8'h42: q_lba[img_q_di[9:8]*8 +: 8] = img_q_di[7:0];
			8'h43: begin q_slot = img_q_di[15:8]; q_op = img_q_di[7:0]; q_sec = 1; end
			8'h44:
				if (img_q_di[15:8] == 8'h00) wbank = img_q_di[0];
				else if (img_q_di[15:8] == 8'h10) wsum_got[7:0] = img_q_di[7:0];
				else if (img_q_di[15:8] == 8'h11) begin wsum_got[15:8] = img_q_di[7:0]; wdone = 1; end
			8'h45: wbuf[{ wbank, img_q_di[15:8] }] = img_q_di[7:0];
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

reg [7:0] b;
reg [15:0] s;
initial begin : mcu_model
	forever begin
		@(posedge clk);
		if (q_sec && q_op == 8'd1) begin
			q_sec = 0;
			#20000;
			mcu_reads = mcu_reads + 1;
			last_lba = q_lba;
			last_slot = q_slot;
			s = 0;
			for (k = 0; k < 512; k = k + 1) begin
				b = ibyte(q_slot, q_lba, k);
				s = s + b;
				@(posedge clk); img_data_wr <= 1'b1; img_data_addr <= k; img_data <= b;
				@(posedge clk); img_data_wr <= 1'b0;
			end
			img_sum <= s;
			mcu_result(8'd1);
		end
		else if (q_sec && q_op == 8'd2 && wdone) begin
			q_sec = 0;
			wdone = 0;
			#20000;
			wsum_calc = 0;
			for (k = 0; k < 512; k = k + 1)
				wsum_calc = wsum_calc + wbuf[k];
			check("write sum", wsum_got, wsum_calc);
			for (k = 0; k < 512; k = k + 1)
				wsec[wsec_n*512 + k] = wbuf[k];
			wsec_lba[wsec_n] = q_lba;
			wsec_slot[wsec_n] = q_slot;
			wsec_n = wsec_n + 1;
			mcu_writes = mcu_writes + 1;
			last_lba = q_lba;
			last_slot = q_slot;
			mcu_result(8'd1);
		end
	end
end

task mount(input [2:0] slot, input [63:0] size);
	begin
		@(posedge clk); img_size <= size; img_mounted <= 8'h01 << slot;
		@(posedge clk); img_mounted <= 8'h00;
		repeat (20) @(posedge clk);
	end
endtask

// ---------------- the BIOS ----------------

task wait_ready;
	integer t;
	begin
		t = 0;
		io_rd(3'd0);
		while (rdata[7] && t < 200000) begin io_rd(3'd0); t = t + 1; end
		if (rdata[7]) begin $display("ERROR busy timeout"); errors = errors + 1; end
	end
endtask

// a command on LBA, the status after it in rdata
task command(input [15:0] lba, input [1:0] op);
	begin
		io_wr(3'd0, lba[7:0]);
		io_wr(3'd1, lba[15:8]);
		io_wr(3'd4, { 6'd0, op });
		wait_ready;
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

integer i, errs0, w0;
initial begin
	repeat (10) @(posedge clk);
	reset = 1'b0;
	repeat (10) @(posedge clk);

	mount(3'd2, 64'd1474560);
	mount(3'd3, 64'd737280);
	io_wr(3'd2, 8'h10);            // A, motor A
	io_rd(3'd0); check("A status", rdata, 8'h50);   // two heads, a disk
	io_rd(3'd1); check("A spt", rdata, 18);
	io_rd(3'd2); check("A cylinders", rdata, 80);
	io_wr(3'd2, 8'h21);            // B, motor B
	io_rd(3'd0); check("B status", rdata, 8'h50);
	io_rd(3'd1); check("B spt", rdata, 9);
	io_rd(3'd2); check("B cylinders", rdata, 80);

	// A: C 1, H 1, R 3 = LBA 56
	io_wr(3'd2, 8'h10);
	command(16'd56, 2'd1);
	check("A read status", rdata, 8'h50);
	check("A read slot", last_slot, 2);
	check("A read lba", last_lba, 56);
	read_buf;
	errs0 = errors;
	for (i = 0; i < 512; i = i + 1)
		if (errors < errs0 + 4) check("A read byte", sec[i], dbyte(2, 56, i));
	$display("A read LBA 56: %0d errors", errors - errs0);

	// A: write LBA 78 (the pointer to 0 first), then read it back
	io_wr(3'd4, 8'h00);
	for (i = 0; i < 512; i = i + 1)
		io_wr(3'd3, i[7:0] ^ 8'hC3 ^ { 7'd0, i[8] });
	w0 = mcu_writes;
	command(16'd78, 2'd2);
	check("A write status", rdata, 8'h50);
	check("A write count", mcu_writes - w0, 1);
	check("A write lba", last_lba, 78);
	check("A write slot", last_slot, 2);
	command(16'd78, 2'd1);
	read_buf;
	errs0 = errors;
	for (i = 0; i < 512; i = i + 1)
		if (errors < errs0 + 4) check("A read back byte", sec[i], i[7:0] ^ 8'hC3 ^ { 7'd0, i[8] });
	$display("A write + read back LBA 78: %0d errors", errors - errs0);

	// B: the last sector
	io_wr(3'd2, 8'h21);
	command(16'd1439, 2'd1);
	check("B read lba", last_lba, 1439);
	check("B read slot", last_slot, 3);
	read_buf;
	errs0 = errors;
	for (i = 0; i < 512; i = i + 1)
		if (errors < errs0 + 4) check("B read byte", sec[i], dbyte(3, 1439, i));
	$display("B read LBA 1439: %0d errors", errors - errs0);

	// B: format C 0 H 1 (LBA 9..17), 9 sectors of F6
	io_wr(3'd4, 8'h00);
	for (i = 0; i < 512; i = i + 1)
		io_wr(3'd3, 8'hF6);
	io_wr(3'd5, 8'h89);            // 250 kbit/s, 9 sectors
	w0 = mcu_writes;
	for (i = 0; i < 9; i = i + 1)
		command(9 + i, 2'd3);
	check("B format status", rdata, 8'h50);
	check("B format count", mcu_writes - w0, 9);
	check("B format last lba", last_lba, 17);
	check("B format byte", wsec[(wsec_n - 1)*512 + 100], 8'hF6);
	$display("B format C0 H1: %0d sectors written, last LBA %0d", mcu_writes - w0, last_lba);

	// A unmounted: no disk, a read ends with error 3, no request
	mount(3'd2, 64'd0);
	io_wr(3'd2, 8'h10);
	w0 = mcu_reads;
	command(16'd0, 2'd1);
	check("A no disk status", rdata, 8'h03);
	check("A no disk requests", mcu_reads - w0, 0);

	$display("tb_fdd: %0d errors", errors);
	$finish;
end

initial begin
	#200000000;
	$display("ERROR timeout");
	$display("tb_fdd: %0d errors", errors + 1);
	$finish;
end

endmodule
