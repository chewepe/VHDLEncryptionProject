# Set up subfolder to create project in
file delete -force xtea_test
file mkdir xtea_test
cd xtea_test

# Create required library
vlib work;

# Compile RTL
vcom ../xtea_subkey_calc_enc.vhd
vcom ../xtea_subkey_calc_dec.vhd
vcom ../xtea_enc.vhd
vcom ../xtea_dec.vhd
vcom ../xtea_top_duplex.vhd;

# Compile testbench
vcom ../xtea_tb.vhd;

# Run simulation
vsim work.xtea_tb;
log -r *;
add wave *;
run 7 us;
