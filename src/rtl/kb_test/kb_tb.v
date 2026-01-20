`timescale 1ns/1ps
module kb_tb;

reg cs = 1;
reg wr = 0;
reg cmd = 0;
reg [7:0] din;
wire [7:0] dout;
reg clk = 0;
reg reset = 0;
wire i_kb;
wire i_mouse;
wire cpu_rst;

// todo: implement mcu fake signals here
reg [7:0] ps2_scancode, xt_scancode;
reg ps2_scancode_upd = 0;
reg xt_scancode_upd = 0;
reg [7:0] ms_x, ms_y;
reg [3:0] ms_z;
reg [2:0] ms_b;
reg ms_upd = 0;

KB_Mouse_8042 uut(
	.CS(cs),
	.WR(wr),
	.cmd(cmd),
	.din(din),
	.dout(dout),
	.clk(clk),
	.reset(reset),
	.I_KB(i_kb),
	.I_MOUSE(i_mouse),
	.CPU_RST(cpu_rst),
	
	.ps2_kbd_scancode(ps2_scancode),
	.ps2_kbd_scancode_upd(ps2_scancode_upd),
	.xt_kbd_scancode(xt_scancode),
	.xt_kbd_scancode_upd(xt_scancode_upd),
	
	.ms_x(ms_x),
	.ms_y(ms_y),
	.ms_z(ms_z),
	.ms_b(ms_b),
	.ms_upd(ms_upd)
);

task send_command(input reg [7:0] d);
begin
	cs=1; cmd=1; wr=1; din=d; 
	#20;
	wr=0; cs=0;
	#200;
end
endtask

task get_command();
begin
	cs=1; cmd=1; wr=0; din=8'hz; 
	#20;
	wr=0; cs=0;
	#200;
end
endtask

task read_data();
begin
	cs=1; cmd=0; wr=0; din=8'hz; 
	#20;
	wr=0; cs=0;
	#200;
end
endtask

task int_read_data();
begin
	if (i_kb) begin
		cs=1; cmd=0; wr=0; din=8'hz; 
		#20;
		wr=0; cs=0;
		#20;
	end
	#20;
	int_read_data();
end
endtask

task send_data(input reg [7:0] d);
begin
	cs=1; cmd=0; wr=1; din=d; 
	#20;
	wr=0; cs=0;
	#200;
end
endtask

task xt_incoming(input reg [7:0] d);
begin
	xt_scancode_upd <= ~xt_scancode_upd;
	xt_scancode <= d;
	ps2_scancode_upd <= ~ps2_scancode_upd;
	ps2_scancode <= d;
	#200;
end 
endtask

initial begin
#20
clk = 0;
reset = 1;
#20;
reset = 0;
#20

send_command(8'hAE); //enable keyboard
send_command(8'hA7); // disable mouse
send_command(8'h60); send_data(8'h01); // enable kbd interrupt
read_data(); 
send_data(8'hFF); // reset kbd
read_data(); read_data(); read_data(); read_data(); 
send_data(8'hF2); // get id
read_data(); read_data(); read_data(); read_data(); 
send_data(8'hF0); 
read_data(); read_data(); read_data(); read_data(); 
send_data(8'h01); // set scancodeset 1
read_data(); read_data(); read_data(); read_data();

int_read_data();

#10000 $finish();

end

always #10 clk = ~clk;  //clock generation

initial
begin
  $dumpfile("out.vcd");
  $dumpvars(0);

  #10000 $finish;
end

reg [7:0] cnt = 0;
reg [4:0] delay = 0;
always @(posedge clk) begin
	delay <= delay + 1;
	if (delay == 5'b11111) begin
		cnt <= cnt + 1;
		xt_scancode_upd <= ~xt_scancode_upd;
		xt_scancode <= {4'hB, cnt[3:0]};
		ps2_scancode_upd <= ~ps2_scancode_upd;
		ps2_scancode <= {4'hC, cnt[3:0]};
	end
end

//initial
    //$monitor($stime,,,, clk,,,, a1,,,, wr1,, rd1,, din1, dout1,,,, sram_a,, sram_wr_n,, sram_rd_n,,,, sram_d);

endmodule

