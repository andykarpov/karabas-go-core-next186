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
-- FPGA Next186 SoC core for Karabas-Go Mini rev.G
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

// Warning! HW_ID2 and HW_ID3 macroses are defined in the Synthesize - XST process properties!

module karabas_minig_top (
    //------------------ global clock --------
    input wire           CLK_50MHZ,

    //------------------ esp8266 uart --------
    inout wire           UART_RX,
    inout wire           UART_TX,
    inout wire           UART_CTS,

    //------------------ sram ----------------
    output wire [20:0]   MA,
    inout wire [15:0]    MD,
    output wire [1:0]    MWR_N,
    output wire [1:0]    MRD_N,

    //------------------ sdram ---------------
    output wire [1:0]    SDR_BA,
    output wire [12:0]   SDR_A,
    output wire          SDR_CLK,
    output wire [1:0]    SDR_DQM,
    output wire          SDR_WE_N,
    output wire          SDR_CAS_N,
    output wire          SDR_RAS_N,
    inout wire [15:0]    SDR_DQ,

    //------------------ sd2 -----------------
    output wire          SD_CS_N,
    output wire          SD_CLK,
    inout wire           SD_DI,
    inout wire           SD_DO,
    input wire           SD_DET_N,

    //------------------ ft812 rgb + sync ----
    input wire [7:0]     VGA_R,
    input wire [7:0]     VGA_G,
    input wire [7:0]     VGA_B,
    input wire           VGA_HS,
    input wire           VGA_VS,

    //------------------ dvi / hdmi ----------
    output wire [3:0]    TMDS_P,
    output wire [3:0]    TMDS_N,

    //------------------ ft812 spi and ctl ---
    output wire          FT_SPI_CS_N,
    output wire          FT_SPI_SCK,
    input wire           FT_SPI_MISO,
    output wire          FT_SPI_MOSI,
    input wire           FT_INT_N,
    input wire           FT_CLK,
    input wire           FT_DE,
    output wire          FT_CLK_OUT,

    //------------------ cf card -------------
    output wire [2:0]    WA,
    output wire [1:0]    WCS_N,
    output wire          WRD_N,
    output wire          WWR_N,
    output wire          WRESET_N,
    inout wire [15:0]    WD,

    //------------------ analog in/out -------    
    output wire          TAPE_OUT,
    input wire           TAPE_IN,

   //------------------ i2s dac -------------
    output wire          DAC_BCK,
    output wire          DAC_WS,
    output wire          DAC_DAT,

    //------------------ adc -----------------
    output wire          ADC_CLK,
    inout wire           ADC_BCK,
    inout wire           ADC_LRCK,
    input wire           ADC_DOUT,
    
    //------------------ esp32 i2s and cs ----
    output wire          ESP32_SPI_CS_N,
    input wire           ESP32_PCM_BCK,
    input wire           ESP32_PCM_RLCK,
    input wire           ESP32_PCM_DAT,    

    //------------------ mcu spi -------------
    input wire           MCU_CS_N,
    input wire           MCU_SCK,
    input wire           MCU_MOSI,
    output wire          MCU_MISO,
    input wire [5:0]     MCU_IO,

    //------------------ midi ----------------
    output wire          MIDI_TX,

    //------------------ optional flash ------
    output wire          FLASH_CS_N,
    input wire           FLASH_DO,
    output wire          FLASH_DI,
    output wire          FLASH_SCK,
    output wire          FLASH_WP_N,
    output wire          FLASH_HOLD_N
);

// unused signals yet
assign FT_SPI_CS_N  = 1'b1;
assign FT_SPI_SCK   = 1'b0;
assign FT_SPI_MOSI  = 1'b0;
assign MWR_N        = 2'b11;
assign MRD_N        = 2'b11;
assign MD           = 16'bZ;
assign MA           = 21'b0;
assign TAPE_OUT     = 1'b0;
assign FLASH_CS_N   = 1'b1;
assign FLASH_WP_N   = 1'b1;
assign FLASH_HOLD_N = 1'b1;
assign FLASH_SCK    = 1'b1;
assign FLASH_DI     = 1'b1;
assign FT_CLK_OUT   = 1'b0;
assign WA           = 3'b000;
assign WCS_N        = 2'b11;
assign WRD_N        = 1'b1;
assign WWR_N        = 1'b1;
assign WRESET_N     = 1'b1;
assign ESP32_SPI_CS_N = 1'b1;

// system
wire clk_vga, clk_bus, clk_adc, clk_sdr, clk_sdr_out, clk_midi;
wire areset, reset;
wire [15:0] audio_mix_l, audio_mix_r;
wire [23:0] adc_l, adc_r;
wire [23:0] vga_rgb;
wire vga_hs, vga_vs, vga_blank, dvi_only;

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

// hdmi 
hdmi_top hdmi_top(
    .clk           (clk_vga),
    .ds80          (1'b1),
    .reset         (reset),

    .vga_rgb       (vga_rgb),
    .vga_hs        (vga_hs),
    .vga_vs        (vga_vs),
    .vga_de        (~vga_blank),

    .audio_en      (~dvi_only),
    .audio_l       (audio_mix_l),
    .audio_r       (audio_mix_r),

    .tmds_p        (TMDS_P),
    .tmds_n        (TMDS_N)
);

// ADC
i2s_transceiver #(.mclk_sclk_ratio(4)) adc(
    .reset_n       (~areset),
    .mclk          (clk_adc),
    .sclk          (ADC_BCK),
    .ws            (ADC_LRCK),
    .sd_rx         (ADC_DOUT),
    .l_data_rx     (adc_l),
    .r_data_rx     (adc_r)
);

// i2s DAC
PCM5102 #(.DAC_CLK_DIV_BITS(2)) PCM5102(
    .clk           (clk_bus),
    .reset         (areset),
    .left          (audio_mix_l),
    .right         (audio_mix_r),
    .din           (DAC_DAT),
    .bck           (DAC_BCK),
    .lrck          (DAC_WS)
);

// sdram clk out
ODDR2 #(.DDR_ALIGNMENT("NONE"), .INIT(1'b0), .SRTYPE("SYNC")) sdr_oddr2 (
    .Q(SDR_CLK), .C0(clk_sdr_out), .C1(!clk_sdr_out), .CE(1'b1), .D0(1'b1), .D1(1'b0), .R(1'b0), .S(1'b0)
);

// adc clk out
ODDR2 #(.DDR_ALIGNMENT("NONE"), .INIT(1'b0), .SRTYPE("SYNC")) adc_oddr2 (
    .Q(ADC_CLK), .C0(clk_adc), .C1(!clk_adc), .CE(1'b1), .D0(1'b1), .D1(1'b0), .R(1'b0), .S(1'b0)
);

endmodule
