File breakdown:
aes_top.vhd - Top level struct instantiating AES encryption, decryption and key expansion components.
aes_enc.vhd - AES encryption core, used as a component of aes_top.vhd.
aes_dec.vhd - AES decryption core, used as a component of aes_top.vhd.
aes_key_expansion.vhd - AES key expansion, used as a component of aes_top.vhd.
aes_pkg.vhd - Package containing type and constant definitions, needed for all AES components.
aes_tb.vhd - Testbench for aes_top.vhd which tests several key/data pairs through encryption/decryption.
test_script_aes.tcl - TCL script to compile AES VHDL code and run testbench.
aes_top_diagram.png - Diagram showing internal layout of the aes_top block.

Operation steps:
First reset the device by setting synchronous active-low reset signal reset_n to '0' for at least 1 clock cycle.
Key length is selected using input key_length, setting to 00 for 128, 01 for 192 or 10 for 256 bit keys.

Key expansion:
1. Begin inputting 128-bit key by setting input key_valid to '1' and key_word_in to the most significant 32 bits of the key.
2. Repeat on subsequent clock cycles with the next most significant 32 bits of the key.
3. After all 128 bits have been input set key_word_in back to 0 and key_valid to '0', triggering the beginning of key expansion.
4. Wait for the output signal key_ready to be set to '1', indicating completion of key expansion.

Data encryption:
1. Once key expansion has completed, input 128-bit block of data using the data_valid and data_word_in signals in the same manner as the key.
2. Once block has been input set data_word_in to 0 and data_valid to '0', triggering the beginning of encryption.
3. Wait for the output signal ciphertext_ready to be set to '1', indicating the completion of data encryption.
4. Ciphertext output will begin 32 bits at a time, most significant 32 bits first, on output signal ciphertext_word_out.

Ciphertext decryption:
1. Once key expansion has completed, input 128-bit ciphertext block using the ciphertext_valid and ciphertext_word_in signals in the same manner as the key.
2. Once ciphertext has been input set ciphertext_word_in to 0 and ciphertext_valid to '0', triggering the beginning of decryption.
3. Wait for the output signal data_ready to be set to '1', indicating the completion of ciphertext decryption.
4. Plaintext output will begin 32 bits at a time, most significant 32 bits first, on output signal data_word_out.

Other notes:

Testbench operation:
The provided testbench tests the AES core by encrypting several blocks of data with different keys and decrypting these blocks with the same keys,
ensuring that the result matches the initial plaintext input. These keys and data blocks are defined by the signals aes_keys and input_data, and can
be added to by increasing the constant num_keys and adding new key/data pairs to the initialiser lists for the aes_keys and input_data signals.
The testbench can be run with the provided TCL script using the command vsim -do test_script_aes.tcl

Hardware implementation:
According to Quartus Prime analysis tools, maximum achievable frequency for the design is 143.99 MHz using a worst-case four corner analysis.
The design also uses 2863 ALMs (adaptive logic modules), 2959 registers and 2048 BRAM bits, representing approximately 3% of the available resources
on the Cyclone V 5CEBA9F31C8 FPGA on the ARM MPS2+ board.
A block diagram showing the internal layout of aes_top is provided as aes_top_diagram.png showing the interconnects between the components and ports.

General implementation notes:
Based on implementation from OpenCores, rewritten to use numeric_std amongst other modifications. Original implementation available from:
https://opencores.org/projects/aes_128_192_256
This design uses a single key expansion block shared by both the encryption and decryption cores, saving hardware resources. This design also allows
full duplex operation, i.e. simultaneous encryption and decryption.
The correct operation of the encryption core was also verified by comparing its output to that given by an online AES-128 calculator, available at:
https://www.cryptool.org/en/cto-highlights/aes
