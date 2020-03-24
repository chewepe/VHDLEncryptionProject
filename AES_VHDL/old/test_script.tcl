vlib aes;

vcom -work aes aes_pkg.vhd;
vcom -work aes aes_key_expansion.vhd;
vcom -work aes aes_enc.vhd;
vcom -work aes aes_dec.vhd;
vcom -work aes aes_top.vhd;

vcom -work aes aes_tb.vhd;

vsim aes.aes_tb;
log -r *;
add wave *;
run -all;
