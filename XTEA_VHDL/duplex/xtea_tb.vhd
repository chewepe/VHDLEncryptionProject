--########################################################################################
--## Developer: Jack Sampford (j.w.sampford-15@student.lboro.ac.uk)                     ##
--##                                                                                    ##
--## Design name: xtea (duplex)                                                         ##
--## Module name: xtea_tb - Testbench                                                   ##
--## Target devices: ARM MPS2+ FPGA Prototyping Board                                   ##
--## Tool versions: Quartus Prime 19.1, ModelSim Intel FPGA Starter Edition 10.5b       ##
--##                                                                                    ##
--## Description: XTEA encryption/decryption core testbench. Tests multiple key/data    ##
--## pairs by encrypting specified data with specified key, then decrypting with the    ##
--## same key and comparing the results.                                                ##
--##                                                                                    ##
--## Dependencies: xtea_top.vhd                                                         ##
--########################################################################################

-- Library declarations
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;

-- Entity definition
ENTITY xtea_tb IS
END ENTITY xtea_tb;

-- Architecture definition
ARCHITECTURE tb OF xtea_tb IS

    -- XTEA encryption/decryption core component
    COMPONENT xtea_top IS
        PORT(
            clk                 : IN  STD_LOGIC;
            reset_n             : IN  STD_LOGIC;
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
    END COMPONENT xtea_top;

    -- Clock period constant
    CONSTANT clk_period         : TIME    := 10 ns;

    -- Number of key/data vectors to test
    CONSTANT num_keys           : INTEGER := 3;

    -- Clock and reset signals
    SIGNAL clk                  : STD_LOGIC;
    SIGNAL reset_n              : STD_LOGIC;
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

    TYPE key_data_array_t IS ARRAY (0 TO num_keys-1) OF STD_LOGIC_VECTOR(127 DOWNTO 0);

    -- Array to hold keys used
    SIGNAL xtea_keys            : key_data_array_t := (0 => x"DEADBEEF0123456789ABCDEFDEADBEEF",
                                                       1 => x"73467723465348589734637824782378",
                                                       2 => x"ABCDEFABCDEFABCDEFABCDEFABCDEFAB");

    -- Signal to hold data input
    SIGNAL input_data           : key_data_array_t := (0 => x"A5A5A5A501234567FEDCBA985A5A5A5A",
                                                       1 => x"FEDCBAFEDCBAFEDCBAFEDCBAFEDCBAFE",
                                                       2 => x"46893489237894238964623812300325");

    -- Signal to hold encrypted data output
    SIGNAL encrypted_data       : STD_LOGIC_VECTOR(127 DOWNTO 0);
    -- Signal to hold decrypted data output
    SIGNAL decrypted_data       : STD_LOGIC_VECTOR(127 DOWNTO 0);

BEGIN

    -- Device under test instantiation
    DUT : xtea_top
    PORT MAP(
        clk                 => clk,
        reset_n             => reset_n,
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
        -- Main test loop, test all key/data pairs
        FOR i IN 0 TO num_keys-1 LOOP
            -- Write in key, updating data on falling edge of clock to avoid delta cycle issues
            WAIT UNTIL FALLING_EDGE(clk);
            key_in_flag <= '1';
            key_in_data <= xtea_keys(i)(127 DOWNTO 96);
            WAIT FOR clk_period;
            key_in_data <= xtea_keys(i)(95 DOWNTO 64);
            WAIT FOR clk_period;
            key_in_data <= xtea_keys(i)(63 DOWNTO 32);
            WAIT FOR clk_period;
            key_in_data <= xtea_keys(i)(31 DOWNTO 0);
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
                REPORT "NOTE: Key/data pair " & INTEGER'IMAGE(i+1) & " passed" SEVERITY NOTE;
            ELSE
                REPORT "ERROR: Key/data pair " & INTEGER'IMAGE(i+1) & " failed" SEVERITY ERROR;
                fail_flag    := '1';
                fail_counter := fail_counter + 1;
            END IF;
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
