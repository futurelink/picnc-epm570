// -----------------------------------------------------------------------------------------
// CPLD pulse generator.
//
// This application works as stepper motor pulse generator and should be controlled by MCU.
//
// Author: Denis Pavlov <futurelink.vl@gmail.com>, 2023-2024
//
// -----------------------------------------------------------------------------------------

module main #(
	parameter DEVICE_ID = 16'h0001,
	parameter PULSEGEN_STEP_HOLD_ADDR = 6'b000001,
	parameter PULSEGEN_DIR_HOLD_ADDR = 6'b000010,
	parameter PULSEGEN_1_ADDR = 4'b0010, // 00110x as well
	parameter PULSEGEN_2_ADDR = 4'b0100, // 01010x as well
	parameter PULSEGEN_3_ADDR = 4'b0110, // 01110x as well
	parameter PULSEGEN_4_ADDR = 4'b1000, // 10010x as well
	parameter INPUTS_ADDR = 6'b100100,
	parameter OUTPUTS_ADDR = 6'b100101
)(
	input  wire        clk,                // Clock input
	input  wire        data_rw,            // Data read/write flag (Read HIGH / Write LOW)
	input  wire        data_ready,         // Data ready signal (Active HIGH)
	input  wire        data_addr,          // Data/address selection
	inout  wire[15:0]  data_io,            // Data port

	input  wire        pulse_buffer_lock,  // Pulse buffer update lock (Active HIGH)
	output reg         pulse_buffer_empty,	// Pulse buffer empty (Active HIGH)
	output wire[3:0]   stepper_pulse,      // Step pulse output
	output wire[3:0]   stepper_dir,		   // Step direction output

	input  wire[15:0]  digital_inputs,     // Digital inputs
	output reg[15:0]   digital_outputs     // Digital outputs
);

	reg[5:0] addr;                         // Address register
	reg[4:0] pulse_period_high;            // Stepgen pulse HIGH length
	reg[4:0] pulse_dir_hold;
	reg[4:0] pulse_dir_hold_cnt;
	reg 		prev_pulse_clk;
	reg		data_ready_reg;
	reg      pulse_buffer_lock_reg;
	reg		prev_data_ready;
	reg[2:0] pulsegen_cs;
	reg		pulsegen_addr;
	reg 		pulsegen_data_ready;
	reg		data_addr_reg;
	reg		data_rw_reg;

	initial begin
		pulsegen_addr = 0;
		pulsegen_cs = 0;
		pulsegen_data_ready = 0;
		pulse_period_high = 0;
		pulse_dir_hold = 0;
		pulse_dir_hold_cnt = 0;
		addr = 0;
		digital_outputs = 0;
		prev_pulse_clk = 0;
		data_ready_reg = 0;
		prev_data_ready = 0;
		pulse_buffer_lock_reg = 0;
		pulse_buffer_empty = 0;
		data_addr_reg = 0;
		data_rw_reg = 0;
	end

	wire[15:0] 	data_out_gen_1, data_out_gen_2, data_out_gen_3, data_out_gen_4;
	wire[3:0] 	step_buffer_empty;
	wire[3:0]	dir_change_flag;

	// Configure IO data bus
	assign data_io[15:0] = data_rw ? 16'hzzzz : 
		(!data_addr ? (
			(addr[5:0] == 6'b000000) ? DEVICE_ID :                       // Read device ID
			(addr[5:2] == PULSEGEN_1_ADDR) ? data_out_gen_1 :            // Read data from Gen 1
			(addr[5:2] == PULSEGEN_2_ADDR) ? data_out_gen_2 :            // Read data from Gen 2
			(addr[5:2] == PULSEGEN_3_ADDR) ? data_out_gen_3 :            // Read data from Gen 3
			(addr[5:2] == PULSEGEN_4_ADDR) ? data_out_gen_4 :            // Read data from Gen 4
			(addr[5:0] == PULSEGEN_STEP_HOLD_ADDR) ? pulse_period_high : // Read pulsegen period high setting
			(addr[5:0] == PULSEGEN_DIR_HOLD_ADDR) ? pulse_dir_hold :	    // Read pulsegen dir hold value
			(addr[5:0] == INPUTS_ADDR) ? digital_inputs :                // Read digital inputs state
			(addr[5:0] == OUTPUTS_ADDR) ? digital_outputs :              // Read digital outputs stat
			16'h0
		) : addr // Read address
	);

	wire pulse_clk; // Divide by 10 (parameter is 4) gives 5Mhz frequency on 50MHz clock
	freq_divider freq_divider(.clk(clk), .out_div_10(pulse_clk)); 

	// On address write mode (data addr is high) when ENABLED (enable is high) - set address,
	// if NOT ENABLED (enable is low) and set to WRITE MODE (data_rw is low) - send digital output 
	// if address is set to outputs' address.
	always @(posedge clk) begin
		data_ready_reg <= (data_ready > prev_data_ready);
		data_addr_reg <= data_addr;
		data_rw_reg <= data_rw;
		pulse_buffer_lock_reg <= pulse_buffer_lock;
	
		if (data_ready_reg && data_rw_reg) begin
			if (data_addr_reg) begin
				// Shrink address from data bus because
				// device only supports 6-bit address.
				if (data_io[5:2] == PULSEGEN_1_ADDR) begin
					pulsegen_cs = 3'd1;
					pulsegen_addr = data_io[0];
				end else if (data_io[5:2] == PULSEGEN_2_ADDR) begin
					pulsegen_cs = 3'd2;
					pulsegen_addr = data_io[0];
				end else if (data_io[5:2] == PULSEGEN_3_ADDR) begin
					pulsegen_cs = 3'd3;
					pulsegen_addr = data_io[0];
				end else if (data_io[5:2] == PULSEGEN_4_ADDR) begin
					pulsegen_cs = 3'd4;
					pulsegen_addr = data_io[0];
				end else begin
					pulsegen_cs = 3'd0;
					pulsegen_addr = 1'b0;
					addr[5:0] <= data_io[5:0];
				end
			end else begin
				if (addr[5:0] == OUTPUTS_ADDR) begin // Write digital outputs state
					digital_outputs[15:0] <= data_io[15:0];
				end else if (addr[5:0] == PULSEGEN_STEP_HOLD_ADDR) begin
					pulse_period_high <= data_io[4:0];
				end else if (addr[5:0] == PULSEGEN_DIR_HOLD_ADDR) begin
					pulse_dir_hold <= data_io[4:0];
				end if (pulsegen_cs)	begin
					pulsegen_data_ready <= 1'b1;
				end
			end
		end else begin
			pulsegen_data_ready <= 1'b0;
		end

		// Start counting dir hold delay
		if (dir_change_flag != 0) begin
			pulse_dir_hold_cnt <= pulse_dir_hold;
		end

 		// Decrement dir hold counter
		if (pulse_clk > prev_pulse_clk) begin
			if (pulse_dir_hold_cnt != 0) begin
				pulse_dir_hold_cnt <= pulse_dir_hold_cnt - 1'b1;
			end
		end

		// Generate interrupt when all pulse channels' buffers are empty.
		// If buffer lock flag is set then we can't generate interrupts.
		// This flag is usually set by interrupt handler before buffer data send.
		pulse_buffer_empty <= (step_buffer_empty == 4'b1111) || pulse_buffer_lock;

		// Save state for next clock pulse
		prev_pulse_clk <= pulse_clk;
		prev_data_ready <= data_ready;
	end
	
	// Generate interrupt signal
	// -------------------------
	//wire pulsegen_data_ready;
	//assign pulsegen_data_ready = data_ready_reg && !data_addr;
	
	wire pulse_dir_hold_lock;
	assign pulse_dir_hold_lock = (pulse_dir_hold_cnt != 0) || (dir_change_flag != 0);

	pulsegen pulsegen_1(
		.clk(clk),
		.data_cs(pulsegen_cs == 1),
		.data_addr(pulsegen_addr),
		.data_rw(data_rw_reg),
		.data_ready(pulsegen_data_ready),
		.data_in(data_io[15:0]),
		.data_out(data_out_gen_1),
		.pulse_clk(pulse_clk),
		.pulse(stepper_pulse[0]),
		.pulse_dir(stepper_dir[0]),
		.pulse_buffer_lock(pulse_buffer_lock_reg),
		.pulse_buffer_empty(step_buffer_empty[0]),
		.pulse_period_high(pulse_period_high),
		.pulse_dir_hold(pulse_dir_hold),
		.pulse_dir_change(dir_change_flag[0]),
		.pulse_dir_hold_lock(pulse_dir_hold_lock)
	);

	pulsegen pulsegen_2(
		.clk(clk),
		.data_cs(pulsegen_cs == 2),
		.data_addr(pulsegen_addr),
		.data_rw(data_rw_reg),
		.data_ready(pulsegen_data_ready),
		.data_in(data_io[15:0]),
		.data_out(data_out_gen_2),
		.pulse_clk(pulse_clk),
		.pulse(stepper_pulse[1]),
		.pulse_dir(stepper_dir[1]),
		.pulse_buffer_lock(pulse_buffer_lock_reg),		
		.pulse_buffer_empty(step_buffer_empty[1]),
		.pulse_period_high(pulse_period_high),
		.pulse_dir_hold(pulse_dir_hold),
		.pulse_dir_change(dir_change_flag[1]),
		.pulse_dir_hold_lock(pulse_dir_hold_lock)
	);

	pulsegen pulsegen_3(
		.clk(clk),
		.data_cs(pulsegen_cs == 3),
		.data_addr(pulsegen_addr),
		.data_rw(data_rw_reg),
		.data_ready(pulsegen_data_ready),
		.data_in(data_io[15:0]),
		.data_out(data_out_gen_3),
		.pulse_clk(pulse_clk),
		.pulse(stepper_pulse[2]),
		.pulse_dir(stepper_dir[2]),
		.pulse_buffer_lock(pulse_buffer_lock_reg),		
		.pulse_buffer_empty(step_buffer_empty[2]),
		.pulse_period_high(pulse_period_high),
		.pulse_dir_hold(pulse_dir_hold),
		.pulse_dir_change(dir_change_flag[2]),
		.pulse_dir_hold_lock(pulse_dir_hold_lock)		
	);

	pulsegen pulsegen_4(
		.clk(clk),
		.data_cs(pulsegen_cs == 4),
		.data_addr(pulsegen_addr),
		.data_rw(data_rw_reg),
		.data_ready(pulsegen_data_ready),
		.data_in(data_io[15:0]),
		.data_out(data_out_gen_4),
		.pulse_clk(pulse_clk),
		.pulse(stepper_pulse[3]),
		.pulse_dir(stepper_dir[3]),
		.pulse_buffer_lock(pulse_buffer_lock_reg),		
		.pulse_buffer_empty(step_buffer_empty[3]),
		.pulse_period_high(pulse_period_high),
		.pulse_dir_hold(pulse_dir_hold),
		.pulse_dir_change(dir_change_flag[3]),
		.pulse_dir_hold_lock(pulse_dir_hold_lock)
	);	

endmodule
