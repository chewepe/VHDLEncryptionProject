File breakdown:
xtea_top_duplex.vhd - Top level struct instantiating and linking the other blocks.
xtea_subkey_calc_enc.vhd - Subkey calculation component for encryption.
xtea_subkey_calc_dec.vhd - Subkey calculation component for decryption.
xtea_enc.vhd - XTEA encryption core.
xtea_dec.vhd - XTEA decryption core.
xtea_tb.vhd - Testbench for xtea_top_duplex.vhd which tests several key/data pairs through encryption/decryption.
test_script_xtea.tcl - TCL script to compile XTEA VHDL code and run testbench.

Operation steps:
First reset the device by setting synchronous active-low reset signal reset_n to '0' for at least 1 clock cycle.

Data encryption:
1. Begin inputting the 128-bit key and data block simultaneously by setting the input signal data_valid to '1' and
   setting key_word_in and data_word_in to the most significant 32 bits of the key and data respectively.
2. After all 128 bits of both have been input set data_valid to '0' and both key_word_in and data_word_in to 0.
3. Wait for the output signal ciphertext_ready to be set to '1', indicating completion of encryption.
4. Ciphertext output will begin 32 bits at a time, most significant 32 bits first, on output signal ciphertext_word_out.

Ciphertext decryption:
1. Begin·inputting·the·128-bit·key·and·ciphertext·block·simultaneously·by·setting·the·input·signal·ciphertext_valid·to·'1'·and
   setting·key_word_in·and·ciphertext_word_in·to·the·most·significant·32·bits·of·the·key·and·ciphertext·respectively.
2. After·all·128·bits·of·both·have·been·input·set·ciphertext_valid·to·'0'·and·both·key_word_in·and·ciphertext_word_in·to·0.
3. Wait·for·the·output·signal·data_ready·to·be·set·to·'1',·indicating·completion·of·decryption.
4. Plaintext data·output·will·begin·32·bits·at·a·time,·most·significant·32·bits·first,·on·output·signal·data_word_out.

Other notes:

Testbench operation:
The provided testbench tests the XTEA core by encrypting several blocks of data with different keys and decrypting these blocks with the same keys,
ensuring that the result matches the initial plaintext input. These keys and data blocks are defined by the signals xtea_keys and input_data,
and can be added to by increasing the constant num_keys and adding new key/data pairs to the initialiser lists for the xtea_keys and input_data_array
signals.
The testbench can be run with the provided script using the command vsim -do test_script_xtea.tcl

Hardware implementation:
According to Quartus Prime analysis tools, maximum achievable frequency for the design is 125.64 MHz using a worst-case four corner analysis, which is
higher than the maximum clock speed of a Cortex M3 (120 MHz). The design also uses 769 ALMs (adaptive logic modules) and 878 registers, representing
approximately 1% of the available resources on the Cyclone V 5CEBA9F31C8 FPGA on the ARM MPS2+ board.

General implementation notes:
This design operates with a 128-bit block size rather than the standard 64-bit block size typical in XTEA implementations by running two XTEA cores
in parallel, encrypting/decrypting one 64-bit block each. This design also operates entirely in duplex, i.e. allowing either encryption, decryption
or both to take place at one time.
The correct operation of the encryption mode was also verified by comparing its output to that of a C implementation based on the standard, available at:
https://github.com/cantora/avr-crypto-lib/blob/master/xtea/xtea.c
