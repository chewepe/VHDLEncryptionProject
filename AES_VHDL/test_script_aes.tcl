# Set up subfolder to create project in
file delete -force aes_test
file mkdir aes_test
cd aes_test

# Create required library
vlib aes;

# Compile RTL
vcom -work aes ../aes_pkg.vhd;
vcom -work aes ../aes_key_expansion.vhd;
vcom -work aes ../aes_enc.vhd;
vcom -work aes ../aes_dec.vhd;
vcom -work aes ../aes_top.vhd;

# Compile testbench
vcom -work aes ../aes_tb.vhd;

# Run simulation
vsim aes.aes_tb;
log -r *;
add wave *;
run 12 us;
