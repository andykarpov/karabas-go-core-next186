`timescale 1ns / 1ns
`default_nettype none

module karabas_186 #(
    parameter BURST_MAX_MHZ = 0 // see mcu.vhd
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
    output wire         mcu_burst_ready
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
assign clk_adc = clk_25;
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
wire core_hs, core_vs, core_blank, core_vga_reset, core_vb, core_hb;
wire [15:0] ide_dat_o, ide_dat_i;
wire [3:0] ide_a;
wire [1:0] ide_cs;
wire ide_we;
reg [1:0] ide_int;

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
    .VGA_HBLANK(core_hb),
	 .VGA_RESET(core_vga_reset),
    .frame_on(),

    .sdr_n_CS_WE_RAS_CAS({sdr_cs_n, sdr_we_n, sdr_ras_n, sdr_cas_n}),
    .sdr_BA(sdr_ba),
    .sdr_ADDR(sdr_a),
    .sdr_DATA(sdr_dq),
    .sdr_DQM(sdr_dqm),

    .LED(),

    .BTN_RESET(reset),
    .BTN_NMI(NMI),

    .RS232_DCE_RXD(),
    .RS232_DCE_TXD(),
    .RS232_EXT_RXD(com1_Rx),
    .RS232_EXT_TXD(com1_Tx),
    .MPU_RX(mpu_Rx),
    .MPU_TX(mpu_Tx),

    .SD_n_CS(sd_cs_n),
    .SD_DI(sd_di),
    .SD_CK(sd_clk),
    .SD_DO(sd_do),

    .CDDA_L(cdda_l),
    .CDDA_R(cdda_r),

    .AUD_L(pwm_audio_l),
    .AUD_R(pwm_audio_r),
    .LAUDIO(audio_l),
    .RAUDIO(audio_r),

    .RS232_HOST_RXD(),
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

    .adc_l(adc_l),
    .adc_r(adc_r)
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

kg_mcu #(
    .BURST_MAX_MHZ(BURST_MAX_MHZ),
    .CS_FILTER(3),
    .ENABLE_RTC(0),
    .ENABLE_UART(0),
    .ENABLE_MATRIX(0),
    .ENABLE_DEBUG(0),
    .ENABLE_IMG(0),
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
    
    .MATRIX_CMD(24'h0),
    .MATRIX_CMD_WR(1'b0),
    
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
    
    // file mounter (unused for now until task 2)
    .IMG_MOUNTED(),
    .IMG_SIZE(),
    .IMG_DATA_WR(),
    .IMG_DATA_ADDR(),
    .IMG_DATA(),
    .IMG_RESULT_WR(),
    .IMG_RESULT(),
    .IMG_SUM(),
    .IMG_Q_WR(1'b0),
    .IMG_Q_DI(24'd0),
    .IMG_Q_ACK(),
    .IMG_PHYS_WR(),
    .IMG_PHYS(),
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

kg_sync #(.W(1)) u_sync_dvi(
    .clk(clk_vga),
    .d(mcu_dvi_only),
    .q(dvi_only)
);

//---------- Soft switches ------------

wire kb_reset, kb_nmi, kb_fake286, kb_joyswap, kb_midi, kb_adlibhide;
wire [2:0] kb_speed;
wire [1:0] kb_isawait;

wire [63:0] softsw_regs;
kg_soft_switches #(
    .N(8),
    .INIT(64'h0000_0001_0001_0000)
) u_softsw(
    .clk(clk_bus),
    .command(softsw_command),
    .regs(softsw_regs),
    .upd()
);

assign kb_speed     = softsw_regs[0*8 +: 3];
assign kb_isawait   = softsw_regs[1*8 +: 2];
assign kb_fake286   = softsw_regs[2*8];
assign kb_joyswap   = softsw_regs[3*8];
assign kb_midi      = softsw_regs[4*8];
assign kb_adlibhide = softsw_regs[5*8];
assign kb_nmi       = softsw_regs[6*8];
assign kb_reset     = softsw_regs[7*8];

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

assign vga_hs = ~core_hs;
assign vga_vs = ~core_vs;
assign vga_blank = core_hb || core_vb;
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

