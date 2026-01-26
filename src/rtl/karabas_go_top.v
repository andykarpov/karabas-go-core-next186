`timescale 1ns / 1ps
`default_nettype none
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
-- FPGA Next186 SoC core for Karabas-Go
-- based on MIST core https://github.com/gyurco/Next186/
--
-- @author Andy Karpov <andy.karpov@gmail.com>
-- EU, 2026
--
-- TODO: mouse wheel
-- TODO: HDD (CF) вместо SD
-- TODO: UART - connect to USB uart or ESP8266
-- TODO: GPIO - joystick

------------------------------------------------------------------------------------------------------------------*/

module karabas_go_top (
    //---------------------------
    input wire CLK_50MHZ,

    //---------------------------
    inout wire UART_RX,
    inout wire UART_TX,
    inout wire UART_CTS,
    inout wire ESP_RESET_N,
    inout wire ESP_BOOT_N,
    
    //---------------------------
    output wire [20:0] MA,
    inout wire [15:0] MD,
    output wire [1:0] MWR_N,
    output wire [1:0] MRD_N,

    //---------------------------
    output wire [1:0] SDR_BA,
    output wire [12:0] SDR_A,
    output wire SDR_CLK,
    output wire [1:0] SDR_DQM,
    output wire SDR_WE_N,
    output wire SDR_CAS_N,
    output wire SDR_RAS_N,
    inout wire [15:0] SDR_DQ,

    //---------------------------
    output wire SD_CS_N,
    output wire SD_CLK,
    inout wire SD_DI,
    inout wire SD_DO,
    input wire SD_DET_N,

    //---------------------------
    output wire [7:0] VGA_R,
    output wire [7:0] VGA_G,
    output wire [7:0] VGA_B,
    output wire VGA_HS,
    output wire VGA_VS,
    output wire V_CLK,
    
    //---------------------------
    output wire FT_SPI_CS_N,
    input wire FT_SPI_SCK,
    input wire FT_SPI_MISO,
    input wire FT_SPI_MOSI,
    input wire FT_INT_N,
    input wire FT_CLK,
    output wire FT_OE_N,

    //---------------------------
    output wire [2:0] WA,
    output wire [1:0] WCS_N,
    output wire WRD_N,
    output wire WWR_N,
    output wire WRESET_N,
    inout wire [15:0] WD,
    
    //---------------------------
    input wire FDC_INDEX,
    output wire [1:0] FDC_DRIVE,
    output wire FDC_MOTOR,
    output wire FDC_DIR,
    output wire FDC_STEP,
    output wire FDC_WDATA,
    output wire FDC_WGATE,
    input wire FDC_TR00,
    input wire FDC_WPRT,
    input wire FDC_RDATA,
    output wire FDC_SIDE_N,

    //---------------------------    
    input wire TAPE_OUT,
    input wire TAPE_IN,
    input wire BEEPER,
    
    //---------------------------
    output wire DAC_LRCK,
    output wire DAC_DAT,
    output wire DAC_BCK,
    output wire DAC_MUTE,
    
    //---------------------------
    input wire MCU_CS_N,
    input wire MCU_SCK,
    inout wire MCU_MOSI,
    output wire MCU_MISO,
    input wire MCU_SPI_FT_CS_N,
    input wire MCU_SPI_SD2_CS_N,    
    inout wire [1:0] MCU_SPI_IO,
    
    //---------------------------
    output wire MIDI_TX,
    output wire MIDI_CLK,
    output wire MIDI_RESET_N,
    
    //---------------------------
    input wire FLASH_CS_N,
    input wire  FLASH_DO,
    input wire FLASH_DI,
    input wire FLASH_SCK,
    input wire FLASH_WP_N,
    input wire FLASH_HOLD_N    
);

//assign BEEPER       = 1'b0; // changed to input
assign ESP_RESET_N  = 1'bZ;
assign ESP_BOOT_N   = 1'bZ;
assign FT_SPI_CS_N  = 1'b1;
//assign FT_SPI_SCK   = 1'b0; // changed to input
//assign FT_SPI_MOSI  = 1'b0; // changed to input
assign FT_OE_N      = 1'b1;
assign MWR_N        = 2'b11;
assign MRD_N        = 2'b11;
assign MD           = 16'bZ;
assign MA           = 21'b0;
//assign TAPE_OUT     = 1'b0; // changed to input
//assign FLASH_CS_N   = 1'b1; // changed to input
//assign FLASH_WP_N   = 1'b1; // changed to input
//assign FLASH_HOLD_N = 1'b1; // changed to input
//assign FLASH_SCK    = 1'b1; // changed to input
assign MIDI_RESET_N = ~reset;
//assign FLASH_DI     = 1'b1; // changed to input
assign WA           = 3'b000;
assign WCS_N        = 2'b11;
assign WRD_N        = 1'b1;
assign WWR_N        = 1'b1;
assign WRESET_N     = 1'b1;

assign FDC_DRIVE    = 2'b00;
assign FDC_MOTOR    = 1'b0;
assign FDC_DIR      = 1'b0;
assign FDC_STEP     = 1'b0;
assign FDC_WDATA    = 1'b0;
assign FDC_WGATE    = 1'b0;
assign FDC_SIDE_N   = 1'b1;

// system
wire clk_vga, clk_bus, clk_adc, clk_sdr, clk_sdr_out, clk_midi;
wire areset, reset;
wire [15:0] audio_mix_l, audio_mix_r;
wire [23:0] adc_l, adc_r;
wire [23:0] vga_rgb;
wire vga_hs, vga_vs, vga_blank, vga_reset, dvi_only;

assign VGA_R = vga_rgb[23:16];
assign VGA_G = vga_rgb[15:8];
assign VGA_B = vga_rgb[7:0];
assign VGA_HS = vga_hs;
assign VGA_VS = vga_vs;

karabas_186 karabas_186(
    .clk           (CLK_50MHZ),
    .clk_bus       (clk_bus),
    .clk_vga       (clk_vga),
    .clk_adc       (clk_adc),
    .clk_sdr       (clk_sdr),
    .clk_sdr_out   (clk_sdr_out),
    .clk_midi      (clk_midi),
    .areset        (areset),
    .reset         (reset),
    .sdr_ba        (SDR_BA),
    .sdr_a         (SDR_A),
    .sdr_dqm       (SDR_DQM),
    .sdr_we_n      (SDR_WE_N),
    .sdr_cas_n     (SDR_CAS_N),
    .sdr_ras_n     (SDR_RAS_N),
    .sdr_dq        (SDR_DQ),
    .pwm_audio_l   (),
    .pwm_audio_r   (),
    .audio_l       (audio_mix_l),
    .audio_r       (audio_mix_r),
    .adc_l         (adc_l),
    .adc_r         (adc_r),
    .midi_tx       (MIDI_TX),
    .vga_rgb       (vga_rgb),
    .vga_hs        (vga_hs),
    .vga_vs        (vga_vs),
    .vga_blank     (vga_blank),
    .vga_reset     (vga_reset),
    .dvi_only      (dvi_only),
    .sd_cs_n       (SD_CS_N),
    .sd_di         (SD_DI),
    .sd_do         (SD_DO),
    .sd_clk        (SD_CLK),
    .mcu_cs_n      (MCU_CS_N),
    .mcu_sck       (MCU_SCK),
    .mcu_mosi      (MCU_MOSI),
    .mcu_miso      (MCU_MISO)
);

// DAC
PCM5102 PCM5102(
    .clk           (clk_bus),
    .reset         (areset),
    .left          (audio_mix_l),
    .right         (audio_mix_r),
    .din           (DAC_DAT),
    .bck           (DAC_BCK),
    .lrck          (DAC_LRCK)
);
assign DAC_MUTE = 1'b1; // soft mute, 0 = mute, 1 = unmute

// sdram clk out
ODDR2 #(.DDR_ALIGNMENT("NONE"), .INIT(1'b0), .SRTYPE("SYNC")) sdr_oddr2 (
    .Q(SDR_CLK), .C0(clk_sdr_out), .C1(!clk_sdr_out), .CE(1'b1), .D0(1'b1), .D1(1'b0), .R(1'b0), .S(1'b0)
);

// midi clk out
ODDR2 #(.DDR_ALIGNMENT("NONE"), .INIT(1'b0), .SRTYPE("SYNC")) midi_oddr2 (
    .Q(MIDI_CLK), .C0(clk_midi), .C1(!clk_midi), .CE(1'b1), .D0(1'b1), .D1(1'b0), .R(1'b0), .S(1'b0)
);

// video clk out
ODDR2 #(.DDR_ALIGNMENT("NONE"), .INIT(1'b0), .SRTYPE("SYNC")) vclk_oddr2 (
    .Q(V_CLK), .C0(clk_vga), .C1(!clk_vga), .CE(1'b1), .D0(1'b1), .D1(1'b0), .R(1'b0), .S(1'b0)
);

endmodule
