module freq_divider(
	input	 wire			clk,					// Global clock	
	output reg			out_div_10			// Output divided by 10
);

reg[2:0] counter;

initial begin
	counter = 3'h0;
	out_div_10 = 0;
end

always @(posedge clk) begin
	if (counter == 3'h0) begin
		counter <= 3'd4;
		out_div_10 <= ~out_div_10;
	end else begin
		counter <= counter - 1'b1;
	end
end

endmodule
