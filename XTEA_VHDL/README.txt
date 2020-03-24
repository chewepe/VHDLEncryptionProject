File breakdown:
xtea_top.vhd - Main XTEA code file, implements all steps of encryption and decryption.
xtea_tb.vhd - Testbench for xtea_top.vhd which tests several key/data pairs through encryption/decryption.
test_script_xtea.tcl - TCL script to compile XTEA VHDL code and run testbench.

Operation steps:
First reset the device by setting synchronous active-low reset signal reset_n to '0' for at least 1 clock cycle.

Data encryption:
1. Set the input signal encryption to '1', configuring the device to encryption mode.
2. Begin inputting the 128-bit key and data block simultaneously by setting the input signal key_data_valid to '1' and
   setting key_word_in and data_word_in to the most significant 32 bits of the key and data respectively.
3. After all 128 bits of both have been input set key_data_valid to '0' and both key_word_in and data_word_in to 0.
4. Wait for the output signal data_ready to be set to '1', indicating completion of encryption.
5. Ciphertext output will begin 32 bits at a time, most significant 32 bits first, on output signal data_word_out.

Ciphertext decryption:
1. Set·the·input·signal·encryption·to·'0',·configuring·the·device·to·decryption·mode.
2. Begin·inputting·the·128-bit·key·and·ciphertext·block·simultaneously·by·setting·the·input·signal·key_data_valid·to·'1'·and
   setting·key_word_in·and·data_word_in·to·the·most·significant·32·bits·of·the·key·and·ciphertext·respectively.
3. After·all·128·bits·of·both·have·been·input·set·key_data_valid·to·'0'·and·both·key_word_in·and·data_word_in·to·0.
4. Wait·for·the·output·signal·data_ready·to·be·set·to·'1',·indicating·completion·of·decryption.
5. Plaintext data·output·will·begin·32·bits·at·a·time,·most·significant·32·bits·first,·on·output·signal·data_word_out.

Other notes:

Testbench operation:
The provided testbench tests the XTEA core by encrypting several blocks of data with different keys and decrypting these blocks with the same keys,
ensuring that the result matches the initial plaintext input. These keys and data blocks are defined by the signals xtea_keys and input_data_array,
and can be added to by increasing the constant num_keys and adding new key/data pairs to the initialiser lists for the xtea_keys and input_data_array
signals.

Hardware implementation:
According to Quartus Prime analysis tools, maximum achievable frequency for the design is 125.6 MHz using a worst-case four corner analysis, which is
higher than the maximum clock speed of a Cortex M3 (120 MHz). The design also uses 364 ALMs (adaptive logic modules) and 560 registers, representing
less than 1% of the available resources on the Cyclone V 5CEBA9F31C8 FPGA on the ARM MPS2+ board.

General implementation notes:
This design operates with a 128-bit block size rather than the standard 64-bit block size typical in XTEA implementations by running two XTEA cores
in parallel, encrypting/decrypting one 64-bit block each. This design also operates entirely in simplex, i.e. only allowing either encryption or
decryption to take place at one time. Several different configurations are possible, such as the addition of two more XTEA cores to allow full duplex
operation, or the removal of one XTEA core to save space, instead encrypting the 64-bit blocks in serial.
