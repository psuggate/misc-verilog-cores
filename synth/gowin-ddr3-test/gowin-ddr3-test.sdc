create_clock -name clk -period 37.037 -waveform {0 18.518} [get_ports {clk_26}]
create_clock -name ulpi_clk -period 16.667 -waveform {0 8.333} [get_ports {ulpi_clk}]
# create_clock -name ulpi_clk -period 16.667 -waveform {0 5.75} [get_ports {ulpi_clk}]

create_clock -name ddr_clk -period 10.000 -waveform {0 5.000} [get_ports {ddr_ck}]


# What does this do ??
# set_clock_latency -source 0.4 [get_clocks {ulpi_clk}] 

set_input_delay -max -clock ulpi_clk 3.5 [get_ports {ulpi_data ulpi_dir ulpi_nxt}]
set_input_delay -min -clock ulpi_clk 1.5 [get_ports {ulpi_data ulpi_dir ulpi_nxt}]

set_output_delay -max -clock ulpi_clk 5 [get_ports {ulpi_data ulpi_stp}]
set_output_delay -min -clock ulpi_clk -5 [get_ports {ulpi_data ulpi_stp}]

# set_output_delay -max -clock ulpi_clk -clock_fall 5 [get_ports {ulpi_data ulpi_stp}]
# set_output_delay -min -clock ulpi_clk -clock_fall -5 [get_ports {ulpi_data ulpi_stp}]
