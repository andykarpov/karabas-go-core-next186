`default_nettype none

module bios_loader(
	input wire clk,
	input wire clk_sdr,
	input wire reset,
	
	input wire active,
	input wire [31:0] addr,
	input wire [7:0] din,
	input wire wr,
	
	output reg [13:0] bios_addr,
	output reg [15:0] bios_din,
	output reg bios_wr,
	input wire bios_req,
	
	output reg bios_loaded
);

initial bios_wr = 0;
initial bios_loaded = 0;

reg [15:0] bios_tmp[0:63];
reg [7:0]  dat;
reg        bios_reqD = 0;
reg [2:0]  activeD = 3'b000;
reg [2:0]  wrD = 3'b000;
reg [31:0] addrD;
reg [7:0]  dinD = 8'hFF;

always @(posedge clk_sdr) begin

	activeD <= {activeD[1:0], active};
	wrD <= {wrD[1:0], wr};
	addrD <= addr;
	dinD <= din;
	
	if (activeD[2:1] == 2'b01) begin // rising edge
		bios_addr <= 0;
		bios_wr <= 0;
	end

	if (activeD[2:1] == 2'b10) bios_loaded <= 1; // falling edge

	if ((activeD[2:1] == 2'b11) & (wrD[2:1] == 2'b01)) begin // rising edge
		if (addrD[0]) begin
			bios_tmp[addrD[6:1]] <= {dinD, dat};
			if (&addrD[5:1]) bios_wr <= 1;
		end else begin
			dat <= dinD;
		end
	end

	bios_reqD <= bios_req;
	if (bios_reqD & ~bios_req) bios_wr <= 0;

	if ((activeD[2:1] == 2'b11) & bios_req) begin
		bios_addr <= bios_addr + 1'd1;
		bios_din <= bios_tmp[bios_addr[5:0]];
	end
end

endmodule
