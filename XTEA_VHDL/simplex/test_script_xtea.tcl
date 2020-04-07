# Set up subfolder to create project in
file delete -force xtea_test
file mkdir xtea_test
cd xtea_test

# Create required library
vlib work;

# Compile RTL
vcom ../xtea_top.vhd;

# Compile testbench
vcom ../xtea_tb.vhd;

# Run simulation
vsim work.xtea_tb;
log -r *;
add wave *;
run 12 us;
