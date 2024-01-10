create_clock -name clk -period 37.037 -waveform {0 18.518} [get_ports {clk_26}]
# create_clock -name ulpi_clk -period 16.667 -waveform {0 8.333} [get_ports {ulpi_clk}]
create_clock -name ulpi_clk -period 16.667 -waveform {0 5.75} [get_ports {ulpi_clk}]

# What does this do ??
set_clock_latency -source 0.4 [get_clocks {ulpi_clk}] 

# set_input_delay -clock ulpi_clk -min 8 [get_ports {ulpi_data ulpi_dir ulpi_nxt}]
# set_output_delay -clock ulpi_clk -min 8 [get_ports {ulpi_data ulpi_stp}]
