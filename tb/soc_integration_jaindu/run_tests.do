# ModelSim DO script to compile and run all 5 testbenches in sequence
vlib work
vmap work work

# Compile all modules and testbenches
vlog -sv ../../rtl/soc_integration_jaindu/display_gpio_peripheral.sv tb_display_gpio_peripheral.sv
vlog -sv ../../rtl/soc_integration_jaindu/soc_bus_interconnect.sv tb_soc_bus_interconnect.sv
vlog -sv ../../rtl/dataflow_memory_rahul/image_bram_dp.sv tb_image_bram_dp.sv
vlog -sv ../../rtl/dataflow_memory_rahul/image_reader.sv tb_image_reader.sv
vlog -sv ../../rtl/soc_integration_jaindu/uart_serial_controller.sv tb_uart_serial_controller.sv

# Run each testbench
vsim -c -do "run -all" tb_display_gpio_peripheral
vsim -c -do "run -all" tb_soc_bus_interconnect
vsim -c -do "run -all" tb_image_bram_dp
vsim -c -do "run -all" tb_image_reader
vsim -c -do "run -all" tb_uart_serial_controller
quit -f
