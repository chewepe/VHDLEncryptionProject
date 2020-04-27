--########################################################################################
--## Developer: Jack Sampford (j.w.sampford-15@student.lboro.ac.uk)                     ##
--##                                                                                    ##
--## Design name: aes                                                                   ##
--## Module name: aes_tb - Testbench                                                    ##
--## Target devices: ARM MPS2+ FPGA Prototyping Board                                   ##
--## Tool versions: Quartus Prime 19.1, ModelSim Intel FPGA Starter Edition 10.5b       ##
--##                                                                                    ##
--## Description: AES encryption/decryption core testbench. Tests multiple key/data     ##
--## pairs by encrypting specified data with specified key, then decrypting with the    ##
--## same key and comparing the results.                                                ##
--##                                                                                    ##
--## Dependencies: aes_top.vhd                                                          ##
--########################################################################################

-- Library declarations
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

-- Entity definition
ENTITY aes_tb IS
END ENTITY aes_tb;

-- Architecture definition
ARCHITECTURE tb OF aes_tb IS

    -- AES encryption/decryption core component
    COMPONENT aes_top IS
        PORT(
            clk                 : IN  STD_LOGIC;
            reset_n             : IN  STD_LOGIC;
            key_length          : IN  STD_LOGIC_VECTOR(1 DOWNTO 0);
            data_word_in        : IN  STD_LOGIC_VECTOR(31 DOWNTO 0);
            data_valid          : IN  STD_LOGIC;
            ciphertext_word_in  : IN  STD_LOGIC_VECTOR(31 DOWNTO 0);
            ciphertext_valid    : IN  STD_LOGIC;
            key_word_in         : IN  STD_LOGIC_VECTOR(31 DOWNTO 0);
            key_valid           : IN  STD_LOGIC;
            key_ready           : OUT STD_LOGIC;
            ciphertext_word_out : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
            ciphertext_ready    : OUT STD_LOGIC;
            data_word_out       : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
            data_ready          : OUT STD_LOGIC
        );
    END COMPONENT aes_top;

    -- Clock period constant
    CONSTANT clk_period         : TIME    := 10 ns;

    -- Number of key/data vectors to test
    CONSTANT num_keys           : INTEGER := 3;

    -- Clock and reset signals
    SIGNAL clk                  : STD_LOGIC;
    SIGNAL reset_n              : STD_LOGIC;
    -- Key length selection signal
    SIGNAL key_length_select    : STD_LOGIC_VECTOR(1 DOWNTO 0);
    -- Plaintext input interface signals
    SIGNAL plaintext_in_data    : STD_LOGIC_VECTOR(31 DOWNTO 0);
    SIGNAL plaintext_in_flag    : STD_LOGIC;
    -- Ciphertext input interface signals
    SIGNAL ciphertext_in_data   : STD_LOGIC_VECTOR(31 DOWNTO 0);
    SIGNAL ciphertext_in_flag   : STD_LOGIC;
    -- Key input interface signals
    SIGNAL key_in_data          : STD_LOGIC_VECTOR(31 DOWNTO 0);
    SIGNAL key_in_flag          : STD_LOGIC;
    -- Key ready indicator signal
    SIGNAL key_ready_flag       : STD_LOGIC;
    -- Ciphertext output interface signals
    SIGNAL ciphertext_out_data  : STD_LOGIC_VECTOR(31 DOWNTO 0);
    SIGNAL ciphertext_out_flag  : STD_LOGIC;
    -- Plaintext output interface signals
    SIGNAL plaintext_out_data   : STD_LOGIC_VECTOR(31 DOWNTO 0);
    SIGNAL plaintext_out_flag   : STD_LOGIC;

    -- Type definitions for key/data arrays
    TYPE key_array_t IS ARRAY (0 TO num_keys-1) OF STD_LOGIC_VECTOR(255 DOWNTO 0);
    TYPE data_array_t IS ARRAY (0 TO num_keys-1) OF STD_LOGIC_VECTOR(127 DOWNTO 0);
    TYPE encrypted_array_t IS ARRAY (0 TO (num_keys*3)-1) OF STD_LOGIC_VECTOR(127 DOWNTO 0);

    -- Array to hold keys used
    SIGNAL aes_keys           : key_array_t       := (0 => x"92347890123748335623034890495573DEADBEEF0123456789ABCDEFDEADBEEF",
                                                      1 => x"01234567DEADBEEFFEDCBA980123456773467723465348589734637824782378",
                                                      2 => x"01234501234501234501234501234501ABCDEFABCDEFABCDEFABCDEFABCDEFAB");

    -- Signal to hold data input
    SIGNAL input_data         : data_array_t      := (0 => x"A5A5A5A501234567FEDCBA985A5A5A5A",
                                                      1 => x"FEDCBAFEDCBAFEDCBAFEDCBAFEDCBAFE",
                                                      2 => x"46893489237894238964623812300325");

    -- Signal to hold expected encryption results
    SIGNAL encrypted_expected : encrypted_array_t := (0 => x"237549D4CDCEA7BE0FE7D162CC9161D3", -- AES-128
                                                      1 => x"22F2D4EAFFE86A37A1653C63049C6E7B",
                                                      2 => x"8DD7FBDDBFBD0F47B9606573A69A3771",
                                                      3 => x"F4D27551A6EFA9BB313BB453B6166FB5", -- AES-192
                                                      4 => x"8A9F285FC0E839AD33D5670EEEFD77C5",
                                                      5 => x"6594433D860F7C36C6D9B999330BAD91",
                                                      6 => x"23365948B5AE43559E081EF6C84AFA21", -- AES-256
                                                      7 => x"C93AF55DE40622DCAB4F1BEDD377CDC3",
                                                      8 => x"AB7A9C69366B013766F8DB3E05F0EC45");

    -- Signal to hold encrypted data output
    SIGNAL encrypted_data       : STD_LOGIC_VECTOR(127 DOWNTO 0);
    -- Signal to hold decrypted data output
    SIGNAL decrypted_data       : STD_LOGIC_VECTOR(127 DOWNTO 0);

BEGIN

    -- Device under test instantiation
    DUT : aes_top
    PORT MAP(
        clk                 => clk,
        reset_n             => reset_n,
        key_length          => key_length_select,
        data_word_in        => plaintext_in_data,
        data_valid          => plaintext_in_flag,
        ciphertext_word_in  => ciphertext_in_data,
        ciphertext_valid    => ciphertext_in_flag,
        key_word_in         => key_in_data,
        key_valid           => key_in_flag,
        key_ready           => key_ready_flag,
        ciphertext_word_out => ciphertext_out_data,
        ciphertext_ready    => ciphertext_out_flag,
        data_word_out       => plaintext_out_data,
        data_ready          => plaintext_out_flag
    );

    -- Clock driver process
    clk_proc : PROCESS
    BEGIN
        clk <= '1';
        WAIT FOR clk_period/2;
        clk <= '0';
        WAIT FOR clk_period/2;
    END PROCESS clk_proc;

    -- Main stimulus process
    stim_proc : PROCESS
        VARIABLE fail_flag    : STD_LOGIC;
        VARIABLE fail_counter : INTEGER;
        PROCEDURE reset_dut IS
        BEGIN
            -- Reset DUT and all inputs
            reset_n            <= '0';
            key_length_select  <= (OTHERS => '0');
            plaintext_in_flag  <= '0';
            plaintext_in_data  <= (OTHERS => '0');
            ciphertext_in_flag <= '0';
            ciphertext_in_data <= (OTHERS => '0');
            key_in_flag        <= '0';
            key_in_data        <= (OTHERS => '0');
            -- Wait and release reset
            WAIT FOR clk_period*2;
            reset_n            <= '1';
            WAIT FOR clk_period;
        END PROCEDURE reset_dut;
    BEGIN
        -- Reset DUT and inputs
        reset_dut;
        -- Reset fail flag and counter
        fail_flag    := '0';
        fail_counter := 0;
        -- Reset input/output storage vectors
        encrypted_data <= (OTHERS => '0');
        decrypted_data <= (OTHERS => '0');
        -- Loop over all key lengths
        FOR length IN 0 TO 2 LOOP
            -- Set correct key length for test
            key_length_select <= STD_LOGIC_VECTOR(TO_UNSIGNED(length,2));
            -- Main test loop, test all key/data pairs
            FOR i IN 0 TO num_keys-1 LOOP
                -- Write in key, updating data on falling edge of clock to avoid delta cycle issues
                WAIT UNTIL FALLING_EDGE(clk);
                key_in_flag <= '1';
                -- Extra writes for AES-256
                IF length = 2 THEN
                    key_in_data <= aes_keys(i)(255 DOWNTO 224);
                    WAIT FOR clk_period;
                    key_in_data <= aes_keys(i)(223 DOWNTO 192);
                    WAIT FOR clk_period;
                END IF;
                -- Extra writes for AES-256 and 192
                IF length >= 1 THEN
                    key_in_data <= aes_keys(i)(191 DOWNTO 160);
                    WAIT FOR clk_period;
                    key_in_data <= aes_keys(i)(159 DOWNTO 128);
                    WAIT FOR clk_period;
                END IF;
                -- Writes for all key sizes
                key_in_data <= aes_keys(i)(127 DOWNTO 96);
                WAIT FOR clk_period;
                key_in_data <= aes_keys(i)(95 DOWNTO 64);
                WAIT FOR clk_period;
                key_in_data <= aes_keys(i)(63 DOWNTO 32);
                WAIT FOR clk_period;
                key_in_data <= aes_keys(i)(31 DOWNTO 0);
                WAIT FOR clk_period;
                -- Stop key input
                key_in_flag <= '0';
                key_in_data <= (OTHERS => '0');
                -- Wait for key expansion to complete
                WAIT UNTIL key_ready_flag = '1';
                -- Write data in, updating on falling edge of clock to avoid delta cycle issues
                WAIT UNTIL FALLING_EDGE(clk);
                plaintext_in_flag <= '1';
                plaintext_in_data <= input_data(i)(127 DOWNTO 96);
                WAIT FOR clk_period;
                plaintext_in_data <= input_data(i)(95 DOWNTO 64);
                WAIT FOR clk_period;
                plaintext_in_data <= input_data(i)(63 DOWNTO 32);
                WAIT FOR clk_period;
                plaintext_in_data <= input_data(i)(31 DOWNTO 0);
                WAIT FOR clk_period;
                -- Stop data input
                plaintext_in_flag <= '0';
                plaintext_in_data <= (OTHERS => '0');
                -- Wait until encryption complete
                WAIT UNTIL ciphertext_out_flag = '1';
                -- Read data output on falling edge
                WAIT UNTIL FALLING_EDGE(clk);
                encrypted_data(127 DOWNTO 96) <= ciphertext_out_data;
                WAIT FOR clk_period;
                encrypted_data(95 DOWNTO 64)  <= ciphertext_out_data;
                WAIT FOR clk_period;
                encrypted_data(63 DOWNTO 32)  <= ciphertext_out_data;
                WAIT FOR clk_period;
                encrypted_data(31 DOWNTO 0)   <= ciphertext_out_data;
                WAIT FOR clk_period;
                -- Compare encrypted data with expected results
                IF encrypted_data = encrypted_expected(i + num_keys*length) THEN
                    REPORT "NOTE: Key/data pair " & INTEGER'IMAGE(i+1) & " key length " & INTEGER'IMAGE(length) & " encryption passed" SEVERITY NOTE;
                ELSE
                    REPORT "ERROR: Key/data pair " & INTEGER'IMAGE(i+1) & " key length " & INTEGER'IMAGE(length) & " encryption failed" SEVERITY ERROR;
                    fail_flag    := '1';
                    fail_counter := fail_counter + 1;
                END IF;
                -- Write ciphertext into decrypter, updating data on falling edge of clock
                WAIT UNTIL FALLING_EDGE(clk);
                ciphertext_in_flag <= '1';
                ciphertext_in_data <= encrypted_data(127 DOWNTO 96);
                WAIT FOR clk_period;
                ciphertext_in_data <= encrypted_data(95 DOWNTO 64);
                WAIT FOR clk_period;
                ciphertext_in_data <= encrypted_data(63 DOWNTO 32);
                WAIT FOR clk_period;
                ciphertext_in_data <= encrypted_data(31 DOWNTO 0);
                WAIT FOR clk_period;
                -- Stop ciphertext input
                ciphertext_in_flag <= '0';
                ciphertext_in_data <= (OTHERS => '0');
                -- Wait until decryption complete
                WAIT UNTIL plaintext_out_flag = '1';
                -- Read data output on falling edge
                WAIT UNTIL FALLING_EDGE(clk);
                decrypted_data(127 DOWNTO 96) <= plaintext_out_data;
                WAIT FOR clk_period;
                decrypted_data(95 DOWNTO 64)  <= plaintext_out_data;
                WAIT FOR clk_period;
                decrypted_data(63 DOWNTO 32)  <= plaintext_out_data;
                WAIT FOR clk_period;
                decrypted_data(31 DOWNTO 0)   <= plaintext_out_data;
                WAIT FOR clk_period;
                -- Compare decrypted data with original plaintext
                IF decrypted_data = input_data(i) THEN
                    REPORT "NOTE: Key/data pair " & INTEGER'IMAGE(i+1) & " key length " & INTEGER'IMAGE(length) & " decryption passed" SEVERITY NOTE;
                ELSE
                    REPORT "ERROR: Key/data pair " & INTEGER'IMAGE(i+1) & " key length " & INTEGER'IMAGE(length) & " decryption failed" SEVERITY ERROR;
                    fail_flag    := '1';
                    fail_counter := fail_counter + 1;
                END IF;
            END LOOP;
        END LOOP;
        -- Print final results
        IF fail_flag = '0' THEN
            REPORT "NOTE: All tests passed" SEVERITY NOTE;
        ELSE
            REPORT "ERROR: " & INTEGER'IMAGE(fail_counter) & " tests failed" SEVERITY ERROR;
        END IF;

        -- Wait forever at end of testbench
        WAIT;
    END PROCESS stim_proc;

END tb;
