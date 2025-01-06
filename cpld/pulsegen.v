// ------------------------------------------
// Pulse generator for stepper motor project.
//
// This module receives 3 clocks: global CPLD clock, speed pulsing clock (length of pulse LOW)
// and fast pulsing clock which determines a length of step pulse (pulse HIGH).
// ------------------------------------------
// Generally the idea is to generate speed pulsing clock from MCU which can save a resolution bits
// of LOW period (which is LOW pulse period * number of periods (0-65535). In a meanwhile HIGH pulse clock
// if way faster so HIGH signal can be = HIGH pulse period * (0-15). Which means that in 1Mhz HIGH pulse clock 
// step pulse length can be 0us - 15us - good enough for modern step motor drivers.
// ------------------------------------------
//
module pulsegen(
	input  wire       clk,					// Global clock
	input  wire       data_rw,				// Read/write signal
	input  wire       data_cs,				// Generator selection signal
	input  wire       data_ready,			// Data load signal
	input  wire       data_addr,			// Data input select (0 - load pulse low, 1 - pulses count)
	input  wire[15:0] data_in,				// Data input
	output wire[15:0] data_out,
	input  wire       pulse_clk,			// Pulse carry clock input
	output reg        pulse,				// Pulse output
	output reg        pulse_dir,			// Dir output
	input  wire       pulse_buffer_lock,  // Pulse buffer lock
	output reg        pulse_buffer_empty, // MCU should detect rising edge and push new data
	input  wire[4:0]  pulse_period_high,  // Pulse high configuration
	input  wire[4:0]  pulse_dir_hold,     // Pulse dir change hold interval
	input  wire       pulse_dir_hold_lock,
	output reg			pulse_dir_change
);

	reg 			prev_pulse_clk;

	// Current settings registers	& buffers
	reg[9:0]		pulses_count;				// Pulses counter (0-1023 pulses), max freq 1.023MHz on 1msec update interval
	reg[9:0]		pulses_count_buffer;

	reg[15:0]	pulse_period_low;	
	reg[15:0]	pulse_period_low_buffer;

	reg			pulse_dir_buffer;
	
	// Counters
	reg[4:0] 	pulse_period_high_cnt;	// Pulse high-level couner (high level - 1-16 x pulse_clk length)
	reg[15:0] 	pulse_period_low_cnt;	// Pulse low-level counter (low level - 1-65535 x pulse_clk length)

	initial begin
		prev_pulse_clk = 0;
		pulses_count = 0;
		pulses_count_buffer = 0;
		pulse_dir = 0;
		pulse_dir_buffer = 0;
		pulse_period_low_buffer = 0;
		pulse_period_high_cnt = 0;
		pulse_period_low_cnt = 0;
		pulse_dir_change = 0;
		pulse_buffer_empty = 0;
		pulse = 0;
	end

	assign data_out = data_rw ? (data_addr ? {6'h0, pulses_count[9:0]} : pulse_period_low[15:0]) : 16'b0;

	always @(posedge clk) begin
		// Load data into buffer
		if (data_ready) begin
			if (data_cs && data_rw) begin
				if (data_addr) begin
					pulse_dir_buffer <= data_in[15];
					pulses_count_buffer <= data_in[9:0];
					pulse_buffer_empty <= 1'b0;
				end else begin
					pulse_period_low_buffer <= data_in[15:0];
				end
			end
		end

		if ((pulses_count == 0) && !pulse_buffer_lock) begin
			// Get data from buffer into work if buffer is unlocked
			// When enabled and has pulses to count
			pulse_period_high_cnt <= pulse_period_high;
			pulse_period_low <= pulse_period_low_buffer;
			pulses_count <= pulses_count_buffer;
			pulses_count_buffer <= 0;
			pulse_buffer_empty <= 1'b1;

			// Direction change flag set for synchronized dir-hold delay on all channels
			pulse_dir <= pulse_dir_buffer;
			pulse_dir_change <= (pulse_dir != pulse_dir_buffer);
		end

		// Reset direction change in next tick
		if (pulse_dir_change) begin
			pulse_dir_change <= 0;
		end

		if (pulse_clk > prev_pulse_clk) begin
			// Generate pulses when dir-hold is done
			if ((pulses_count != 0) && !pulse_dir_hold_lock && !pulse_dir_change) begin
				if (pulse_period_high_cnt == 0) begin		// Low level counter ended up
					if (pulse_period_low_cnt == 0) begin	// Start new pulse
						pulses_count <= pulses_count - 1'b1;
						pulse_period_high_cnt <= pulse_period_high;
						pulse_period_low_cnt <= pulse_period_low;
						pulse <= 1'b0;
					end else begin
						pulse_period_low_cnt <= pulse_period_low_cnt - 1'b1;
						pulse <= 1'b0;
					end
				end else begin
					pulse_period_high_cnt <= pulse_period_high_cnt - 1'b1;
					pulse_period_low_cnt <= pulse_period_low;
					pulse <= 1'b1;
				end
			end else begin
				pulse <= 1'b0;
			end 
		end
		
		// Save state for next clock pulse
		prev_pulse_clk <= pulse_clk;
	end

endmodule
