--########################################################################################
--## Developer: Jack Sampford (j.w.sampford-15@student.lboro.ac.uk)                     ##
--##                                                                                    ##
--## Design name: xtea                                                                  ##
--## Module name: xtea_top_duplex - RTL                                                 ##
--## Target devices: ARM MPS2+ FPGA Prototyping Board                                   ##
--## Tool versions: Quartus Prime 19.1, ModelSim Intel FPGA Starter Edition 10.5b       ##
--##                                                                                    ##
--## Description: XTEA encryption/decryption core. Takes plaintext data in and creates  ##
--## ciphertext. Takes ciphertext data in and creates plaintext. Set relevant flag      ##
--## high, (data_valid for encryption, ciphertext_valid for decryption) and input data/ ##
--## ciphertext 32 bits at a time on data_word_in/ciphertext_word_in, then wait for the ##
--## relevant flag to be asserted (ciphertext_ready for encryption, data_ready for      ##
--## decryption) and read data out 32 bits at a time on either ciphertext_word_out or   ##
--## data_word_out signals.                                                             ##
--##                                                                                    ##
--## Dependencies: xtea_subkey_calc_enc.vhd, xtea_subkey_calc_dec.vhd xtea_enc.vhd,     ##
--## xtea_dec.vhd                                                                       ##
--########################################################################################

-- Library declarations
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;

-- Entity declaration
ENTITY xtea_top_duplex IS
    PORT(
        -- Clock and active low reset
        clk                 : IN  STD_LOGIC;
        reset_n             : IN  STD_LOGIC;

        -- Plaintext data input, one 32-bit word at a time
        data_word_in        : IN  STD_LOGIC_VECTOR(31 DOWNTO 0);
        -- Flag to enable data input
        data_valid          : IN  STD_LOGIC;

        -- Ciphertext data input, one 32-bit word at a time
        ciphertext_word_in  : IN  STD_LOGIC_VECTOR(31 DOWNTO 0);
        -- Flag to enable ciphertext data input
        ciphertext_valid    : IN  STD_LOGIC;

        -- Key input, one 32-bit word at a time
        -- No flag to enable input, either data_valid or ciphertext_valid are used
        key_word_in         : IN  STD_LOGIC_VECTOR(31 DOWNTO 0);

        -- Ciphertext data output from encryption core, one 32-bit word at a time
        ciphertext_word_out : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
        -- Flag to indicate the beginning of ciphertext output
        ciphertext_ready    : OUT STD_LOGIC;

        -- Plaintext data output from decryption core, one 32-bit word at a time
        data_word_out       : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
        -- Flag to indicate the beginning of plaintext output
        data_ready          : OUT STD_LOGIC
    );
END ENTITY xtea_top_duplex;

-- Architecture definition
ARCHITECTURE struct OF xtea_top_duplex IS

    -- Signals to allow passing of subkeys between key expansion and encryption/decryption cores
    SIGNAL subkey_encryption : STD_LOGIC_VECTOR(31 DOWNTO 0);
    SIGNAL subkey_decryption : STD_LOGIC_VECTOR(31 DOWNTO 0);

    -- Encryption subkey calculation component
    COMPONENT xtea_subkey_calc_enc IS
        PORT(
            clk          : IN  STD_LOGIC;
            reset_n      : IN  STD_LOGIC;
            key_word_in  : IN  STD_LOGIC_VECTOR(31 DOWNTO 0);
            key_valid    : IN  STD_LOGIC;
            key_word_out : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
        );
    END COMPONENT xtea_subkey_calc_enc;

    -- Decryption subkey calculation component
    COMPONENT xtea_subkey_calc_dec IS
        PORT(
            clk          : IN  STD_LOGIC;
            reset_n      : IN  STD_LOGIC;
            key_word_in  : IN  STD_LOGIC_VECTOR(31 DOWNTO 0);
            key_valid    : IN  STD_LOGIC;
            key_word_out : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
        );
    END COMPONENT xtea_subkey_calc_dec;
    
    -- Encryption core component
    COMPONENT xtea_enc IS
        PORT(
            clk           : IN  STD_LOGIC;
            reset_n       : IN  STD_LOGIC;
            data_word_in  : IN  STD_LOGIC_VECTOR(31 DOWNTO 0);
            data_valid    : IN  STD_LOGIC;
            key_word_in   : IN  STD_LOGIC_VECTOR(31 DOWNTO 0);
            data_ready    : OUT STD_LOGIC;
            data_word_out : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
        );
    END COMPONENT xtea_enc;

    -- Decryption core component
    COMPONENT xtea_dec IS
        PORT(
            clk           : IN  STD_LOGIC;
            reset_n       : IN  STD_LOGIC;
            data_word_in  : IN  STD_LOGIC_VECTOR(31 DOWNTO 0);
            data_valid    : IN  STD_LOGIC;
            key_word_in   : IN  STD_LOGIC_VECTOR(31 DOWNTO 0);
            data_ready    : OUT STD_LOGIC;
            data_word_out : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
        );
    END COMPONENT xtea_dec;

BEGIN

    -- Instantiate encryption subkey calculation component
    enc_subkey_calc_inst : xtea_subkey_calc_enc
    PORT MAP(
        clk          => clk,
        reset_n      => reset_n,
        key_word_in  => key_word_in,
        key_valid    => data_valid,
        key_word_out => subkey_encryption
    );

    -- Instantiate decryption subkey calculation component
    dec_subkey_calc_inst : xtea_subkey_calc_dec
    PORT MAP(
        clk          => clk,
        reset_n      => reset_n,
        key_word_in  => key_word_in,
        key_valid    => ciphertext_valid,
        key_word_out => subkey_decryption
    );

    -- Instantiate XTEA encryption component
    xtea_enc_inst : xtea_enc
    PORT MAP(
        clk           => clk,
        reset_n       => reset_n,
        data_word_in  => data_word_in,
        data_valid    => data_valid,
        key_word_in   => subkey_encryption,
        data_ready    => ciphertext_ready,
        data_word_out => ciphertext_word_out
    );

    -- Instantiate XTEA decryption component
    xtea_dec_inst : xtea_dec
    PORT MAP(
        clk           => clk,
        reset_n       => reset_n,
        data_word_in  => ciphertext_word_in,
        data_valid    => ciphertext_valid,
        key_word_in   => subkey_decryption,
        data_ready    => data_ready,
        data_word_out => data_word_out
    );

END struct;
