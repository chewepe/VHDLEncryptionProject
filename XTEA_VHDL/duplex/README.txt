File breakdown:
xtea_top_duplex.vhd - Top level struct instantiating and linking the other blocks.
xtea_subkey_calc.vhd - XTEA subkey calculation component.
xtea_enc.vhd - XTEA encryption core.
xtea_dec.vhd - XTEA decryption core.
xtea_tb.vhd - Testbench for xtea_top_duplex.vhd which tests several key/data pairs through encryption/decryption.
test_script_xtea.tcl - TCL script to compile XTEA VHDL code and run testbench.

Operation steps:
First reset the device by setting synchronous active-low reset signal reset_n to '0' for at least 1 clock cycle.

Key expansion:
1. Begin inputting 128-bit key by setting input key_valid to '1' and key_word_in to the most significant 32 bits of the key.
2. Repeat on subsequent clock cycles with the next most significant 32 bits of the key.
3. After all 128 bits have been input set key_word_in back to 0 and key_valid to '0', triggering the beginning of subkey calculation.
4. Wait for the output signal key_ready to be set to '1', indicating completion of subkey calculation.

Data encryption:
1. Once subkey calculation has completed, input 128-bit block of data using the data_valid and data_word_in signals in the same manner as the key.
2. Once block has been input set data_word_in to 0 and data_valid to '0', triggering the beginning of encryption.
3. Wait for the output signal ciphertext_ready to be set to '1', indicating the completion of data encryption.
4. Ciphertext output will begin 32 bits at a time, most significant 32 bits first, on output signal ciphertext_word_out.

Ciphertext decryption:
1. Once subkey calculation has completed, input 128-bit ciphertext block using the ciphertext_valid and ciphertext_word_in signals in the same manner as the key.
2. Once ciphertext has been input set ciphertext_word_in to 0 and ciphertext_valid to '0', triggering the beginning of decryption.
3. Wait for the output signal data_ready to be set to '1', indicating the completion of ciphertext decryption.
4. Plaintext output will begin 32 bits at a time, most significant 32 bits first, on output signal data_word_out.

Other notes:

Testbench operation:
The provided testbench tests the XTEA core by encrypting several blocks of data with different keys and decrypting these blocks with the same keys,
ensuring that the result matches the initial plaintext input. These keys and data blocks are defined by the signals xtea_keys and input_data,
and can be added to by increasing the constant num_keys and adding new key/data pairs to the initialiser lists for the xtea_keys and input_data_array
signals.
The testbench can be run with the provided script using the command vsim -do test_script_xtea.tcl

Hardware implementation:
According to Quartus Prime analysis tools, maximum achievable frequency for the design is 128.82 MHz using a worst-case four corner analysis.
The design also uses 2311 ALMs (adaptive logic modules) and 3073 registers, representing approximately 3% of the available resources on the
Cyclone V 5CEBA9F31C8 FPGA on the ARM MPS2+ board.

General implementation notes:
This design operates with a 128-bit block size rather than the standard 64-bit block size typical in XTEA implementations by running two XTEA cores
in parallel, encrypting/decrypting one 64-bit block each. This design also operates entirely in duplex, i.e. allowing either encryption, decryption
or both to take place at one time.
The correct operation of the encryption mode was also verified by comparing its output to that of a C implementation based on the standard, available at:
https://github.com/cantora/avr-crypto-lib/blob/master/xtea/xtea.c
