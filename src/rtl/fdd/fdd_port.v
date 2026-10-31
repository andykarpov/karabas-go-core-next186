`timescale 1ns / 1ns
`default_nettype wire

/*
 fdd_port.v

 The floppy drives A and B of Next186: a sector port for the BIOS (INT 13h, DL 0 / 1), not a 765
 (the SoC has no DMA, so nothing but the BIOS could use a 765). The disks are the slots 2 (A) and
 3 (B) of the mcu file mounter (img_sdc), or (PHYS, Karabas Go) a physical drive of the floppy
 connector when the mcu maps the slot to one (CMD_IMG_PHYS), through pcxt_fdd_phys
 (karabas-go-core-pcxt) with the sector buffer here.

 Registers (a = port - 3F0h, one clock per access, the read data in that clock):
   0 R  status of the selected drive: 7 busy, 6 two heads, 5 write protected, 4 a disk is there,
        1..0 the error of the last command: 0 none, 1 sector not found, 2 data error (CRC, or a
        sector the mcu could not read / write), 3 no disk; 3 a physical drive is probed (its
        disk and geometry not known yet: after its motor came on with no disk there, after an
        error 1 / 3 that may be a disk change, the Go has no change line), wait for it
   0 W  LBA 7..0                1 W  LBA 15..8
   1 R  sectors per track       2 R  cylinders
   2 W  control: 0 the selected drive, 4 motor A, 5 motor B (a physical drive: selected while
        its motor is on, the motor line is shared)
   3 RW the sector buffer: the byte at the pointer, the pointer goes on (0..511, wraps)
   4 W  command: 1 read the sector LBA of the selected drive into the buffer, 2 write the buffer
        to it, 3 format (an image: as write; a physical drive: the track of it, at its first
        sector, with the sectors per track and the rate of register 5, the buffer as the data;
        the other sectors of the track only end); 0 only sets the pointer to 0. A command sets
        the pointer to 0 and busy until it is done
   5 W  format: 7..6 data rate (0 500, 1 300, 2 250 kbit/s, 3 1M), 5..0 sectors per track
 The geometry of an image comes from its size (160K .. 1.44M, 2.88M), of a physical disk from
 the probe of pcxt_fdd_phys.
*/

module fdd_port #(
	parameter PHYS = 0
) (
	input wire clk,
	input wire reset,

	// the CPU: one clock per access
	input wire cs,
	input wire we,
	input wire [2:0] a,
	input wire [7:0] din,
	output wire [7:0] dout,

	// img_sdc, slots 2 (A) and 3 (B); busy / done / bytes only with the slot of one of them
	input wire [1:0] img_mounted,
	input wire [63:0] img_size,
	output reg [1:0] sdc_rd = 2'b00,
	output reg [1:0] sdc_wr = 2'b00,
	output wire [31:0] sdc_sector,
	input wire sdc_busy,
	input wire sdc_done,
	input wire sdc_error,
	input wire sdc_byte_in_strobe,
	input wire [8:0] sdc_byte_addr,
	input wire [7:0] sdc_byte_in_data,
	output wire [7:0] sdc_byte_out_data,

	// PHYS: CMD_IMG_PHYS of kg_mcu, the floppy pins (see pcxt_fdd_phys)
	input wire img_phys_wr,
	input wire [15:0] img_phys,
	input wire [3:0] fdd_in,
	output wire [7:0] fdd_out
);

localparam S_IDLE  = 3'd0;
localparam S_START = 3'd1;
localparam S_RD    = 3'd2;  // read: the request to img_sdc
localparam S_RDATA = 3'd3;  // read: the bytes into the buffer until sdc_done
localparam S_WR    = 3'd4;  // write: the request to img_sdc
localparam S_WWAIT = 3'd5;  // write: the buffer to img_sdc until sdc_done
localparam S_PWAIT = 3'd6;  // PHYS: the op

reg [2:0] state = S_IDLE;
reg [15:0] lba = 16'd0;
reg drv = 1'b0;
reg [1:0] motor = 2'b00;
reg [5:0] fmt_spt = 6'd18;
reg [1:0] fmt_rate = 2'd0;
reg [1:0] op = 2'd0;
reg [1:0] err = 2'd0;
reg busy = 1'b0;
reg [8:0] ptr = 9'd0;
reg [15:0] secs0 = 16'd0, secs1 = 16'd0;

// the physical drives
reg [1:0] map0 = 2'd0, map1 = 2'd0;  // A / B: 0 an image, 1 DS0, 2 DS1
reg [1:0] probe = 2'b00;
reg op_go = 1'b0;
reg p_on = 1'b0;                     // an op owns the buffer
wire op_done;
wire [1:0] op_err;
wire geo_present, geo_probe, geo_wp;
wire [7:0] geo_cyl, geo_spt;
wire [1:0] geo_heads;
wire ph_we;
wire [8:0] ph_a;
wire [7:0] ph_wd;
wire phys_d = PHYS && ((drv ? map1 : map0) != 2'd0);

// the sector buffer: one write port, one synchronous read port
reg [7:0] buffer [0:511];
reg [7:0] buf_q = 8'd0;
wire cpu_wr_data = cs && we && a == 3'd3;
wire cpu_rd_data = cs && !we && a == 3'd3;
wire [8:0] buf_ra = p_on ? ph_a : (state == S_WR || state == S_WWAIT) ? sdc_byte_addr : ptr;
always @(posedge clk) begin
	if (state == S_RDATA && sdc_byte_in_strobe)
		buffer[sdc_byte_addr] <= sdc_byte_in_data;
	else if (p_on && ph_we)
		buffer[ph_a] <= ph_wd;
	else if (cpu_wr_data)
		buffer[ptr] <= din;
	buf_q <= buffer[buf_ra];
end
assign sdc_byte_out_data = buf_q;
assign sdc_sector = {16'd0, lba};

generate if (PHYS) begin : g_phys
	pcxt_fdd_phys u_phys(
		.clk(clk),
		.reset(reset),
		.map0(map0),
		.map1(map1),
		.probe(probe),
		.dor_motor(motor),
		.dor_drive(drv),
		.op_go(op_go),
		.op_kind(op),
		.op_n(drv),
		.op_lba(lba),
		.op_spt(fmt_spt),
		.op_rate(fmt_rate),
		.op_done(op_done),
		.op_err(op_err),
		.geo_upd(),
		.geo_n(drv),
		.geo_present(geo_present),
		.geo_probe(geo_probe),
		.geo_wp(geo_wp),
		.geo_cyl(geo_cyl),
		.geo_spt(geo_spt),
		.geo_secs(),
		.geo_heads(geo_heads),
		.buf_we(ph_we),
		.buf_a(ph_a),
		.buf_wd(ph_wd),
		.buf_q(buf_q),
		.fdd_in(fdd_in),
		.fdd_out(fdd_out),
		.dbg_sel(3'd0),
		.dbg_word()
	);
end else begin : g_no_phys
	assign op_done = 1'b0;
	assign op_err = 2'd0;
	assign geo_present = 1'b0;
	assign geo_probe = 1'b0;
	assign geo_wp = 1'b0;
	assign geo_cyl = 8'd0;
	assign geo_spt = 8'd0;
	assign geo_heads = 2'd0;
	assign ph_we = 1'b0;
	assign ph_a = 9'd0;
	assign ph_wd = 8'd0;
	assign fdd_out = 8'h00;
end endgenerate

// sectors of an image: its size up to 32 MB, else as large
function [15:0] secs_of;
	input [63:0] size;
	secs_of = (size[63:25] != 39'd0) ? 16'hFFFF : size[24:9];
endfunction

// the geometry of the selected drive (an image: 160K 40/8/1, 180K 40/9/1, 320K 40/8/2, 360K
// 40/9/2, 720K 80/9/2, 1.2M 80/15/2, 1.44M 80/18/2, larger 80/36/2, the next larger one for
// sizes between)
wire [15:0] secs = drv ? secs1 : secs0;
wire [7:0] img_cyl = (secs <= 16'd720) ? 8'd40 : 8'd80;
wire [7:0] img_spt =
	(secs <= 16'd320) ? 8'd8 : (secs <= 16'd360) ? 8'd9 : (secs <= 16'd640) ? 8'd8 :
	(secs <= 16'd720) ? 8'd9 : (secs <= 16'd1440) ? 8'd9 : (secs <= 16'd2400) ? 8'd15 :
	(secs <= 16'd2880) ? 8'd18 : 8'd36;
wire img_2h = (secs > 16'd360);
wire present = phys_d ? geo_present : (secs != 16'd0);
wire wp = phys_d & geo_wp;
wire heads2 = phys_d ? (geo_heads == 2'd2) : img_2h;
wire [7:0] spt = phys_d ? geo_spt : img_spt;
wire [7:0] cyl = phys_d ? geo_cyl : img_cyl;

assign dout =
	(a == 3'd0) ? { busy, heads2, wp, present, phys_d & geo_probe, 1'b0, err } :
	(a == 3'd1) ? spt :
	(a == 3'd2) ? cyl :
	(a == 3'd3) ? buf_q :
	8'h00;

always @(posedge clk) begin
	op_go <= 1'b0;
	probe <= 2'b00;

	// the CPU (the data port and the command only while not busy)
	if (cs && we)
		case (a)
			3'd0: lba[7:0] <= din;
			3'd1: lba[15:8] <= din;
			3'd2: begin drv <= din[0]; motor <= din[5:4]; end
			3'd5: begin fmt_rate <= din[7:6]; fmt_spt <= din[5:0]; end
			default: ;
		endcase
	if ((cpu_rd_data || cpu_wr_data) && !busy)
		ptr <= ptr + 9'd1;

	if (reset) begin
		state <= S_IDLE;
		busy <= 1'b0;
		sdc_rd <= 2'b00;
		sdc_wr <= 2'b00;
		p_on <= 1'b0;
	end
	else case (state)
		S_IDLE:
			if (cs && we && a == 3'd4) begin
				ptr <= 9'd0;
				if (din[1:0] != 2'd0) begin
					op <= din[1:0];
					err <= 2'd0;
					busy <= 1'b1;
					state <= S_START;
				end
			end

		S_START:
			if (phys_d) begin
				op_go <= 1'b1;
				p_on <= 1'b1;
				state <= S_PWAIT;
			end
			else if (!present) begin
				err <= 2'd3;
				busy <= 1'b0;
				state <= S_IDLE;
			end
			else
				state <= (op == 2'd1) ? S_RD : S_WR;

		S_RD: begin
			sdc_rd[drv] <= 1'b1;
			if (sdc_busy) begin
				sdc_rd <= 2'b00;
				state <= S_RDATA;
			end
		end

		S_WR: begin
			sdc_wr[drv] <= 1'b1;
			if (sdc_busy) begin
				sdc_wr <= 2'b00;
				state <= S_WWAIT;
			end
		end

		S_RDATA, S_WWAIT:
			if (sdc_done) begin
				if (sdc_error)
					err <= 2'd2;
				busy <= 1'b0;
				state <= S_IDLE;
			end

		S_PWAIT:
			if (op_done) begin
				err <= op_err;
				p_on <= 1'b0;
				busy <= 1'b0;
				state <= S_IDLE;
			end

		default: state <= S_IDLE;
	endcase

	if (img_mounted[0]) begin
		secs0 <= secs_of(img_size);
		map0 <= 2'd0;
	end
	if (img_mounted[1]) begin
		secs1 <= secs_of(img_size);
		map1 <= 2'd0;
	end
	// PHYS: a slot on a physical drive, its probe
	if (PHYS && img_phys_wr && img_phys[15:9] == 7'd1 && img_phys[1:0] != 2'd0) begin
		if (img_phys[8]) map1 <= img_phys[1:0]; else map0 <= img_phys[1:0];
		if (img_phys[8]) probe[1] <= 1'b1; else probe[0] <= 1'b1;
	end
end

endmodule
