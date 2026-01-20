//`default_nettype none

module hdmi_frame(

	input wire clk_rgb,
	input wire clk_vga,
	input wire reset, 

	// input video
	input wire [17:0] rgb,
	input wire hs,
	input wire vs,
	input wire vmode, // 1 = 640x480, 0 = 640x400

	// output video
	output wire [23:0] hdmi_rgb,
	output wire hdmi_hs,
	output wire hdmi_vs,
	output wire hdmi_blank,
	
	// debug
	output wire [10:0] width,
	output wire [10:0] height
);

localparam [10:0] hoff = 144;
localparam [10:0] voff_480 = 30;
localparam [10:0] voff_400 = 34;

// clk_hdmi
wire clk_hdmi = clk_vga;

// 640x480 vmode (vmode=1)
// ModeLine "640x480" 25.175 640 656 752 800 480 490 492 525 -HSync -VSync
// 640 656+17 752+17 800  480 490 492 520 - next186 values

// 640x400 vmode (vmode=0)
// Modeline "640x400" 25.175 640 656 752 800 400 412 414 449 -HSync +VSync
// 640 656+17 752+17 800  400 412 413 446 - next186 values

wire vmode_width = 640;
wire vmode_height = (vmode) ? 480 : 400;
wire hsp = hs; // incoming hs is positive for all resolutions from the vga module
wire vsp = vs; // incoming vs is positive for all resolutions from the vga module
wire [10:0] vmode_hoff = (vmode) ? hoff : hoff;
wire [10:0] vmode_voff = (vmode) ? voff_480 : voff_400;

reg prev_hsp, prev_vsp;
reg [10:0] hcnt, vcnt;
reg [10:0] htotal, vtotal;
always @(posedge clk_rgb, posedge reset)
begin
	if (reset) begin
		hcnt <= 11'd0;
		vcnt <= 11'd0;
		prev_hsp <= 1'b0;
		prev_vsp <= 1'b0;
		htotal <= 11'd0;
		vtotal <= 11'd0;
	end else begin
		prev_hsp <= hsp;
		if (hsp && ~prev_hsp) begin
			htotal <= hcnt;
			hcnt <= 0;
			prev_vsp <= vsp;
			if (vsp && prev_vsp) begin
				vtotal <= vcnt;
				vcnt <= 0;
			end
			else
				vcnt <= vcnt + 1;
		end
		else
			hcnt <= hcnt + 1;	
	end
end
assign width = htotal;
assign height = vtotal;

// hdmi blank
wire h_blank = (hcnt < vmode_hoff) || (hcnt >= vmode_width+vmode_hoff);
wire v_blank = (vcnt < vmode_voff) || (vcnt >= vmode_height+vmode_voff);
assign hdmi_blank = h_blank || v_blank;
wire rgb_active = ~hdmi_blank;

// hdmi sync
assign hdmi_hs = ~((hcnt >= 0) && (hcnt <= 96)); // negative for 640x480 and 640x400
assign hdmi_vs = (vmode) ? ~((vcnt >= 0) && (vcnt <= 6)) : ((vcnt >= 0) && (vcnt <= 1)); // neg 640x480 / pos 640x400

// output
assign hdmi_rgb = {rgb[17:12], 2'b0,  
						 rgb[11:6], 2'b0,  
						 rgb[5:0], 2'b0}; 

//				{rgb_raw[17:12], 2'b0,  
//				 rgb_raw[11:6], 2'b0,  
//				 rgb_raw[5:0], 2'b0}; 

endmodule
