`timescale 1ns / 1ps
`default_nettype none
//////////////////////////////////////////////////////////////////////////////////
//
// This file is part of the Next186 Soc PC project
// http://opencores.org/project,next186
//
// Filename: sound_gen.v
// Description: Part of the Next186 SoC PC project, 
//		stereo 2x16bit pulse density modulated sound generator
// 	44100 samples/sec
//		Disney Sound Source and Covox Speech compatible
// Version 1.0
// Creation date: Jan2015
//
// Author: Nicolae Dumitrache 
// e-mail: ndumitrache@opencores.org
//
/////////////////////////////////////////////////////////////////////////////////
// 
// Copyright (C) 2015 Nicolae Dumitrache
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
//////////////////////////////////////////////////////////////////////////////////
// Additional Comments: 
//
//	byte write: both channels are the same (Covox emulation), the 8bit sample value is shifted by 8, the channel selector is reset to LEFT
// word write: LEFT first, the queue is updated only after RIGHT value is written
// sample rate: 44100Hz
//////////////////////////////////////////////////////////////////////////////////
`define SPKVOL	11

module soundwave(
		input wire CLK,
		input wire clk_en,
		input wire [15:0]data,
		input wire we,
		input wire word,
		input wire speaker,
		input wire [15:0]cdda_l,
		input wire [15:0]cdda_r,
        input wire [23:0] adc_l,
        input wire [23:0] adc_r,
		input wire [15:0]opl3left,
		input wire [15:0]opl3right,
		input wire [7:0]tandy_snd,
		output wire full,	// when not full, write max 2x1152 16bit samples
		output wire dss_full,
		output reg [15:0] laudio,
		output reg [15:0] raudio,
		output reg AUDIO_L,
		output reg AUDIO_R
	);

	reg [31:0]wdata;
	reg lr = 1'b0;
	reg [2:0]write = 3'b000;
	wire qempty;
	wire [31:0]sample;
	wire [31:0]sample1 = qempty ? 32'hc000c000 : sample;
	reg [31:0]lval = 0; 
	reg [31:0]rval = 0;
	reg [15:0]r_opl3left = 0;
	reg [15:0]r_opl3right = 0;

	wire signed [15:0] lmix = $signed(adc_l[23:8]) + $signed(cdda_l) + $signed(sample1[15:0]) + $signed(r_opl3left) + $signed({tandy_snd, 6'd0}) + $signed(speaker << `SPKVOL); // signed mixer left
	wire signed [15:0] rmix = $signed(adc_r[23:8]) + $signed(cdda_r) + $signed(sample1[31:16]) + $signed(r_opl3right) + $signed({tandy_snd, 6'd0}) + $signed(speaker << `SPKVOL); // signed mixer right

	always @(posedge CLK)
	begin
		r_opl3left <= opl3left;
		r_opl3right <= opl3right;
		laudio <= lmix;
		raudio <= rmix;
	end
	
	// pwm dac
	dac dac_l(
		.I_CLK			(CLK),
		.I_RESET			(1'b0),
		.I_DATA			(laudio),
		.O_DAC			(AUDIO_L)
	);

	dac dac_r(
		.I_CLK			(CLK),
		.I_RESET			(1'b0),
		.I_DATA			(raudio),
		.O_DAC			(AUDIO_R)
	);	

	wire [11:0]wrusedw;
	wire [11:0]rdusedw;
	assign full = wrusedw >= 12'd2940;
	assign dss_full = rdusedw > 12'd90;	// Disney sound source queue full

	sndfifo sndfifo_inst 
	(
		.wr_clk(CLK), // input wr_clk
		.rd_clk(CLK), // input rd_clk
		.din(wdata), // input [31 : 0] din
		.wr_en(|write), // input wr_en
		.rd_en(clk_en), // input rd_en
		.dout(sample), // output [31 : 0] dout
		.wr_data_count(wrusedw),
		.rd_data_count(rdusedw),
		.empty(qempty) // output empty
	);

	always @(posedge CLK) begin
		if(we) 
			if(word) begin
				lr <= !lr;
				write <= {2'b00, lr};
				if(lr) wdata[31:16] <= data;
				else wdata[15:0] <= data;
			end else begin
				lr <= 1'b0;		// left
				write <= 3'b110;
				wdata <= {1'b1, data[7:0], 8'b00000001, data[7:0], 7'b0000000};
			end
		else write <= write - |write;
	end


endmodule
