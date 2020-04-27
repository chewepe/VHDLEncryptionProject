--########################################################################################
--## Developer: Jack Sampford (j.w.sampford-15@student.lboro.ac.uk)                     ##
--##                                                                                    ##
--## Design name: xtea                                                                  ##
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

-- Arcvhitecture definition
ARCHITECTURE tb OF xtea_tb IS

    -- XTEA encryption/decryption core component
    COMPONENT xtea_top IS
        PORT(
            clk            : IN  STD_LOGIC;
            reset_n        : IN  STD_LOGIC;
            encryption     : IN  STD_LOGIC;
            key_data_valid : IN  STD_LOGIC;
            data_word_in   : IN  STD_LOGIC_VECTOR(31 DOWNTO 0);
            key_word_in    : IN  STD_LOGIC_VECTOR(31 DOWNTO 0);
            data_word_out  : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
            data_ready     : OUT STD_LOGIC
        );
    END COMPONENT xtea_top;

    -- Clock period constant
    CONSTANT clk_period : TIME    := 10 ns;

    -- Number of key/data vectors to test
    CONSTANT num_keys   : INTEGER := 3;

    -- Clock and reset signals
    SIGNAL clk                  : STD_LOGIC;
    SIGNAL reset_n              : STD_LOGIC;
    -- Encryption setting flag
    SIGNAL encryption_flag      : STD_LOGIC;
    -- Key/data input interface signals
    SIGNAL key_data_in_flag     : STD_LOGIC;
    SIGNAL input_data           : STD_LOGIC_VECTOR(31 DOWNTO 0);
    SIGNAL input_key            : STD_LOGIC_VECTOR(31 DOWNTO 0);
    -- Data output interface signals
    SIGNAL output_data          : STD_LOGIC_VECTOR(31 DOWNTO 0);
    SIGNAL output_data_flag     : STD_LOGIC;

    TYPE key_data_array_t IS ARRAY (0 TO num_keys-1) OF STD_LOGIC_VECTOR(127 DOWNTO 0);

    -- Array to hold keys used
    SIGNAL xtea_keys            : key_data_array_t := (0 => x"DEADBEEF0123456789ABCDEFDEADBEEF",
                                                       1 => x"73467723465348589734637824782378",
                                                       2 => x"ABCDEFABCDEFABCDEFABCDEFABCDEFAB");

    -- Signal to hold data input
    SIGNAL input_data_array     : key_data_array_t := (0 => x"A5A5A5A501234567FEDCBA985A5A5A5A",
                                                       1 => x"FEDCBAFEDCBAFEDCBAFEDCBAFEDCBAFE",
                                                       2 => x"46893489237894238964623812300325");

    -- Signal to hold expected encryption outputs
    SIGNAL encrypted_expected   : key_data_array_t := (0 => x"089975E92555F334CE76E4F24D932AB3",
                                                       1 => x"07F5110D638D6121F0FC43540AB370B8",
                                                       2 => x"BC8BD8D9269AC66173B1FF238096EC53");

    -- Signal to hold encrypted data output
    SIGNAL encrypted_data       : STD_LOGIC_VECTOR(127 DOWNTO 0);
    -- Signal to hold decrypted data output
    SIGNAL decrypted_data       : STD_LOGIC_VECTOR(127 DOWNTO 0);

BEGIN

    -- Device under test instantiation
    DUT : xtea_top
    PORT MAP(
        clk            => clk,
        reset_n        => reset_n,
        encryption     => encryption_flag,
        key_data_valid => key_data_in_flag,
        data_word_in   => input_data,
        key_word_in    => input_key,
        data_word_out  => output_data,
        data_ready     => output_data_flag
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
            reset_n          <= '0';
            encryption_flag  <= '0';
            key_data_in_flag <= '0';
            input_data       <= (OTHERS => '0');
            input_key        <= (OTHERS => '0');
            -- Wait and release reset
            WAIT FOR clk_period*2;
            reset_n          <= '1';
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
            -- Set mode to encryption
            encryption_flag  <= '1';
            WAIT FOR clk_period;
            -- Write in key and data, updating data on falling edge of clock to avoid delta cycle issues
            WAIT UNTIL FALLING_EDGE(clk);
            key_data_in_flag <= '1';
            input_key        <= xtea_keys(i)(127 DOWNTO 96);
            input_data       <= input_data_array(i)(127 DOWNTO 96);
            WAIT FOR clk_period;
            input_key        <= xtea_keys(i)(95 DOWNTO 64);
            input_data       <= input_data_array(i)(95 DOWNTO 64);
            WAIT FOR clk_period;
            input_key        <= xtea_keys(i)(63 DOWNTO 32);
            input_data       <= input_data_array(i)(63 DOWNTO 32);
            WAIT FOR clk_period;
            input_key        <= xtea_keys(i)(31 DOWNTO 0);
            input_data       <= input_data_array(i)(31 DOWNTO 0);
            WAIT FOR clk_period;
            -- Stop key/data input
            key_data_in_flag <= '0';
            input_key        <= (OTHERS => '0');
            input_data       <= (OTHERS => '0');
            -- Wait until encryption complete
            WAIT UNTIL output_data_flag = '1';
            -- Read ciphertext output on falling edge
            WAIT UNTIL FALLING_EDGE(clk);
            encrypted_data(127 DOWNTO 96) <= output_data;
            WAIT FOR clk_period;
            encrypted_data(95 DOWNTO 64)  <= output_data;
            WAIT FOR clk_period;
            encrypted_data(63 DOWNTO 32)  <= output_data;
            WAIT FOR clk_period;
            encrypted_data(31 DOWNTO 0)   <= output_data;
            WAIT FOR clk_period;
            -- Compare encrypted data with expected results
            IF encrypted_data = encrypted_expected(i) THEN
                REPORT "NOTE: Key/data pair " & INTEGER'IMAGE(i+1) & " encryption passed" SEVERITY NOTE;
            ELSE
                REPORT "ERROR: Key/data pair " & INTEGER'IMAGE(i+1) & " encryption failed" SEVERITY ERROR;
                fail_flag    := '1';
                fail_counter := fail_counter + 1;
            END IF;
            -- Set mode to decryption
            encryption_flag  <= '0';
            WAIT FOR clk_period;
            -- Write key and ciphertext in, updating on falling edge of clock
            WAIT UNTIL FALLING_EDGE(clk);
            key_data_in_flag <= '1';
            input_key        <= xtea_keys(i)(127 DOWNTO 96);
            input_data       <= encrypted_data(127 DOWNTO 96);
            WAIT FOR clk_period;
            input_key        <= xtea_keys(i)(95 DOWNTO 64);
            input_data       <= encrypted_data(95 DOWNTO 64);
            WAIT FOR clk_period;
            input_key        <= xtea_keys(i)(63 DOWNTO 32);
            input_data       <= encrypted_data(63 DOWNTO 32);
            WAIT FOR clk_period;
            input_key        <= xtea_keys(i)(31 DOWNTO 0);
            input_data       <= encrypted_data(31 DOWNTO 0);
            WAIT FOR clk_period;
            -- Stop key/ciphertext input
            key_data_in_flag <= '0';
            input_key        <= (OTHERS => '0');
            input_data       <= (OTHERS => '0');
            -- Wait until decryption complete
            WAIT UNTIL output_data_flag = '1';
            -- Read plaintext output on falling edge
            WAIT UNTIL FALLING_EDGE(clk);
            decrypted_data(127 DOWNTO 96) <= output_data;
            WAIT FOR clk_period;
            decrypted_data(95 DOWNTO 64)  <= output_data;
            WAIT FOR clk_period;
            decrypted_data(63 DOWNTO 32)  <= output_data;
            WAIT FOR clk_period;
            decrypted_data(31 DOWNTO 0)   <= output_data;
            WAIT FOR clk_period;
            -- Compare decrypted data with original plaintext
            IF decrypted_data = input_data_array(i) THEN
                REPORT "NOTE: Key/data pair " & INTEGER'IMAGE(i+1) & " decryption passed" SEVERITY NOTE;
            ELSE
                REPORT "ERROR: Key/data pair " & INTEGER'IMAGE(i+1) & " decryption failed" SEVERITY ERROR;
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
