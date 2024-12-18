# ------------------------------------------

set_time_unit ns
set_decimal_places 3

# ------------------------------------------
#

create_clock -period 50MHz -name {clk} [get_ports {clk}]
create_generated_clock -name {pulse_clk} -source {clk} -divide_by 10 {freq_divider|out_div_10}

set_min_delay -to [get_ports {digital_outputs*}] 0.1ns
set_max_delay -to [get_ports {digital_outputs*}] 23ns

set_min_delay -to [get_ports {stepper_*}] 0.05ns
set_max_delay -to [get_ports {stepper_*}] 19ns

set_min_delay -from [get_ports {data_io*}] 0.05ns
set_max_delay -from [get_ports {data_io*}] 19ns

set_min_delay -to [get_ports {data_io*}] 0.05ns
set_max_delay -to [get_ports {data_io*}] 23ns

set_min_delay -from [get_ports {data_rw*}] 0.05ns
set_max_delay -from [get_ports {data_rw*}] 19ns

set_min_delay -from [get_ports {data_ready*}] 0.05ns
set_max_delay -from [get_ports {data_ready*}] 19ns

set_min_delay -from [get_ports {data_addr*}] 0.05ns
set_max_delay -from [get_ports {data_addr*}] 19ns

set_min_delay -from {pulse_buffer_lock} 0.05ns
set_max_delay -from {pulse_buffer_lock} 19ns

set_min_delay -to {pulse_buffer_empty} 0.05ns
set_max_delay -to {pulse_buffer_empty} 19ns

