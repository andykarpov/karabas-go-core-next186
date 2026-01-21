//////////////////////////////////////////////////////////////////////////////////
//
// This file is part of the Next186 Soc PC project
// http://opencores.org/project,next186
//
// Filename: KB_8042.v
// Description: Part of the Next186 SoC PC project, keyboard/mouse PS2 controller
//		Simplified 8042 implementation
// Version 1.0
// Creation date: Jan2013
//
// Author: Nicolae Dumitrache 
// e-mail: ndumitrache@opencores.org
//
// Updated by: Andy Karpov
// Added support for virtual PS/2 keyboard/mouse on karabas go
// 
/////////////////////////////////////////////////////////////////////////////////
// 
// Copyright (C) 2013 Nicolae Dumitrache
// 
// This source file may be used and distributed without 
// restriction provided that this copyright statement is not 
// removed from the file and that any derivative work contains 
// the original copyright notice and the associated disclaimer.
// 
// This source file is free software; you can redistribute it 
// and/or modify it under the terms of the GNU Lesser General 
// Public License as published by the Free Software Foundation;
// either version 2.1 of the License, or (at your option) any 
// later version. 
// 
// This source is distributed in the hope that it will be 
// useful, but WITHOUT ANY WARRANTY; without even the implied 
// warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR 
// PURPOSE. See the GNU Lesser General Public License for more 
// details. 
// 
// You should have received a copy of the GNU Lesser General 
// Public License along with this source; if not, download it 
// from http://www.opencores.org/lgpl.shtml 
// 
///////////////////////////////////////////////////////////////////////////////////
// Additional Comments: 
//
// http://www.computer-engineering.org/ps2keyboard/
// http://wiki.osdev.org/%228042%22_PS/2_Controller
// http://wiki.osdev.org/Mouse_Input
//
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module KB_Mouse_8042(
    input wire CS,
	 input wire WR,
    input wire cmd,			// 0x60 = data, 0x64 = cmd
	 input wire [7:0]din,
	 output wire [7:0]dout, 
	 input wire clk,			// cpu CLK
	 input wire reset,
	 output wire I_KB,		// interrupt keyboard
	 output wire I_MOUSE,  // interrupt mouse
	 output reg CPU_RST = 0,

     // keyboard scancode from rp2040
     input wire [7:0] ps2_kbd_scancode,
     input wire ps2_kbd_scancode_upd,
     input wire [7:0] xt_kbd_scancode,
     input wire xt_kbd_scancode_upd,

     // mouse report from rp2040
     input wire [7:0] ms_x,
     input wire [7:0] ms_y,
     input wire [3:0] ms_z,
     input wire [2:0] ms_b,
     input wire ms_upd,
	  
	  output wire [15:0] ps2_command,
	  output wire ps2_command_wr
    );
	 
	//	status 
	// bit5 = MOBF (mouse to host buffer full - with OBF), 
	// bit4 = INH, 
	// bit2 (1-initialized ok), 
	// bit1 (IBF-input buffer full - host to kb/mouse), 
	// bit0 (OBF-output buffer full - kb/mouse to host)
	
	reg [3:0]cmdbyte = 4'b1100; // EN2,EN,INT2,INT
	reg wcfg = 1'b0;	// write config byte
	reg next_mouse = 1'b0;
	reg ctl_outb = 1'b0;
	reg [7:0]wr_data;
	reg wr_mouse = 1'b0;
	reg wr_kb = 1'b0;
	reg rd_kb = 1'b0;
	reg rd_mouse = 1'b0;
	reg OBF = 1'b0;
	reg MOBF = 1'b0;
	reg [7:0]s_data;

	wire [7:0]kb_data;
	wire [7:0]mouse_data;
	wire kb_data_out_ready;
	wire kb_data_in_ready;
	wire mouse_data_out_ready;
	wire mouse_data_in_ready;
	wire IBF = ((wr_kb | ~kb_data_in_ready) & ~cmdbyte[2]) | ((wr_mouse  | ~mouse_data_in_ready) & ~cmdbyte[3]);
	
	assign dout = cmd ? {2'b00, MOBF, 1'b1, wcfg, 1'b1, IBF, OBF | MOBF | ctl_outb} : 
					  ctl_outb ? {2'b00, cmdbyte[3:2], 2'b00, cmdbyte[1:0]} : s_data; //MOBF ? mouse_data : kb_data;
	assign I_KB = cmdbyte[0] & OBF; 			// INT & OBF
	assign I_MOUSE = cmdbyte[1] & MOBF; 	// INT2 & MOBF

	wire [15:0] ps2_kbd_command;
	wire ps2_kbd_command_wr;
	
	// todo: mux with mouse commands maybe
	assign ps2_command = ps2_kbd_command;
	assign ps2_command_wr = ps2_kbd_command_wr;

    PS2KeyboardInterfaceEmu Keyboard
    (
        .clk(clk),
		  .reset(reset),
        .rd(rd_kb),
        .wr(wr_kb),
        .data_in(wr_data[7:0]),
        .data_out(kb_data),
        .data_out_ready(kb_data_out_ready),
        .data_in_ready(kb_data_in_ready),

        .ps2_scancode(ps2_kbd_scancode),
        .ps2_scancode_upd(ps2_kbd_scancode_upd),
        .xt_scancode(xt_kbd_scancode),
        .xt_scancode_upd(xt_kbd_scancode_upd),

		  .ps2_command(ps2_kbd_command),
		  .ps2_command_wr(ps2_kbd_command_wr)
    );

    PS2MouseInterfaceEmu Mouse
    (
        .clk(clk),
		  .reset(reset),
        .rd(rd_mouse),
        .wr(wr_mouse),
        .data_in(wr_data[7:0]),
        .data_out(mouse_data),
        .data_out_ready(mouse_data_out_ready),
        .data_in_ready(mouse_data_in_ready),

        .ms_x(ms_x),
        .ms_y(ms_y),
        .ms_z(ms_z),
        .ms_b(ms_b),
        .ms_upd(ms_upd)
    );
	
	always @(posedge clk) begin
		CPU_RST <= 0;
		if(~kb_data_in_ready || wr_kb) wr_kb <= 1'b0;
		if(~kb_data_out_ready || rd_kb) begin rd_kb <= 1'b0; OBF <= 1'b0; end // andy
		if(~mouse_data_in_ready || wr_mouse) wr_mouse <= 0;
		if(~mouse_data_out_ready || rd_mouse) begin rd_mouse <= 1'b0; MOBF <= 1'b0; end

		if(~OBF & ~MOBF)
			if(kb_data_out_ready & ~rd_kb & ~cmdbyte[2]) begin
				OBF <= 1'b1;
				s_data <= kb_data;
			end else if(mouse_data_out_ready & ~rd_mouse & ~cmdbyte[3]) begin
				MOBF <= 1'b1;
				s_data <= mouse_data;
			end
		
		if(CS) 
			if(WR)
				if(cmd)	// 0x64 write
					case(din)
						8'h20: ctl_outb <= 1'b1;	// read config byte
						8'h60: wcfg <= 1;			// write config byte
						8'ha7: cmdbyte[3] <= 1;	// disable mouse
						8'ha8: cmdbyte[3] <= 0;	// enable mouse
						8'had: cmdbyte[2] <= 1;	// disable kb
						8'hae: cmdbyte[2] <= 0;	// enable kb
						8'hd4: next_mouse <= 1;	//	write next byte to mouse
						/*8'hf0, 8'hf2, 8'hf4, 8'hf6, 8'hf8, 8'hfa, 8'hfc,*/ 8'hfe: CPU_RST <= 1; // CPU reset
					endcase 
				else begin	// 0x60 write
					if(wcfg) cmdbyte <= {din[5:4], din[1:0]};
					else begin
						next_mouse <= 0;
						wr_mouse <= next_mouse;
						wr_kb <= ~next_mouse;
						wr_data <= din;
					end
					wcfg <= 0;
				end
			else 	// read data
				if(~cmd) begin	
					ctl_outb <= 1'b0;
					if(!ctl_outb) begin
						OBF <= 1'b0;
						MOBF <= 1'b0;
						rd_kb <= OBF;
						rd_mouse <= MOBF;
					end
				end
	end
endmodule

module PS2KeyboardInterfaceEmu(
	 input wire clk,
     input wire reset,
	 input wire rd,				// enable PS2 data reading from keyboard
	 input wire wr,				// can write data from controller to PS2 keyboard
	 input wire [7:0] data_in,		// data from controller
	 output reg [7:0]data_out,	// data from PS2 keyboard
	 output reg data_out_ready = 1,	// PS2 keyboard received data ready
	 output reg data_in_ready = 1,	// PS2 keyboard sent data ready
    input wire [7:0] ps2_scancode,
    input wire ps2_scancode_upd,
	 input wire [7:0] xt_scancode,
	 input wire xt_scancode_upd,
	 
	 output reg [15:0] ps2_command,
	 output reg ps2_command_wr
);

	initial data_in_ready = 1;
	initial data_out_ready = 0;

    localparam S_IDLE=0;
    localparam S_WRITE = 1;
	 localparam S_WRITE_NEXT = 2;
    localparam S_WRITE_DONE = 3;
    localparam S_CLEAR = 4;
    localparam S_CLEAR_DONE = 5;
	 localparam S_READ = 6;
	 localparam S_READ_END = 7;
	 localparam S_READ_DONE = 8;
	 localparam S_TRANSFER_READ = 9;
	 localparam S_TRANSFER_READ_END = 10;
	 localparam S_TRANSFER_WRITE = 11;

	 // incoming fifo
	 wire in_fifo_full, in_fifo_empty;
    wire [7:0] in_fifo_do;
    reg [7:0] in_fifo_di;
    reg in_fifo_rd, in_fifo_wr, in_fifo_clr;
	 fifo1 #(.DATA_WIDTH(8), .ADDR_WIDTH(8)) in_fifo(
		  .clk(clk),
        .reset(in_fifo_clr),
        .rd(in_fifo_rd),
        .wr(in_fifo_wr),
        .din(in_fifo_di),
        .dout(in_fifo_do),
        .full(in_fifo_full),
        .empty(in_fifo_empty)
	 );
	 
	 // fill in fifo with incoming data from rp2040
	 always @(posedge clk)
	 begin
		in_fifo_wr <= 0;
		prev_ps2_scancode_upd <= ps2_scancode_upd;
		prev_xt_scancode_upd <= xt_scancode_upd;
		
		// scancodeset 2
		if (prev_ps2_scancode_upd != ps2_scancode_upd) begin		  
		  if (enabled && (scancodeset == 8'h02) && !in_fifo_full) begin
				in_fifo_wr <= 1;
				in_fifo_di <= ps2_scancode;
		  end 
		end
		// scancodeset 1
		if (prev_xt_scancode_upd != xt_scancode_upd) begin			
			if (enabled && (scancodeset == 8'h01) && !in_fifo_full) begin
				in_fifo_wr <= 1;
				in_fifo_di <= xt_scancode;
			end
		end
	 end

    // fifo for responses, 256 bytes length
    wire fifo_full, fifo_empty;
    wire [7:0] fifo_do;
    reg [7:0] fifo_di;
    reg fifo_rd, fifo_wr, fifo_clr;
    fifo1 #(.DATA_WIDTH(8), .ADDR_WIDTH(8)) fifo(
        .clk(clk),
        .reset(fifo_clr),
        .rd(fifo_rd),
        .wr(fifo_wr),
        .din(fifo_di),
        .dout(fifo_do),
        .full(fifo_full),
        .empty(fifo_empty),
        .data_count()
    );

	 localparam DEFAULT_ENABLED = 1'b1;
	 localparam [7:0] DEFAULT_SCANCODESET = 8'h02;
	 localparam [7:0] DEFAULT_LEDS = 8'h00;
	 localparam [7:0] DEFAULT_TYPEMATIC = 8'b00101100;
	
    reg prev_ps2_scancode_upd, prev_xt_scancode_upd, prev_wr, prev_rd;
    reg enabled = 1'b1;
    reg [3:0] state = S_IDLE;
    reg [2:0] cnt_write = 0;
    reg [23:0] data_write;
	 reg [7:0] last_scancode;
	 reg [7:0] prev_data_in;

	 reg [7:0] scancodeset = DEFAULT_SCANCODESET;
	 reg [7:0] leds = DEFAULT_LEDS;
	 reg [7:0] typematic = DEFAULT_TYPEMATIC;
	 
	 reg poweron = 0;
	 
	 localparam [7:0] CMD_LEDS = 8'hED;
	 localparam [7:0] CMD_ECHO = 8'hEE;
	 localparam [7:0] CMD_SCANCODESET = 8'hF0;
	 localparam [7:0] CMD_ID = 8'hF2;
	 localparam [7:0] CMD_TYPEMATIC = 8'hF3;
	 localparam [7:0] CMD_ENABLE = 8'hF4;
	 localparam [7:0] CMD_DISABLE = 8'hF5;
	 localparam [7:0] CMD_DEFAULTS = 8'hF6;
	 localparam [7:0] CMD_RESEND = 8'hFE;
	 localparam [7:0] CMD_RESET = 8'hFF;
	 
	 localparam [7:0] ACK_BAT = 8'hAA;
	 localparam [7:0] ACK_OK = 8'hFA;
	 localparam [7:0] ACK_ECHO = 8'hEE;
	 localparam [7:0] ACK_RESEND = 8'hFE;

	 task do_write(input reg [2:0] i_cnt, input reg [23:0] i_data, input reg [3:0] i_st);
		begin
			cnt_write <= i_cnt;
			data_write <= i_data;
			state <= i_st;
		end
	 endtask

    always @(posedge clk)
    begin
        prev_wr <= wr;
        prev_rd <= rd;
		  ps2_command_wr <= 0;
		  
		  if (fifo_do != CMD_RESEND) // remember last scancode, except resend
			 last_scancode <= fifo_do;
			 
		  // reset data_out_ready on read end
		  if (rd && ~prev_rd && data_out_ready) begin
			   data_out_ready <= 0;
		  end

		  // write from host - high prio, will cancel other tasks	
		  if (wr && ~prev_wr) begin
			  fifo_rd <= 0; // interrupt previous writes
			  fifo_wr <= 0;
			  fifo_clr <= 0;
			  in_fifo_rd <= 0;
			  in_fifo_clr <= 0;
			  data_in_ready <= 1'b0;
			  data_out_ready <= 1'b0; // also clears the out!
			  prev_data_in <= data_in;
			  case(data_in)
					CMD_LEDS: do_write(1, ACK_OK, S_CLEAR); // set leds (second bytes will write the response)
					CMD_ECHO: begin do_write(1, ACK_ECHO, S_CLEAR); end // set echo
					//8'hEF: do_write(1, ACK_RESEND, S_CLEAR); // invalid
					CMD_SCANCODESET: do_write(1, ACK_OK, S_CLEAR); // set scancodeset (second byte will write the response)
					//8'hF1: do_write(1, ACK_RESEND, S_CLEAR); // invalid
					CMD_ID: do_write(3, {8'h83, 8'hAB, ACK_OK}, S_CLEAR); // kbd id
					CMD_TYPEMATIC: do_write(1, ACK_OK, S_CLEAR); // set typematic and delay
					CMD_ENABLE: begin do_write(1, ACK_OK, S_CLEAR); enabled <= 1'b1; end // enable scanning
					CMD_DISABLE: begin do_write(1, ACK_OK, S_CLEAR); enabled <= 1'b0; end // disabled scanning
					CMD_DEFAULTS: begin do_write(1, ACK_OK, S_CLEAR); ps2_command <= {CMD_DEFAULTS, 8'h00}; ps2_command_wr <= 1; end // set default params
					//8'hF7, 8'hF8, 8'hF9, 8'hFA, 8'hFB, 8'hFC, 8'hFD: do_write(1, ACK_OK, S_CLEAR); // sc3 specific
					//CMD_RESEND: do_write(2, {last_scancode, ACK_OK}, S_CLEAR); // resend
					CMD_RESET: begin // reset + self test: 1 - fifo clr, 2 - response FA, AA
						ps2_command <= {CMD_RESET, 8'h00}; ps2_command_wr <= 1;
						do_write(3'd2, {8'h00, ACK_BAT, ACK_OK}, S_CLEAR); 
						leds <= DEFAULT_LEDS;
						typematic <= DEFAULT_TYPEMATIC;
						scancodeset <= DEFAULT_SCANCODESET;
						enabled <= DEFAULT_ENABLED;
					end 
					default: begin 
						if (prev_data_in == CMD_SCANCODESET) begin // set or get scancodeset byte
							case (data_in)
								8'h01: begin do_write(1, ACK_OK, S_CLEAR); scancodeset<=1; ps2_command <= {CMD_SCANCODESET, 8'h01}; ps2_command_wr <= 1; end // set 1
								8'h02: begin do_write(1, ACK_OK, S_CLEAR); scancodeset<=2; ps2_command <= {CMD_SCANCODESET, 8'h02}; ps2_command_wr <= 1; end // set 2
								8'h03: begin do_write(1, ACK_OK, S_CLEAR); scancodeset<=3; ps2_command <= {CMD_SCANCODESET, 8'h03}; ps2_command_wr <= 1; end // set 3
								default: do_write(2, {scancodeset, ACK_OK}, S_CLEAR); // get
							endcase
						end
						else if (prev_data_in == CMD_LEDS) begin // set leds byte
							ps2_command <= {CMD_LEDS, data_in}; ps2_command_wr <= 1;
							leds <= data_in;
							do_write(1, ACK_OK, S_CLEAR);
						end
						else if (prev_data_in == CMD_TYPEMATIC) begin // set typematic byte
							ps2_command <= {CMD_TYPEMATIC, data_in}; ps2_command_wr <= 1;
							typematic <= data_in;
							do_write(1, ACK_OK, S_CLEAR);
						end
						else begin // response to any other command (unimplemented scancodeset3 related, for example)
							do_write(1, ACK_OK, S_CLEAR);
						end
					end
			  endcase
		 end
		 else case (state)
            S_IDLE: begin

					 // reset fills the initial AA
					 if (!poweron) begin
						poweron <= 1;
						scancodeset <= DEFAULT_SCANCODESET;
						enabled <= DEFAULT_ENABLED;
						typematic <= DEFAULT_TYPEMATIC;
						leds <= DEFAULT_LEDS;
						data_in_ready <= 1'b0;
						do_write(1, ACK_BAT, S_CLEAR);
						ps2_command <= {CMD_DEFAULTS, 8'h00}; ps2_command_wr <= 1;
					 end

					 // prepare byte to read
					 else if (~fifo_empty && ~data_out_ready) begin
						 state <= S_READ;
					 end
					 
					 // transfer from incoming fifo to out fifo
					 else if (~in_fifo_empty && ~fifo_full) begin
						data_in_ready <= 0;
						state <= S_TRANSFER_READ;
					 end
            end
				
				S_TRANSFER_READ: begin
					in_fifo_rd <= 1'b1;
					state <= S_TRANSFER_READ_END;
				end
				
				S_TRANSFER_READ_END: begin
					in_fifo_rd <= 1'b0;
					state <= S_TRANSFER_WRITE;
				end
				
				S_TRANSFER_WRITE: begin
					do_write(1, in_fifo_do, S_WRITE);
				end
				
				S_READ: begin
					fifo_rd <= 1'b1;
					state <= S_READ_END;
				end
				
				S_READ_END: begin
					fifo_rd <= 1'b0;	
					state <= S_READ_DONE;
				end
				
				S_READ_DONE: begin
					data_out <= fifo_do;
					data_out_ready <= 1;
					state <= S_IDLE;
				end

            S_WRITE: begin
                fifo_di <= data_write[7:0];
                fifo_wr <= 1'b1;
                state <= S_WRITE_NEXT;
            end
				
				S_WRITE_NEXT: begin
					fifo_wr <= 1'b0;
					if (cnt_write > 1) begin
                    cnt_write <= cnt_write - 1;
                    data_write <= {8'h00, data_write[23:8]}; // shift data_write for next write
                    state <= S_WRITE;
                end 
                else
                    state <= S_WRITE_DONE;
				end

            S_WRITE_DONE: begin
					 fifo_wr <= 1'b0;
                data_in_ready <= 1;
                state <= S_IDLE;
            end

            S_CLEAR: begin
                fifo_clr <= 1;
					 in_fifo_clr <= 1;
                state <= S_CLEAR_DONE;                
            end

            S_CLEAR_DONE: begin
					fifo_clr <= 0;
					in_fifo_clr <= 0;
               state <= S_WRITE;
            end
				
				default:
					state <= S_IDLE;
			endcase
    end

endmodule

module PS2MouseInterfaceEmu(
    input wire clk,
    input wire reset,
    input wire rd,				// enable PS2 data reading from mouse
    input wire wr,				// can write data from controller to PS2 mouse
    input wire [7:0] data_in,		// data from controller
    output reg [7:0]data_out,	// data from PS2 mouse
    output reg data_out_ready = 0,	// PS2 mouse received data ready
    output reg data_in_ready = 1,	// PS2 mouse sent data ready

    input wire [7:0] ms_x,
    input wire [7:0] ms_y,
    input wire [3:0] ms_z,
    input wire [2:0] ms_b,
    input wire ms_upd,
	 
	 output reg [15:0] ps2_command,
	 output reg ps2_command_wr = 0
);

	initial data_in_ready = 1;
	initial data_out_ready = 0;
	
	// global mouse state
	reg signed [31:0] x = 0;
	reg signed [31:0] y = 0;
	reg signed [31:0] z = 0;
	reg [2:0] b = 3'b0;

    localparam S_IDLE=0;
    localparam S_WRITE = 1;
	 localparam S_WRITE_NEXT = 2;
    localparam S_WRITE_DONE = 3;
    localparam S_CLEAR = 4;
    localparam S_CLEAR_DONE = 5;
	 localparam S_READ = 6;
	 localparam S_READ_END = 7;
	 localparam S_READ_DONE = 8;
	 localparam S_TRANSFER_READ = 9;
	 localparam S_TRANSFER_READ_END = 10;
	 localparam S_TRANSFER_WRITE = 11;
	 
	 // fill incoming data from rp2040 to globals x,y,b
	 reg prev_ms_upd = 0;
	 always @(posedge clk)
	 begin
		if (prev_ms_upd != ms_upd) begin
		  x <= x + $signed(ms_x);
		  y <= y - $signed(ms_y);
		  z <= z + $signed(ms_z);
		  b <= ms_b;
		end
		prev_ms_upd <= ms_upd;
	end

    // fifo for responses, 256 bytes length
    wire fifo_full, fifo_empty;
    wire [7:0] fifo_do;
    reg [7:0] fifo_di;
    reg fifo_wr, fifo_clr;
	 reg fifo_rd;
    fifo1 #(.DATA_WIDTH(8), .ADDR_WIDTH(8)) fifo(
        .clk(clk),
        .reset(fifo_clr),
        .rd(fifo_rd),
        .wr(fifo_wr),
        .din(fifo_di),
        .dout(fifo_do),
        .full(fifo_full),
        .empty(fifo_empty),
        .data_count()
    );
	 
	 localparam DEFAULT_ENABLED = 1'b0;
	 localparam DEFAULT_REMOTE = 1'b0;
	 localparam [7:0] DEFAULT_SCALING = 8'h01;
	 localparam [7:0] DEFAULT_RESOLUTION = 8'h02;
	 localparam [7:0] DEFAULT_SAMPLERATE = 100;
	 localparam [31:0] CPU_FREQ = 50; // 50 MHz
	 reg [31:0] samplerate_pulses;
	 
    reg prev_wr, prev_rd;
    reg enabled = DEFAULT_ENABLED;
    reg remote = DEFAULT_REMOTE;
    reg [3:0] state = S_IDLE;
    reg [2:0] cnt_write = 0;
    reg [31:0] data_write;
	 reg [7:0] scaling = DEFAULT_SCALING;
	 reg [7:0] resolution = DEFAULT_RESOLUTION;
	 reg [7:0] mode = 0;
	 reg [7:0] wrap = 0;
	 reg [7:0] samplerate = DEFAULT_SAMPLERATE;
	 reg [7:0] prev_data_in;
	 reg poweron = 0;
	 reg [31:0] samplerate_cnt = 0;
    
	 // todo: https://isdaman.com/alsos/hardware/mouse/ps2interface.htm
	 // todo: add support for 4 byte report (z axis) https://wiki.osdev.org/PS/2_Mouse
	 // - remember last 3 resolutions reg [23:0] last_resolutions
	 // - when asking for mouse id, if resolutions are 200,100,80 (magic sequence) 
	 // - response with 0x03 instead of 0x00 as ID and 
	 // - then send 4-bytes reports
	 
    reg [23:0] mouse_packet, prev_mouse_packet;
	 reg signed [31:0] prev_x, prev_y, prev_z;
	 wire signed [31:0] dx, dy, dz;
	 assign dx = x - prev_x; // dx
	 assign dy = y - prev_y; // dy
	 assign dz = z - prev_z; // dz
	 wire dxo = (dx[31:8] != {24{dx[31]}}); // dx overflow
	 wire dyo = (dx[31:8] != {24{dy[31]}}); // dy overflow
	 reg [2:0] prev_b;
	 wire [23:0] mouse_status = {samplerate, 
										  resolution, 
										  {1'b0, remote, enabled, ~scaling[0], 1'b0, b}};

	 localparam [7:0] CMD_SET_SCALING1 = 8'hE6;
	 localparam [7:0] CMD_SET_SCALING2 = 8'hE7;
	 localparam [7:0] CMD_SET_RESOLUTION = 8'hE8;
	 localparam [7:0] CMD_GET_STATUS = 8'hE9;
	 localparam [7:0] CMD_SET_STREAMING = 8'hEA;
	 localparam [7:0] CMD_GET_PACKET = 8'hEB;	 
	 localparam [7:0] CMD_RESET_WRAP = 8'hEC;	 
	 localparam [7:0] CMD_SET_WRAP = 8'hEE;	 
	 localparam [7:0] CMD_SET_REMOTE = 8'hF0;	 
	 localparam [7:0] CMD_GET_ID = 8'hF2;	 
	 localparam [7:0] CMD_SET_SAMPLERATE = 8'hF3;	 
	 localparam [7:0] CMD_SET_ENABLED = 8'hF4;	 
	 localparam [7:0] CMD_SET_DISABLED = 8'hF5;	 
	 localparam [7:0] CMD_SET_DEFAULTS = 8'hF6;
	 localparam [7:0] CMD_RESEND = 8'hFE;	 
	 localparam [7:0] CMD_RESET = 8'hFF;	 
	 
	 localparam [7:0] ACK_BAT = 8'hAA;
	 localparam [7:0] ACK_OK = 8'hFA;
	 localparam [7:0] ACK_ECHO = 8'hEE;
	 localparam [7:0] ACK_RESEND = 8'hFE;

	 task do_write(input reg [2:0] i_cnt, input reg [31:0] i_data, input reg [3:0] i_st);
		begin
			cnt_write <= i_cnt;
			data_write <= i_data;
			state <= i_st;
		end
	 endtask

    always @(posedge clk)
    begin
        prev_wr <= wr;
        prev_rd <= rd;
		  ps2_command_wr <= 0;
		  
		  // samplerate counter
		  if (samplerate > 0) begin
			  samplerate_pulses <= CPU_FREQ * 1000000 / samplerate;
			  samplerate_cnt <= samplerate_cnt + 1;
		  end
		  
		  // reset data_out_ready on read
		  if (rd && ~prev_rd && data_out_ready) begin
			   data_out_ready <= 0;
		  end	
		  
		  // react on writes (high priority, out of FSM)
		  if (wr && ~prev_wr) begin
			  fifo_rd <= 0; // interrupt previous writes
			  fifo_wr <= 0;
			  fifo_clr <= 0;
			  data_in_ready <= 1'b0;
			  data_out_ready <= 1'b0; // also clears the out!
			  prev_data_in <= data_in;
			  case(data_in)
					CMD_SET_SCALING1: begin do_write(1, 8'hFA, S_CLEAR); scaling <= 1; ps2_command <= {CMD_SET_SCALING1, 8'h00}; ps2_command_wr <= 1; end // set scaling 1:1
					CMD_SET_SCALING2: begin do_write(1, 8'hFA, S_CLEAR); scaling <= 2; ps2_command <= {CMD_SET_SCALING2, 8'h00}; ps2_command_wr <= 1; end // set scaling 2:1
					CMD_SET_RESOLUTION: begin do_write(1, 8'hFA, S_CLEAR); end // set resolution (in next byte)
					CMD_GET_STATUS: begin do_write(4, {mouse_status, 8'hFA}, S_CLEAR); end // status request
					CMD_SET_STREAMING: begin do_write(1, 8'hFA, S_CLEAR); remote <= 1'b0; end // set default streaming mode
					CMD_GET_PACKET: begin do_write(4, {mouse_packet, 8'hFA}, S_CLEAR); end // request one packet
					CMD_RESET_WRAP: begin do_write(1, 8'hFA, S_CLEAR); wrap <= 1'b0; end // reset wrap mode
					CMD_SET_WRAP: begin do_write(1, 8'hFA, S_CLEAR); wrap <= 1'b1; end // set wrap mode
					CMD_SET_REMOTE: begin do_write(1, 8'hFA, S_CLEAR); remote <= 1'b1; end // set remote mode
					CMD_GET_ID: begin do_write(2, {8'h00, 8'hFA}, S_CLEAR); end // identify + 2 bytes 0x00, 0x00
					CMD_SET_SAMPLERATE: begin do_write(1, 8'hFA, S_CLEAR); end // set samplerate (in next byte)
					CMD_SET_ENABLED: begin do_write(1, 8'hFA, S_CLEAR); enabled <= 1'b1; end // enable reporting
					CMD_SET_DISABLED: begin do_write(1, 8'hFA, S_CLEAR); enabled <= 1'b0; end // disabled reporting
					CMD_SET_DEFAULTS: begin do_write(1, 8'hFA, S_CLEAR); enabled <= DEFAULT_ENABLED; scaling <= DEFAULT_SCALING; resolution <= DEFAULT_RESOLUTION; samplerate <= DEFAULT_SAMPLERATE; ps2_command <= {CMD_SET_DEFAULTS, 8'h00}; ps2_command_wr <= 1; end // set default params - todo!
					//CMD_RESEND: begin do_write(1, 8'hFA, S_CLEAR); end // resend
					CMD_RESET: begin do_write(3, {8'h00, 8'hAA, 8'hFA}, S_CLEAR); enabled <= DEFAULT_ENABLED; scaling <= DEFAULT_SCALING; resolution <= DEFAULT_RESOLUTION; samplerate <= DEFAULT_SAMPLERATE; ps2_command <= {CMD_SET_DEFAULTS, 8'h00}; ps2_command_wr <= 1; end // reset: 1 - fifo clr, 2 - response AA, 0x00
					default: begin 
						if (prev_data_in == CMD_SET_RESOLUTION) begin // set resolution
							ps2_command <= {CMD_SET_RESOLUTION, data_in}; ps2_command_wr <= 1;
							resolution <= data_in;
							do_write(1, 8'hFA, S_CLEAR);
						end
						else if (prev_data_in == CMD_SET_SAMPLERATE) begin // set samplerate
							ps2_command <= {CMD_SET_SAMPLERATE, data_in}; ps2_command_wr <= 1;
							samplerate <= data_in;
							do_write(1, 8'hFA, S_CLEAR);
						end
						else begin // response to any other command
							do_write(1, 8'hFA, S_CLEAR);
						end
					end
			  endcase
		 end 
		 else case (state)
            S_IDLE: begin

					 // reset fills the initial AA
					 if (!poweron) begin
						poweron <= 1;
						data_in_ready <= 1'b0;
						do_write(1, 8'hAA, S_CLEAR);
					 end

					 // prepare byte to read
					 else if (~fifo_empty && ~data_out_ready) begin
						 state <= S_READ;
					 end
					 
					 // prepare new mouse packet
					 else if ((samplerate_cnt >= samplerate_pulses)) begin
						samplerate_cnt <= 0;
						prev_x <= x;
						prev_y <= y;
						prev_z <= z;
						prev_b <= b;
						mouse_packet <= {dy[7:0], dx[7:0], dyo, dxo, dy[31], dx[31], 1'b1, b[2:0]};
						if (enabled && (mouse_packet != prev_mouse_packet)) begin // write new packet to the fifo
							data_in_ready <= 1'b0;
							do_write(3, mouse_packet, S_WRITE);
						end
						prev_mouse_packet <= mouse_packet;
					 end
            end

				S_READ: begin
					fifo_rd <= 1'b1;
					state <= S_READ_END;
				end
				
				S_READ_END: begin
					fifo_rd <= 1'b0;
					state <= S_READ_DONE;
				end
				
				S_READ_DONE: begin
					data_out <= fifo_do;
					data_out_ready <= 1;
					state <= S_IDLE;
				end

            S_WRITE: begin
                fifo_di <= data_write[7:0];
                fifo_wr <= 1'b1;
					 state <= S_WRITE_NEXT;
            end
				
				S_WRITE_NEXT: begin
					fifo_wr <= 1'b0;
                if (cnt_write > 1) begin
                    cnt_write <= cnt_write - 1;
                    data_write <= {8'h00, data_write[31:8]};
                    state <= S_WRITE;
                end 
                else
                    state <= S_WRITE_DONE;
				end

            S_WRITE_DONE: begin
					 fifo_wr <= 1'b0;
                data_in_ready <= 1;
                state <= S_IDLE;
            end

            S_CLEAR: begin
                fifo_clr <= 1;
                state <= S_CLEAR_DONE;                
            end

            S_CLEAR_DONE: begin
					 fifo_clr <= 0;
                state <= S_WRITE;
            end
				
				default: state <= S_IDLE;
			endcase
    end

endmodule

