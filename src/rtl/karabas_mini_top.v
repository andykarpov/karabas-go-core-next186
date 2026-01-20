`timescale 1ns / 1ns
`default_nettype none

// bios loader experiment. 
// also needs to be switched in cache conctoller!!!
`define BIOS_LOADER

/*-------------------------------------------------------------------------------------------------------------------
-- 
-- 
-- #       #######                                                 #                                               
-- #                                                               #                                               
-- #                                                               #                                               
-- ############### ############### ############### ############### ############### ############### ############### 
-- #             #               # #                             # #             #               # #               
-- #             # ############### #               ############### #             # ############### ############### 
-- #             # #             # #               #             # #             # #             #               # 
-- #             # ############### #               ############### ############### ############### ############### 
--                                                                                                                 
--         ####### ####### ####### #######                                         ############### ############### 
--                                                                                 #               #             # 
--                                                                                 #   ########### #             # 
--                                                                                 #             # #             # 
-- https://github.com/andykarpov/karabas-go                                        ############### ############### 
--
-- FPGA Next186 SoC core for Karabas-Go Mini
--
-- @author Andy Karpov <andy.karpov@gmail.com>
-- EU, 2026
--
-- TODO: midi tx (mpu401 ?), midi clk + ацп
-- TODO: HDD (CF) вместо SD
-- TODO: SRAM заюзать
-- TODO: UART - connect to USB uart or ESP8266
-- TODO: GPIO - joystick
-- TODO: replace all IP cores with soft implementation

------------------------------------------------------------------------------------------------------------------*/

// Warning! HW_ID2 macros defined in the Synthesize - XST process properties!

module karabas_mini_top (
	//------------------ global clock --------
	input wire 				CLK_50MHZ,

	//------------------ esp8266 uart --------
	inout wire 				UART_RX,
	inout wire 				UART_TX,
	inout wire 				UART_CTS,
	inout wire 				ESP_RESET_N,
	inout wire 				ESP_BOOT_N,

	//------------------ sram ----------------
	output wire [20:0] 	MA,
	inout wire [15:0] 	MD,
	output wire [1:0] 	MWR_N,
	output wire [1:0] 	MRD_N,

	//------------------ sdram ---------------
	output wire [1:0] 	SDR_BA,
	output wire [12:0] 	SDR_A,
	output wire 			SDR_CLK,
	output wire [1:0] 	SDR_DQM,
	output wire 			SDR_WE_N,
	output wire 			SDR_CAS_N,
	output wire 			SDR_RAS_N,
	inout wire [15:0] 	SDR_DQ,

	//------------------ sd2 -----------------
	output wire 			SD_CS_N,
	output wire 			SD_CLK,
	inout wire 				SD_DI,
	inout wire 				SD_DO,
	input wire 				SD_DET_N,

	//------------------ ft812 rgb + sync ----
	input wire [7:0] 		VGA_R,
	input wire [7:0] 		VGA_G,
	input wire [7:0] 		VGA_B,
	input wire 				VGA_HS,
	input wire 				VGA_VS,

	//------------------ dvi / hdmi ----------
	output wire [3:0] 	TMDS_P,
	output wire [3:0] 	TMDS_N,

	//------------------ ft812 spi and ctl ---
	output wire 			FT_SPI_CS_N,
	output wire 			FT_SPI_SCK,
	input wire 				FT_SPI_MISO,
	output wire 			FT_SPI_MOSI,
	input wire 				FT_INT_N,
	input wire 				FT_CLK,
	input wire 				FT_AUDIO,
	input wire 				FT_DE,
	input wire 				FT_DISP,
	output wire 			FT_RESET,
	output wire 			FT_CLK_OUT,

	//------------------ cf card -------------
	output wire [2:0] 	WA,
	output wire [1:0] 	WCS_N,
	output wire 			WRD_N,
	output wire 			WWR_N,
	output wire 			WRESET_N,
	inout wire [15:0] 	WD,

	//------------------ analog in/out -------	
	output wire 			TAPE_OUT,
	input wire 				TAPE_IN,
	output wire 			AUDIO_L,
	output wire 			AUDIO_R,

	//------------------ adc -----------------
	output wire 			ADC_CLK,
	inout wire 				ADC_BCK,
	inout wire 				ADC_LRCK,
	input wire 				ADC_DOUT,

	//------------------ mcu spi -------------
	input wire 				MCU_CS_N,
	input wire 				MCU_SCK,
	input wire 				MCU_MOSI,
	output wire 			MCU_MISO,
	input wire [3:0] 		MCU_IO,

	//------------------ midi ----------------
	output wire 			MIDI_TX,
	output wire 			MIDI_CLK,
	output wire 			MIDI_RESET_N,

	//------------------ optional flash ------
	output wire 			FLASH_CS_N,
	input wire  			FLASH_DO,
	output wire 			FLASH_DI,
	output wire 			FLASH_SCK,
	output wire 			FLASH_WP_N,
	output wire 			FLASH_HOLD_N
);

// unused signals yet
assign ESP_RESET_N 	= 1'bZ;
assign ESP_BOOT_N 	= 1'bZ;
assign FT_SPI_CS_N = 1'b1;
assign FT_SPI_SCK = 1'b0;
assign FT_SPI_MOSI = 1'b0;
assign MWR_N = 2'b11;
assign MRD_N = 2'b11;
assign MD = 16'bZ;
assign MA = 21'b0;
assign TAPE_OUT = 1'b0;
//assign FLASH_CS_N = 1'b1;
assign FLASH_WP_N = 1'b1;
assign FLASH_HOLD_N = 1'b1;
assign FLASH_SCK = 1'b1;
assign MIDI_RESET_N = 1'b1;
assign FLASH_DI = 1'b1;
assign FT_RESET = 1'b1;
assign MIDI_CLK = 1'b0;
assign FT_CLK_OUT = 1'b0;
assign ADC_CLK = 1'b0;
assign ADC_BCK = 1'b0;
assign ADC_LRCK = 1'b0;
assign WA = 3'b000;
assign WCS_N = 2'b11;
assign WRD_N = 1'b1;
assign WWR_N = 1'b1;
assign WRESET_N = 1'b1;

// --------- System ------------
wire clk_bus, clk_vga, clk_sdr, clk_sdr_out;
wire areset;
wire [17:0] vga_rgb;
wire vga_hs, vga_vs, vga_blank;
wire sdr_cs_n;
wire [15:0] audio_mix_l, audio_mix_r;
wire kb_reset, kb_nmi;
wire [7:0] ps2_scancode, xt_scancode;
wire ps2_scancode_upd, xt_scancode_upd;
wire [7:0] ms_x, ms_y;
wire [3:0] ms_z;
wire [2:0] ms_b;
wire ms_upd;
wire vmode;
wire [23:0] adc_l, adc_r; // todo!

wire [31:0] romload_a;
wire [7:0] romload_d;
wire romload_active, romload_wr;

wire [13:0] bios_addr;
wire [15:0] bios_din;
wire bios_wr;
wire bios_loaded;
wire bios_req;

wire [15:0] ps2_command;
wire ps2_command_wr;

assign FLASH_CS_N = sdr_cs_n;

system sys_inst
	(
		.CLK_50MHZ(CLK_50MHZ),
		.CLK_BUS(clk_bus),
		.CLK_VGA(clk_vga),
		.CLK_SDR(clk_sdr),
		.ARESET(areset),
		
		.VGA_R(vga_rgb[17:12]),
		.VGA_G(vga_rgb[11:6]),
		.VGA_B(vga_rgb[5:0]),
		.VGA_HSYNC(vga_hs),
		.VGA_VSYNC(vga_vs),
		.VGA_BLANK(vga_blank),
		.VMODE(vmode),
		
		.sdr_CLK_out(clk_sdr_out),
		.sdr_n_CS_WE_RAS_CAS({sdr_cs_n, SDR_WE_N, SDR_RAS_N, SDR_CAS_N}),
		.sdr_BA(SDR_BA),
		.sdr_ADDR(SDR_A),
		.sdr_DATA(SDR_DQ),
		.sdr_DQM(SDR_DQM),
		
		.LED(),
		.BTN_RESET(kb_reset || !bios_loaded),
		.BTN_NMI(kb_nmi),
		
		.SD_n_CS(SD_CS_N),
		.SD_DI(SD_DI),
		.SD_CK(SD_CLK),
		.SD_DO(SD_DO),
		.AUD_L(audio_mix_l),
		.AUD_R(audio_mix_r),

		.ps2_scancode(ps2_scancode),
		.ps2_scancode_upd(ps2_scancode_upd),

		.xt_scancode(xt_scancode),
		.xt_scancode_upd(xt_scancode_upd),
		
		.ps2_command(ps2_command),
		.ps2_command_wr(ps2_command_wr),
		
		.ms_x(ms_x),
		.ms_y(ms_y),
		.ms_z(ms_z),
		.ms_b(ms_b),
		.ms_upd(ms_upd),

		.RS232_DCE_RXD(),
		.RS232_DCE_TXD(),
		.RS232_EXT_RXD(1'b0), // todo
		.RS232_EXT_TXD(),
		.RS232_HOST_RXD(),
		.RS232_HOST_TXD(),
		.RS232_HOST_RST(),
		.GPIO(),
		
		.adc_l(adc_l),
		.adc_r(adc_r),
		.MIDI_OUT(MIDI_TX),
		
		.BIOS_ADDR(bios_addr),
		.BIOS_DIN(bios_din),
		.BIOS_WR(bios_wr),
		.BIOS_REQ(bios_req)
	);

//---------- MCU ------------

wire [12:0] joy_l, joy_r;
wire [15:0] softsw_command, osd_command;
wire mcu_busy;
wire [7:0] hwid;
wire dvi_only;

mcu mcu(
	.CLK(clk_bus),
	.N_RESET(~areset),
	
	.MCU_MOSI(MCU_MOSI),
	.MCU_MISO(MCU_MISO),
	.MCU_SCK(MCU_SCK),
	.MCU_SS(MCU_CS_N),
	
	.MS_X(ms_x),
	.MS_Y(ms_y),
	.MS_Z(ms_z),
	.MS_B(ms_b),
	.MS_UPD(ms_upd),
	
	.KB_SCANCODE(ps2_scancode),
	.KB_SCANCODE_UPD(ps2_scancode_upd),

	.XT_SCANCODE(xt_scancode),
	.XT_SCANCODE_UPD(xt_scancode_upd),
	
	.PS2_COMMAND(ps2_command),
	.PS2_COMMAND_WR(ps2_command_wr),	
	
	.JOY_L(joy_l),
	.JOY_R(joy_r),
	
	.RTC_A(8'b00000000),
	.RTC_DI(8'b00000000),
	.RTC_DO(),
	.RTC_CS(1'b0),
	.RTC_WR_N(1'b1),
	
	.UART_RX_DATA(),
	.UART_RX_IDX(),
	.UART_TX_DATA(8'b00000000),
	.UART_TX_WR(1'b0),
	
	.ROMLOADER_ACTIVE(romload_active), // todo
	.ROMLOAD_ADDR(romload_a),
	.ROMLOAD_DATA(romload_d),
	.ROMLOAD_WR(romload_wr),
	
	.HWID(hwid),
	.DVI_ONLY(dvi_only),
	
	.SOFTSW_COMMAND(softsw_command),	
	.OSD_COMMAND(osd_command),
	
//	.DEBUG_ADDR("00000" & hdmi_width),
//	.DEBUG_DATA("00000" & hdmi_height),
	
	.BUSY(mcu_busy)
);

//---------- Soft switches ------------

soft_switches soft_switches(
	.CLK(clk_bus),	
	.SOFTSW_COMMAND(softsw_command),
	.NMI(kb_nmi),
	.RESET(kb_reset)
);

// --------- BIOS loader ---------------
`ifdef BIOS_LOADER
bios_loader bios_loader(
	.clk(clk_bus),
	.clk_sdr(clk_sdr),
	.reset(areset),
	
	.active(romload_active),
	.addr(romload_a),
	.din(romload_d),
	.wr(romload_wr),
	
	.bios_addr(bios_addr),
	.bios_din(bios_din),
	.bios_wr(bios_wr),
	.bios_req(bios_req),
	.bios_loaded(bios_loaded)
);
`else
	assign bios_loaded = 1;
	assign bios_wr = 0;
`endif

// hdmi 
wire [23:0] hdmi_rgb;
wire hdmi_hs, hdmi_vs, hdmi_blank;
assign hdmi_rgb = {vga_rgb[17:12], 2'b00, vga_rgb[11:6], 2'b00, vga_rgb[5:0], 2'b00};
assign hdmi_hs = (vmode) ? ~vga_hs : ~vga_hs;
assign hdmi_vs = (vmode) ? ~vga_vs : vga_vs;
assign hdmi_blank = vga_blank;

hdmi_top hdmi_top(
	.clk				(clk_vga),
	.ds80				(1'b1),
	.reset			(areset || kb_reset),

	.vga_rgb			(hdmi_rgb),
	.vga_hs			(hdmi_hs),
	.vga_vs			(hdmi_vs),
	.vga_de			(~hdmi_blank),

	.audio_en		(~dvi_only),
	.audio_l			(audio_mix_l),
	.audio_r			(audio_mix_r),

	.tmds_p			(TMDS_P),
	.tmds_n			(TMDS_N)
);

//------- Sigma-Delta DAC ---------
dac dac_l(
	.I_CLK			(clk_vga),
	.I_RESET			(areset),
	.I_DATA			({2'b00, !audio_mix_l[15], audio_mix_l[14:4], 2'b00}),
	.O_DAC			(AUDIO_L)
);

dac dac_r(
	.I_CLK			(clk_vga),
	.I_RESET			(areset),
	.I_DATA			({2'b00, !audio_mix_r[15], audio_mix_r[14:4], 2'b00}),
	.O_DAC			(AUDIO_R)
);

// sdram clk out
ODDR2 #(
	.DDR_ALIGNMENT("NONE"), // Sets output alignment to "NONE", "C0" or "C1" 
	.INIT(1'b0),    // Sets initial state of the Q output to 1'b0 or 1'b1
	.SRTYPE("SYNC") // Specifies "SYNC" or "ASYNC" set/reset
) ODDR2_inst 
(
	.Q(SDR_CLK),   // 1-bit DDR output data
	.C0(clk_sdr_out),  // 1-bit clock input
	.C1(!clk_sdr_out), // 1-bit clock input
	.CE(1'b1), 		// 1-bit clock enable input
	.D0(1'b1), 		// 1-bit data input (associated with C0)
	.D1(1'b0), 		// 1-bit data input (associated with C1)
	.R(1'b0),   	// 1-bit reset input
	.S(1'b0)    	// 1-bit set input
);

endmodule
