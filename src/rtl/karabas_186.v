`timescale 1ns / 1ns
`default_nettype none

module karabas_186 #(
    parameter BURST_MAX_MHZ = 0, // see kg_mcu
    parameter PHYS_FDD = 0,      // 1: the physical floppy drives of the floppy connector (Karabas Go)
    // the MCU link: 1 = v1 (kg_mcu, img_sdc, kg_soft_switches, overlay.vhd), 2 = v2 (kg_mcu2: its
    // mounter, SW registers, kg_l2_osd_overlay; mcu_burst_ready is MCU_INT, mcu_burst_cs_n unused)
    parameter LINK = 1
)(
    input  wire         clk,

    output wire         clk_bus,
    output wire         clk_vga,
    output wire         clk_adc,
    output wire         clk_sdr,
    output wire         clk_sdr_out,
    output wire         clk_midi,
    output wire         areset,
    output reg          reset,

    output wire [1:0]   sdr_ba,
    output wire [12:0]  sdr_a,
    output wire [1:0]   sdr_dqm,
    output wire         sdr_we_n,
    output wire         sdr_cas_n,
    output wire         sdr_ras_n,
    inout  wire [15:0]  sdr_dq,

    output wire         pwm_audio_l,
    output wire         pwm_audio_r,
    output wire [15:0]  audio_l,
    output wire [15:0]  audio_r,
    input  wire [23:0]  adc_l,
    input  wire [23:0]  adc_r,
    output wire         midi_tx,

    output wire [23:0]  vga_rgb,
    output wire         vga_hs,
    output wire         vga_vs,
    output wire         vga_blank,
    output wire         vga_reset,
    output wire         dvi_only,

    output wire         sd_cs_n,
    output wire         sd_di,
    input  wire         sd_do,
    output wire         sd_clk,

    input  wire         mcu_cs_n,
    input  wire         mcu_sck,
    input  wire         mcu_mosi,
    output wire         mcu_miso,
    input  wire         mcu_burst_cs_n,  // burst transfers (karabas-go-firmware docs/burst_protocol.md)
    output wire         mcu_burst_ready,

    // the floppy connector (PHYS_FDD), at the pins: { rdata, wprt, tr00, index },
    // { wdata, wgate, side, step, dir, motor, ds1, ds0 }, see pcxt_fdd_phys
    input  wire [3:0]   fdd_in,
    output wire [7:0]   fdd_out
);

wire clk_buf;
IBUFG #(.IOSTANDARD("DEFAULT")) IBUFG_inst 
(
	.I(clk),    // Clock buffer input (connect directly to top-level port)
	.O(clk_buf) // Clock buffer output
);

// dcm
wire clk_cpu, clk_dsp, CLK14745600, clk_mpu, clk_25, clk_12, clk_3;
wire locked;
dcm dcm_system (
    .CLK_IN1(clk_buf),
    .CLK_OUT1(clk_sdr_out), // 100 @ 180
    .CLK_OUT2(clk_sdr),     // 100
    .CLK_OUT3(clk_cpu),     // 50
    .CLK_OUT4(clk_dsp),     // 40
	 .CLK_OUT5(clk_25),      // 25
    .LOCKED(locked)
);

dcm_dsp dcm_dsp (
    .CLK_IN1(clk_buf),
    .CLK_OUT1(CLK14745600),  // 14.7456
    .CLK_OUT2(clk_12)        // 12
);

assign areset = ~locked;
assign clk_bus = clk_cpu;
assign clk_vga = clk_25;
assign clk_adc = clk_12; // PCM1808: SCKI 12 MHz = 256 fs, fs 46.9 kHz (25 MHz gave 97.7 kHz, over its 96 kHz)
assign clk_midi = clk_12;
assign clk_mpu = clk_3; // from clk_12 div 4

reg [1:0] div4 = 0;
always @(posedge clk_12)
    div4 <= div4 + 1;

BUFGCE buf_mpu(.I(clk_12), .O(clk_3), .CE(&div4[1:0]));

// --------- System ------------
wire sdr_cs_n;
wire [15:0] ps2_command;
wire ps2_command_wr;
wire [15:0] cdda_l;
wire [15:0] cdda_r;
wire [5:0] core_r, core_g, core_b;
wire core_hs, core_vs, core_blank, core_vga_reset, core_vb, core_vb_frame, core_hb, core_hs_d, core_vs_d;
wire [15:0] ide_dat_o, ide_dat_i;
wire [3:0] ide_a;
wire [1:0] ide_cs;
wire ide_we;
wire [1:0] ide_int;
wire fdc_cs, fdc_we;
wire kb_boot_c;
wire [2:0] fdc_a;
wire [7:0] fdc_dat_o, fdc_dat_i;
wire cpu_reset;
// soundwave gives the mix as unsigned (+32768, for the PWM); the I2S DAC and HDMI take signed samples
wire [15:0] sys_laudio, sys_raudio;
assign audio_l = sys_laudio ^ 16'h8000;
assign audio_r = sys_raudio ^ 16'h8000;

// the ADC samples (clk_12) into clk_cpu: a word is taken when it is the same on two clocks
reg [15:0] adc_l1, adc_l2, adc_ls_l, adc_r1, adc_r2, adc_ls_r;
always @(posedge clk_cpu) begin
    adc_l1 <= adc_l[23:8];
    adc_l2 <= adc_l1;
    if (adc_l1 == adc_l2) adc_ls_l <= adc_l2;
    adc_r1 <= adc_r[23:8];
    adc_r2 <= adc_r1;
    if (adc_r1 == adc_r2) adc_ls_r <= adc_r2;
end

// level meters of the mcu (dot matrix): 2^20 clocks at 50 MHz = 21 ms
wire [23:0] matrix_cmd;
wire matrix_cmd_wr;
audio_peaks #(.PERIOD_BITS(20)) audio_peaks(
    .clk(clk_bus),
    .audio_l(audio_l),
    .audio_r(audio_r),
    .cmd_wr(matrix_cmd_wr),
    .cmd(matrix_cmd)
);

system sys_inst(
    .clk_25(clk_25),
    .clk_sdr(clk_sdr),
    .CLK14745600(CLK14745600),
    .clk_mpu(clk_mpu),

    .clk_cpu(clk_cpu),
    .clk_en_opl2(cen_opl2),
    .clk_en_44100(cen_44100),
    .clk_dsp(clk_dsp),

    .fake286(fake286_r2),
    .adlibhide(kb_adlibhide),
    .cpu_speed(cpu_speed),
    .waitstates(kb_isawait == 0 ? 8'd50 :
                kb_isawait == 1 ? 8'd100 :
                kb_isawait == 2 ? 8'd166 : 8'd200),

    .VGA_R(core_r),
    .VGA_G(core_g),
    .VGA_B(core_b),
    .VGA_HSYNC(core_hs),
    .VGA_VSYNC(core_vs),
    .VGA_BLANK(core_blank),
    .VGA_VBLANK(core_vb),
    .VGA_VBLANK_FRAME(core_vb_frame),
    .VGA_HBLANK(core_hb),
    .VGA_HSYNC_D(core_hs_d),
    .VGA_VSYNC_D(core_vs_d),
	 .VGA_RESET(core_vga_reset),
    .frame_on(),

    .sdr_n_CS_WE_RAS_CAS({sdr_cs_n, sdr_we_n, sdr_ras_n, sdr_cas_n}),
    .sdr_BA(sdr_ba),
    .sdr_ADDR(sdr_a),
    .sdr_DATA(sdr_dq),
    .sdr_DQM(sdr_dqm),

    .LED(),

    .BTN_RESET(reset),
    .CPU_RESET(cpu_reset),
    .BTN_NMI(NMI),

    .RS232_DCE_RXD(1'b1),
    .RS232_DCE_TXD(),
    .RS232_EXT_RXD(com1_Rx),
    .RS232_EXT_TXD(com1_Tx),
    .MPU_RX(mpu_Rx),
    .MPU_TX(mpu_Tx),

    .SD_n_CS(core_sd_cs_n),
    .SD_DI(sd_di),
    .SD_CK(sd_clk),
    .SD_DO(sd_do),

    .CDDA_L(cdda_l),
    .CDDA_R(cdda_r),

    .AUD_L(pwm_audio_l),
    .AUD_R(pwm_audio_r),
    .LAUDIO(sys_laudio),
    .RAUDIO(sys_raudio),

    .RS232_HOST_RXD(1'b1),
    .RS232_HOST_TXD(),
    .RS232_HOST_RST(),

    .GPIO_WR(joy_wr),
    .GPIO_IN(joy),

    .IDE_DAT_O(ide_dat_o),
    .IDE_DAT_I(ide_dat_i),
    .IDE_A(ide_a),
    .IDE_WE(ide_we),
    .IDE_CS(ide_cs),
    .IDE_INT(ide_int),

    .FDC_CS(fdc_cs),
    .FDC_A(fdc_a),
    .FDC_WE(fdc_we),
    .FDC_DAT_O(fdc_dat_o),
    .FDC_DAT_I(fdc_dat_i),
    .SYS_CFG({7'd0, kb_boot_c}),

    .I2C_SCL(),
    .I2C_SDA(),

    .BIOS_ADDR(bios_addr),
    .BIOS_DIN(bios_din),
    .BIOS_WR(bios_wr),
    .BIOS_REQ(bios_req),
        
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

    .adc_l({ adc_ls_l, 8'd0 }),
    .adc_r({ adc_ls_r, 8'd0 })
);

//---------- MCU ------------

wire [12:0] joy_l, joy_r;
wire [15:0] softsw_command, osd_command;
wire mcu_busy;
wire [7:0] hwid;

wire [7:0] ps2_scancode, xt_scancode;
wire ps2_scancode_upd, xt_scancode_upd;
wire [7:0] ms_x, ms_y;
wire [3:0] ms_z;
wire [2:0] ms_b;
wire ms_upd;

wire [31:0] romload_a;
wire [7:0] romload_d;
wire romload_active, romload_wr;

wire [1:0] mcu_btns;
wire mcu_dvi_only;

// --------- File mounter & ATA Hard Disk ------------

wire [7:0] img_mounted;
wire [63:0] img_size;
wire img_data_wr;
wire [8:0] img_data_addr;
wire [7:0] img_data;
wire img_result_wr;
wire [7:0] img_result;
wire [15:0] img_sum;
wire img_q_wr;
wire [23:0] img_q_di;
wire img_q_ack;
wire img_phys_wr;
wire [15:0] img_phys;

wire [7:0] sdc_img_mounted;
wire [63:0] sdc_img_size;
wire sdc_busy, sdc_done, sdc_error;
wire [2:0] sdc_slot;
wire sdc_byte_in_strobe;
wire [8:0] sdc_byte_addr;
wire [7:0] sdc_byte_in_data;
wire sdc_active;

wire [15:0] hdf_dout;
wire [1:0] hdf_rd, hdf_wr;
wire [31:0] hdf_sector;
wire [7:0] hdf_byte_out_data;
wire hdf_own = (sdc_slot < 3'd2);
wire fdd_own = (sdc_slot[2:1] == 2'b01);
wire [1:0] fdd_rd, fdd_wr;
wire [31:0] fdd_sector;
wire [7:0] fdd_byte_out_data;

// the OSD of link v2 (kg_mcu2 -> kg_l2_osd_overlay)
wire osd_wr, osd_en, osd_zoom;
wire [11:0] osd_waddr;
wire [7:0] osd_wdata;
wire [23:0] osd_fg, osd_bg;
wire [1:0] osd_alpha, osd_place;
wire [4:0] osd_px, osd_ph;
wire [3:0] osd_py;
wire [5:0] osd_pw;
// the switches: kg_soft_switches (LINK 1) or the SW registers of kg_mcu2
wire [111:0] softsw_regs;
// the requests of the drives to the mounter (img_sdc of LINK 1, kg_mcu2 of LINK 2)
wire [7:0] sdc_rd_v, sdc_wr_v, sdc_byte_out_v;
wire [31:0] sdc_sector_v;

generate if (LINK == 1) begin : mcu_link1
kg_mcu #(
    .BURST_MAX_MHZ(BURST_MAX_MHZ),
    .CS_FILTER(3),
    .ENABLE_RTC(0),
    .ENABLE_UART(0),
    .ENABLE_MATRIX(1),
    .ENABLE_DEBUG(0),
    .ENABLE_IMG(1),
    .ENABLE_FILE(1),
    .FILE_CMDS(0),
    .FILE_WR_EACH(1),
    .FILE_TO_ROM(1),
    .ENABLE_FT(0),
    .ENABLE_SD2(0),
    .ENABLE_ESP(0),
    .ENABLE_PS2_CMD(1),
    .ENABLE_FLASHBOOT(0)
) mcu(
    .CLK(clk_bus),
    .N_RESET(~areset),
    
    .MCU_MOSI(mcu_mosi),
    .MCU_MISO(mcu_miso),
    .MCU_SCK(mcu_sck),
    .MCU_SS(mcu_cs_n),
    .MCU_SPI_FT_SS(1'b1),
    .MCU_SPI_SD2_SS(1'b1),
    .MCU_BURST_CS_N(mcu_burst_cs_n),
    .MCU_BURST_READY(mcu_burst_ready),
    
    .MS_X(ms_x),
    .MS_Y(ms_y),
    .MS_Z(ms_z),
    .MS_B(ms_b),
    .MS_UPD(ms_upd),
    
    .KB_STATUS(),
    .KB_DAT0(), .KB_DAT1(), .KB_DAT2(), .KB_DAT3(), .KB_DAT4(), .KB_DAT5(),
    .KB_SCANCODE(ps2_scancode),
    .KB_SCANCODE_UPD(ps2_scancode_upd),
    .XT_SCANCODE(xt_scancode),
    .XT_SCANCODE_UPD(xt_scancode_upd),
    .PS2_COMMAND(ps2_command),
    .PS2_COMMAND_WR(ps2_command_wr),
    
    .JOY_L(joy_l),
    .JOY_R(joy_r),
    .BTNS(mcu_btns),
    
    .RTC_A(8'h0),
    .RTC_DI(8'h0),
    .RTC_DO(),
    .RTC_CS(1'b0),
    .RTC_WR_N(1'b1),
    
    .UART_RX_DATA(),
    .UART_RX_IDX(),
    .UART_TX_DATA(8'h0),
    .UART_TX_WR(1'b0),
    .UART_TX_MODE(1'b0),
    .UART_DLM(8'h0),
    .UART_DLL(8'h0),
    .UART_DLM_WR(1'b0),
    .UART_DLL_WR(1'b0),
    
    .MATRIX_CMD(matrix_cmd),
    .MATRIX_CMD_WR(matrix_cmd_wr),
    
    .DEBUG_ADDR(16'h0),
    .DEBUG_DATA(16'h0),
    
    // rom loader
    .ROMLOADER_ACTIVE(romload_active),
    .ROMLOAD_ADDR(romload_a),
    .ROMLOAD_DATA(romload_d),
    .ROMLOAD_WR(romload_wr),
    .IOCTL_ACTIVE(),
    
    // file loader (unused)
    .FILELOAD_RESET(),
    .FILELOAD_ACTIVE(),
    .FILELOAD_SIZE(),
    .FILELOAD_ADDR(),
    .FILELOAD_DATA(),
    .FILELOAD_WR(),
    
    // ft812
    .FT_SPI_ON(),
    .FT_VGA_ON(),
    .FT_RESET(),
    .FT_SCK(),
    .FT_MOSI(),
    .FT_MISO(1'b0),
    .FT_CS_N(),
    
    // sd2
    .SD2_SCK(),
    .SD2_MOSI(),
    .SD2_MISO(1'b0),
    .SD2_CS_N(),
    
    // hw setup
    .HWID(hwid),
    .DVI_ONLY(mcu_dvi_only),
    
    // soft switches, osd
    .SOFTSW_COMMAND(softsw_command),    
    .OSD_COMMAND(osd_command),
    
    // file mounter
    .IMG_MOUNTED(img_mounted),
    .IMG_SIZE(img_size),
    .IMG_DATA_WR(img_data_wr),
    .IMG_DATA_ADDR(img_data_addr),
    .IMG_DATA(img_data),
    .IMG_RESULT_WR(img_result_wr),
    .IMG_RESULT(img_result),
    .IMG_SUM(img_sum),
    .IMG_Q_WR(img_q_wr),
    .IMG_Q_DI(img_q_di),
    .IMG_Q_ACK(img_q_ack),
    .IMG_PHYS_WR(img_phys_wr),
    .IMG_PHYS(img_phys),
    .IMG_FLUSH(),
    
    // esp
    .ESP_UART_TX_DATA(),
    .ESP_UART_TX_WR(),
    .ESP_UART_RX_DATA(8'h0),
    .ESP_UART_RX_WR(1'b0),
    .ESP_UART_RX_ACK(),
    
    // flashboot
    .FLASHBOOT_START(1'b0),
    .FLASHBOOT_COREID(5'd0),
    
    .BUSY(mcu_busy)
);
end else begin : mcu_link2
    // the v2 events as the toggles of v1 (system takes a change of them)
    wire [7:0] l2_ps2_code, l2_ms_x, l2_ms_y, l2_ms_z, l2_ms_b;
    wire l2_ps2_kind, l2_ps2_wr, l2_ms_wr;
    wire [5:0] l2_btns;
    wire [1:0] l2_ld_kind;
    wire l2_ld_active, l2_ld_wr;
    wire [31:0] l2_ld_addr;
    wire [7:0] l2_ld_data;
    wire [15:0] l2_joy_l, l2_joy_r;
    reg [7:0] ps2_r = 8'd0, xt_r = 8'd0;
    reg ps2_t = 1'b0, xt_t = 1'b0, ms_t = 1'b0;
    always @(posedge clk_bus) begin
        if (l2_ps2_wr && !l2_ps2_kind) begin ps2_r <= l2_ps2_code; ps2_t <= ~ps2_t; end
        if (l2_ps2_wr && l2_ps2_kind) begin xt_r <= l2_ps2_code; xt_t <= ~xt_t; end
        if (l2_ms_wr) ms_t <= ~ms_t;
    end
    assign ps2_scancode = ps2_r;
    assign ps2_scancode_upd = ps2_t;
    assign xt_scancode = xt_r;
    assign xt_scancode_upd = xt_t;
    assign ms_x = l2_ms_x;
    assign ms_y = l2_ms_y;
    assign ms_z = l2_ms_z[3:0];
    assign ms_b = l2_ms_b[2:0];
    assign ms_upd = ms_t;
    assign mcu_btns = l2_btns[1:0];
    assign joy_l = l2_joy_l[12:0];
    assign joy_r = l2_joy_r[12:0];
    // the ROMs of the core file (LD kind 0) into the BIOS loader
    assign romload_active = l2_ld_active && l2_ld_kind == 2'd0;
    assign romload_wr = l2_ld_wr && l2_ld_kind == 2'd0;
    assign romload_a = l2_ld_addr;
    assign romload_d = l2_ld_data;
    assign hwid = 8'd0;
    assign softsw_command = 16'd0;
    assign osd_command = 16'd0;

    kg_mcu2 #(
        .SW_N(14),
        .SW_INIT(112'h0000_0000_0000_0000_0001_0001_0000),
        .CS_FILTER(3),
        .ENABLE_OSD(1),
        .ENABLE_IMG(1),        // HDD0 / HDD1 (slots 0, 1), FDD A / B (2, 3)
        .IMG_OUT_LATENCY(3),
        .ENABLE_AUX(1),        // the level meters of the dot matrix
        .ENABLE_FT(0),
        .ENABLE_SD2(0)         // the second card belongs to the SoC
    ) mcu2(
        .CLK(clk_bus),
        .N_RESET(~areset),

        .MCU_SCK(mcu_sck),
        .MCU_MOSI(mcu_mosi),
        .MCU_MISO(mcu_miso),
        .MCU_SS(mcu_cs_n),
        .MCU_INT(mcu_burst_ready),
        .MCU_SPI_FT_SS(1'b1),
        .MCU_SPI_SD2_SS(1'b1),

        .SW(softsw_regs), .SW_WR(), .SW_INDEX(), .SW_VALUE(), .HW_ID(), .DVI_ONLY(mcu_dvi_only),
        .CORE_BUILD(), .FW_BUILD(), .BUSY(mcu_busy), .BTNS(l2_btns), .RELOAD_REQ(1'b0), .RELOAD_CORE(8'd0),

        .KBD(), .KBD_WR(), .PS2_CODE(l2_ps2_code), .PS2_KIND(l2_ps2_kind), .PS2_WR(l2_ps2_wr),
        .MS_X(l2_ms_x), .MS_Y(l2_ms_y), .MS_Z(l2_ms_z), .MS_B(l2_ms_b), .MS_WR(l2_ms_wr),
        .JOY_L(l2_joy_l), .JOY_R(l2_joy_r), .JOY_WR(),
        .PS2_CMD(ps2_command), .PS2_CMD_WR(ps2_command_wr),

        .LD_KIND(l2_ld_kind), .LD_SLOT(), .LD_SIZE(), .LD_START(), .LD_ACTIVE(l2_ld_active), .LD_END(),
        .LD_ADDR(l2_ld_addr), .LD_DATA(l2_ld_data), .LD_WR(l2_ld_wr), .LD_READY(1'b1),

        .OSD_WR(osd_wr), .OSD_WADDR(osd_waddr), .OSD_WDATA(osd_wdata), .OSD_EN(osd_en),
        .OSD_FG(osd_fg), .OSD_BG(osd_bg), .OSD_ALPHA(osd_alpha), .OSD_PX(osd_px), .OSD_PY(osd_py),
        .OSD_PW(osd_pw), .OSD_PH(osd_ph), .OSD_PLACE(osd_place), .OSD_ZOOM(osd_zoom),

        .SDC_IMG_MOUNTED(sdc_img_mounted), .SDC_IMG_SIZE(sdc_img_size),
        .SDC_RD(sdc_rd_v), .SDC_WR(sdc_wr_v), .SDC_SECTOR(sdc_sector_v),
        .SDC_BUSY(sdc_busy), .SDC_DONE(sdc_done), .SDC_ERROR(sdc_error), .SDC_SLOT(sdc_slot),
        .SDC_BYTE_IN_STROBE(sdc_byte_in_strobe), .SDC_BYTE_ADDR(sdc_byte_addr),
        .SDC_BYTE_IN_DATA(sdc_byte_in_data), .SDC_BYTE_OUT_DATA(sdc_byte_out_v),
        .IMG_WP(), .IMG_PHYS_WR(img_phys_wr), .IMG_PHYS(img_phys), .IMG_FLUSH(), .FDD_CHNG_WR(), .FDD_CHNG(),
        .FDD_CHNG_REQ(1'b0), .FDD_CHNG_DS(2'd0),
        .BK_MOUNT(1'b0), .BK_FLUSHED(1'b0), .BK_SLOT(3'd0), .BK_SIZE(32'd0), .BK_KIND(8'd0), .BK_RESULT(8'd0),
        .IMG_ACTIVE(sdc_active),

        .PORT_OUT_DATA(), .PORT_OUT_WR(), .PORT_OUT_READY(4'b1111), .PORT_IN_DATA(32'd0), .PORT_IN_WR(4'd0),
        .PORT_CFG(128'd0), .PORT_IN_FULL(), .PORT_STAT(), .PORT_STAT_WR(),
        .RTC_A(8'd0), .RTC_DI(8'd0), .RTC_CS(1'b0), .RTC_WR_N(1'b1), .RTC_DO(),
        .MATRIX_CMD(matrix_cmd), .MATRIX_CMD_WR(matrix_cmd_wr), .DEBUG_ADDR(16'd0), .DEBUG_DATA(16'd0),

        .FT_SPI_ON(), .FT_VGA_ON(), .FT_RESET(), .FT_SCK(), .FT_MOSI(), .FT_MISO(1'b0), .FT_CS_N(),
        .SD2_SCK(), .SD2_MOSI(), .SD2_MISO(1'b0), .SD2_CS_N()
    );
end endgenerate

assign sdc_rd_v = {4'b0000, fdd_rd, hdf_rd};
assign sdc_wr_v = {4'b0000, fdd_wr, hdf_wr};
assign sdc_sector_v = (hdf_rd != 2'b00 || hdf_wr != 2'b00) ? hdf_sector : fdd_sector; // the lower slots go first
assign sdc_byte_out_v = fdd_own ? fdd_byte_out_data : hdf_byte_out_data;

generate if (LINK == 1) begin : img_link1
img_sdc #(
    .OUT_LATENCY(3),
    .TIMEOUT(24'd10000000), // ~200ms at 50MHz
    .RETRIES(2'd3)
) u_img_sdc(
    .clk(clk_bus),
    .reset(areset),

    .img_mounted(img_mounted),
    .img_size(img_size),
    .img_data_wr(img_data_wr),
    .img_data_addr(img_data_addr),
    .img_data(img_data),
    .img_result_wr(img_result_wr),
    .img_result(img_result),
    .img_sum(img_sum),
    .img_q_wr(img_q_wr),
    .img_q_di(img_q_di),
    .img_q_ack(img_q_ack),

    .sdc_img_mounted(sdc_img_mounted),
    .sdc_img_size(sdc_img_size),
    .sdc_rd(sdc_rd_v),
    .sdc_wr(sdc_wr_v),
    .sdc_sector(sdc_sector_v),
    .sdc_busy(sdc_busy),
    .sdc_done(sdc_done),
    .sdc_error(sdc_error),
    .sdc_slot(sdc_slot),
    .sdc_byte_in_strobe(sdc_byte_in_strobe),
    .sdc_byte_addr(sdc_byte_addr),
    .sdc_byte_in_data(sdc_byte_in_data),
    .sdc_byte_out_data(sdc_byte_out_v),
    .active(sdc_active)
);
end endgenerate


wire hdd0_dev0_en = (kb_hdd0_mode != 2'd2);
wire core_sd_cs_n;
assign sd_cs_n = (kb_hdd0_mode == 2'd1) ? 1'b1 : core_sd_cs_n;

hdf_ata #(
    .DEF_HEADS(5'd16),
    .DEF_SPT(8'd63),
    .SYNC_BUS(1)
) u_hdf_ata(
    .clk(clk_bus),
    .reset(areset),
    .ata_reset(cpu_reset), // the CPU reset: reset, and the 8042 reset (Ctrl+Alt+Del of DOS)
    .dev0_en(hdd0_dev0_en),
    .dev(),
    .dev1_here(),

    .a(ide_a[2:0]),
    .cs_n({ ~(ide_cs[0] & ide_a[3]), ~(ide_cs[0] & ~ide_a[3]) }),
    .rd_n(~(ide_cs[0] & ~ide_we)),
    .wr_n(~(ide_cs[0] & ide_we)),
    .din(ide_dat_o),
    .dout(hdf_dout),

    .img_mounted(sdc_img_mounted[1:0]),
    .img_size(sdc_img_size),
    .sdc_rd(hdf_rd),
    .sdc_wr(hdf_wr),
    .sdc_sector(hdf_sector),
    .sdc_busy(sdc_busy & hdf_own),
    .sdc_done(sdc_done & hdf_own),
    .sdc_error(sdc_error),
    .sdc_byte_in_strobe(sdc_byte_in_strobe & hdf_own),
    .sdc_byte_addr(sdc_byte_addr),
    .sdc_byte_in_data(sdc_byte_in_data),
    .sdc_byte_out_data(hdf_byte_out_data),
    .led()
);

assign ide_dat_i = hdf_dout;
assign ide_int = 2'b00;

//---------- Floppy drives ------------
// fdd_port (rtl/fdd) at 3F0h-3F5h: a sector port for the BIOS (no 765: the SoC has no DMA).
// Drives A and B: slots 2 and 3 of img_sdc (PHYS_FDD: or a physical drive of the floppy
// connector, pcxt_fdd_phys).

fdd_port #(.PHYS(PHYS_FDD)) u_fdd(
	.clk(clk_bus),
	.reset(areset),

	.cs(fdc_cs),
	.we(fdc_we),
	.a(fdc_a),
	.din(fdc_dat_o),
	.dout(fdc_dat_i),

	.img_mounted(sdc_img_mounted[3:2]),
	.img_size(sdc_img_size),
	.sdc_rd(fdd_rd),
	.sdc_wr(fdd_wr),
	.sdc_sector(fdd_sector),
	.sdc_busy(sdc_busy & fdd_own),
	.sdc_done(sdc_done & fdd_own),
	.sdc_error(sdc_error),
	.sdc_byte_in_strobe(sdc_byte_in_strobe & fdd_own),
	.sdc_byte_addr(sdc_byte_addr),
	.sdc_byte_in_data(sdc_byte_in_data),
	.sdc_byte_out_data(fdd_byte_out_data),

	.img_phys_wr(img_phys_wr),
	.img_phys(img_phys),
	.fdd_in(fdd_in),
	.fdd_out(fdd_out)
);

kg_sync #(.W(1)) u_sync_dvi(
    .clk(clk_vga),
    .d(mcu_dvi_only),
    .q(dvi_only)
);

//---------- Soft switches ------------

wire kb_reset, kb_nmi, kb_fake286, kb_joyswap, kb_midi, kb_adlibhide;
wire [2:0] kb_speed;
wire [1:0] kb_isawait;
wire [1:0] kb_hdd0_mode;

// register n = OSD item n of core*.json; the file items (HDD0 8, HDD1 9, FDD A 10, FDD B 11)
// have no register value
generate if (LINK == 1) begin : sw_link1
kg_soft_switches #(
    .N(14),
    .INIT(112'h0000_0000_0000_0000_0001_0001_0000)
) u_softsw(
    .clk(clk_bus),
    .command(softsw_command),
    .regs(softsw_regs),
    .upd()
);
end endgenerate

assign kb_speed     = softsw_regs[0*8 +: 3];
assign kb_isawait   = softsw_regs[1*8 +: 2];
assign kb_fake286   = softsw_regs[2*8];
assign kb_joyswap   = softsw_regs[3*8];
assign kb_midi      = softsw_regs[4*8];
assign kb_adlibhide = softsw_regs[5*8];
assign kb_hdd0_mode = softsw_regs[6*8 +: 2];
assign kb_boot_c    = softsw_regs[7*8];   // Boot: 0 A: first, 1 C: first
assign kb_nmi       = softsw_regs[12*8];
assign kb_reset     = softsw_regs[13*8];

// --------- BIOS ROM loader ------------

wire [13:0] bios_addr;
wire [15:0] bios_din;
wire bios_wr;
wire bios_loaded;
wire bios_req;

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

// --------- OSD ------------

generate if (LINK == 1) begin : osd_link1
overlay #(
    .H_OFFSET(104),
    .V_OFFSET(32)
) overlay(
	.CLK(clk_vga),
	.RGB_I({core_r, 2'b00, core_g, 2'b00, core_b, 2'b00}),
	.RGB_O(vga_rgb),
	.HSYNC_I(core_hs),
	.VSYNC_I(core_vs),
	.OSD_COMMAND(osd_command)
);

assign vga_hs = ~core_hs_d;
assign vga_vs = ~core_vs_d;
assign vga_blank = core_hb || core_vb_frame;
end else begin : osd_link2
// the bitmap OSD of link v2: centred in de, 2 clocks of latency with its syncs and de; the syncs
// and blank of the core are those delayed as its pixels (VGA_*_D)
wire osd_de;
kg_l2_osd_overlay osd(
    .wclk(clk_bus),
    .osd_wr(osd_wr), .osd_waddr(osd_waddr), .osd_wdata(osd_wdata), .osd_en(osd_en),
    .osd_fg(osd_fg), .osd_bg(osd_bg), .osd_alpha(osd_alpha), .osd_px(osd_px), .osd_py(osd_py),
    .osd_pw(osd_pw), .osd_ph(osd_ph), .osd_place(osd_place), .osd_zoom(osd_zoom),
    .icon_on(8'd0), .icon_act(8'd0),
    .clk(clk_vga),
    .rgb_i({core_r, 2'b00, core_g, 2'b00, core_b, 2'b00}),
    .hs_i(~core_hs_d), .vs_i(~core_vs_d), .de_i(~(core_hb || core_vb_frame)),
    .rgb_o(vga_rgb), .hs_o(vga_hs), .vs_o(vga_vs), .de_o(osd_de)
);
assign vga_blank = ~osd_de;
end endgenerate
assign vga_reset = core_vga_reset;

// ---------- misc -----------------------

reg   [4:0] cpu_speed;
always @(*) begin
	case (kb_speed)
		1: cpu_speed = 1; // /2
		2: cpu_speed = 2; // /3
		3: cpu_speed = 3; // /4
		4: cpu_speed = 7; // /8
		5: cpu_speed = 15;// /16
		6: cpu_speed = 31;// /32
		default: cpu_speed = 0;
	endcase
end

always @(posedge clk_cpu) reset <= kb_reset | !bios_loaded | mcu_btns[1];

reg  NMI;
integer nmi_cnt = 0;
reg btn_nmi_d;
always @(posedge clk_25) begin
	btn_nmi_d <= kb_nmi;
	if (nmi_cnt == 0) begin
		if (~btn_nmi_d & kb_nmi) nmi_cnt <= 24'hFFFFFF;
		NMI <= 0;
	end else begin
		NMI <= 1;
		nmi_cnt <= nmi_cnt - 1'd1;
	end
end

wire com1_Rx, com1_Tx;
wire mpu_Rx, mpu_Tx;
wire UART_RX = 1'b1; // todo
wire UART_TX;
assign UART_TX = kb_midi ? mpu_Tx : com1_Tx;
assign com1_Rx = kb_midi ? 1'b1 : UART_RX;
assign mpu_Rx = kb_midi ? UART_RX : 1'b1;
assign midi_tx = UART_TX; // todo

localparam  CPU_MHZ = 50;

reg         cen_opl2; // 3.58MHz
reg  [15:0] cen_opl2_cnt;
wire [15:0] cen_opl2_cnt_next = cen_opl2_cnt + 16'd358;
always @(posedge clk_cpu) begin
	cen_opl2 <= 0;
	cen_opl2_cnt <= cen_opl2_cnt_next;
	if (cen_opl2_cnt_next >= (CPU_MHZ * 100)) begin
		cen_opl2 <= 1;
		cen_opl2_cnt <= cen_opl2_cnt_next - (CPU_MHZ * 100);
	end
end

reg         cen_44100;
reg  [31:0] cen_44100_cnt;
wire [31:0] cen_44100_cnt_next = cen_44100_cnt + 16'd44100;
always @(posedge clk_cpu) begin
	cen_44100 <= 0;
	cen_44100_cnt <= cen_44100_cnt_next;
	if (cen_44100_cnt_next >= (CPU_MHZ*1000000)) begin
		cen_44100 <= 1;
		cen_44100_cnt <= cen_44100_cnt_next - (CPU_MHZ*1000000);
	end
end

reg fake286_r, fake286_r2;
always @(posedge clk_cpu) { fake286_r, fake286_r2 } <= { kb_fake286, fake286_r };

reg   [7:0] joy = 8'hFF;
wire        joy_wr;
reg   [7:0] joy_cnt = 8'hFF;
reg   [8:0] joy_cnt_ce_cnt;
reg         joy_cnt_ce;

always @(posedge clk_cpu) begin
    // todo: раскурить эту поеботину
	/*joy[7:4] <= joyswap ? ~{joy_r[5:4], joy_l[5:4]} : ~{joy_l[5:4], joy_r[5:4]};
	joy_cnt_ce_cnt <= joy_cnt_ce_cnt + 1'd1;
	if (joy_cnt_ce_cnt == {cpu_speed, {4{1'b1}}}) joy_cnt_ce_cnt <= 0;
	joy_cnt_ce <= joy_cnt_ce_cnt == 0;
	if (joy_wr) begin
		joy[3:0] <= 4'b1111;
		joy_cnt <= 0;
		joy_cnt_ce_cnt <= 1;
		joy_cnt_ce <= 0;
	end else if (joy_cnt != 8'hFF) begin
		if (joy_cnt == {~joy1[15], joy1[14:8]}) joy[0] <= 0;
		if (joy_cnt == {~joy1[ 7], joy1[ 6:0]}) joy[1] <= 0;
		if (joy_cnt == {~joy0[15], joy0[14:8]}) joy[2] <= 0;
		if (joy_cnt == {~joy0[ 7], joy0[ 6:0]}) joy[3] <= 0;
		if (joy_cnt_ce) joy_cnt <= joy_cnt + 1'd1;
	end else joy[3:0] <= 0;*/
end

endmodule

