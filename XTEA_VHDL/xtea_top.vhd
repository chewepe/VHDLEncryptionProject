--########################################################################################
--## Developer: Jack Sampford (j.w.sampford-15@student.lboro.ac.uk)                     ##
--##                                                                                    ##
--## Design name: xtea                                                                  ##
--## Module name: xtea_top - RTL                                                        ##
--## Target devices: ARM MPS2+ FPGA Prototyping Board                                   ##
--## Tool versions: Quartus Prime 19.1, ModelSim Intel FPGA Starter Edition 10.5b       ##
--##                                                                                    ##
--## Description: XTEA encryption/decryption core. Takes in key and either plaintext or ##
--## ciphertext data 32 bits at a time and encrypts/decrypts the data as per the        ##
--## setting of the encryption input flag. Encrypted data is output 32 bits at a time   ##
--## on data_word_out output when data_ready flag goes high.                            ##
--##                                                                                    ##
--## Dependencies: None                                                                 ##
--########################################################################################

-- Library declarations
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

-- Entity definition
ENTITY xtea_top IS
    PORT(
        -- Clock and active low reset
        clk            : IN  STD_LOGIC;
        reset_n        : IN  STD_LOGIC;

        -- Switch to enable encryption or decryption, 1 for encryption 0 for decryption
        encryption     : IN  STD_LOGIC;

        -- Flag to begin the input of data/key
        key_data_valid : IN  STD_LOGIC;
        -- Data/ciphertext input, one 32-bit word at a time
        data_word_in   : IN  STD_LOGIC_VECTOR(31 DOWNTO 0);
        -- Key input, one 32-bit word at a time
        key_word_in    : IN  STD_LOGIC_VECTOR(31 DOWNTO 0);

        -- Data/ciphertext output, one 32-bit word at a time
        data_word_out  : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
        -- Flag to indicate beginning of data output
        data_ready     : OUT STD_LOGIC
    );
END ENTITY xtea_top;

-- Architecture definition
ARCHITECTURE rtl OF xtea_top IS

    -- Set number of rounds minus two, standard is 32
    CONSTANT max_round : INTEGER := 30;

    -- Value to modify internal sum by, fixed as per XTEA standard
    CONSTANT delta     : UNSIGNED := UNSIGNED'(x"9E3779B9");

    -- Delay signal for input flag to allow sequencing of calculation
    SIGNAL key_data_valid_d : STD_LOGIC;

    -- Data input signals
    SIGNAL data_word_00 : UNSIGNED(31 DOWNTO 0);
    SIGNAL data_word_01 : UNSIGNED(31 DOWNTO 0);
    SIGNAL data_word_10 : UNSIGNED(31 DOWNTO 0);
    SIGNAL data_word_11 : UNSIGNED(31 DOWNTO 0);
    SIGNAL data_cntr    : INTEGER RANGE 0 TO 3;

    -- Key array
    TYPE key_arr IS ARRAY(0 TO 3) OF UNSIGNED(31 DOWNTO 0);
    SIGNAL key_block : key_arr;

    -- Calculation and round counters
    SIGNAL calc_flag  : STD_LOGIC;
    SIGNAL calc_cntr  : INTEGER RANGE 0 TO 8;
    SIGNAL round_cntr : INTEGER RANGE 0 TO max_round+2;
    -- Last round flag
    SIGNAL last_round : STD_LOGIC;

    -- Subkey calculation signals
    SIGNAL subkey : UNSIGNED(31 DOWNTO 0);
    SIGNAL sum    : UNSIGNED(31 DOWNTO 0);

    -- Output calculation signals
    SIGNAL output_word_00 : UNSIGNED(31 DOWNTO 0);
    SIGNAL output_word_01 : UNSIGNED(31 DOWNTO 0);
    SIGNAL output_word_10 : UNSIGNED(31 DOWNTO 0);
    SIGNAL output_word_11 : UNSIGNED(31 DOWNTO 0);
    SIGNAL temp_vector_00 : STD_LOGIC_VECTOR(31 DOWNTO 0);
    SIGNAL temp_vector_01 : STD_LOGIC_VECTOR(31 DOWNTO 0);
    SIGNAL temp_vector_10 : STD_LOGIC_VECTOR(31 DOWNTO 0);
    SIGNAL temp_vector_11 : STD_LOGIC_VECTOR(31 DOWNTO 0);
    SIGNAL comb_input_0   : STD_LOGIC_VECTOR(31 DOWNTO 0);
    SIGNAL comb_input_1   : STD_LOGIC_VECTOR(31 DOWNTO 0);
    SIGNAL comb_out_0     : STD_LOGIC_VECTOR(31 DOWNTO 0);
    SIGNAL comb_out_1     : STD_LOGIC_VECTOR(31 DOWNTO 0);

BEGIN

    -- Delay input to allow correct sequencing of calculation
    input_delay : PROCESS(clk)
    BEGIN
        IF RISING_EDGE(clk) THEN
            IF reset_n = '0' THEN
                key_data_valid_d <= '0';
            ELSE
                key_data_valid_d <= key_data_valid;
            END IF;
        END IF;
    END PROCESS input_delay;

    -- Load input words and key into 128-bit block
    data_key_read : PROCESS(clk)
    BEGIN
        IF RISING_EDGE(clk) THEN
            IF reset_n = '0' THEN
                data_word_00   <= (OTHERS => '0');
                data_word_01   <= (OTHERS => '0');
                data_word_10   <= (OTHERS => '0');
                data_word_11   <= (OTHERS => '0');
                key_block      <= (OTHERS => (OTHERS => '0'));
                data_cntr      <= 0;
            ELSE
                IF key_data_valid = '1' THEN
                    IF encryption = '1' THEN
                        -- Data written opposite way for decryption, i.e.
                        -- Encryption:
                        -- 00 <= data(31 DOWNTO 0)
                        -- 01 <= data(63 DOWNTO 32)
                        -- 10 <= data(95 DOWNTO 64)
                        -- 11 <= data(127 DOWNTO 96)
                        -- Decryption:
                        -- 00 <= data(63 DOWNTO 32)
                        -- 01 <= data(31 DOWNTO 0)
                        -- 10 <= data(127 DOWNTO 96)
                        -- 11 <= data(95 DOWNTO 64)
                        IF data_cntr = 0 THEN
                            data_word_11   <= UNSIGNED(data_word_in);
                            key_block(3)   <= UNSIGNED(key_word_in);
                            data_cntr      <= data_cntr + 1;
                        ELSIF data_cntr = 1 THEN
                            data_word_10   <= UNSIGNED(data_word_in);
                            key_block(2)   <= UNSIGNED(key_word_in);
                            data_cntr      <= data_cntr + 1;
                        ELSIF data_cntr = 2 THEN
                            data_word_01   <= UNSIGNED(data_word_in);
                            key_block(1)   <= UNSIGNED(key_word_in);
                            data_cntr      <= data_cntr + 1;
                        ELSIF data_cntr = 3 THEN
                            data_word_00   <= UNSIGNED(data_word_in);
                            key_block(0)   <= UNSIGNED(key_word_in);
                            data_cntr      <= 0;
                        END IF;
                    ELSE
                        IF data_cntr = 0 THEN
                            data_word_10   <= UNSIGNED(data_word_in);
                            key_block(3)   <= UNSIGNED(key_word_in);
                            data_cntr      <= data_cntr + 1;
                        ELSIF data_cntr = 1 THEN
                            data_word_11   <= UNSIGNED(data_word_in);
                            key_block(2)   <= UNSIGNED(key_word_in);
                            data_cntr      <= data_cntr + 1;
                        ELSIF data_cntr = 2 THEN
                            data_word_00   <= UNSIGNED(data_word_in);
                            key_block(1)   <= UNSIGNED(key_word_in);
                            data_cntr      <= data_cntr + 1;
                        ELSIF data_cntr = 3 THEN
                            data_word_01   <= UNSIGNED(data_word_in);
                            key_block(0)   <= UNSIGNED(key_word_in);
                            data_cntr      <= 0;
                        END IF;
                    END IF;
                END IF;
            END IF;
        END IF;
    END PROCESS data_key_read;

    -- Calculation flag management
    calc_flag_set : PROCESS(clk)
    BEGIN
        IF RISING_EDGE(clk) THEN
            IF reset_n = '0' THEN
                calc_flag <= '0';
            ELSE
                IF key_data_valid_d = '1' AND key_data_valid = '0' THEN
                    -- Begin calculation once data and key loaded
                    calc_flag <= '1';
                ELSIF calc_cntr = 8 AND last_round = '1' THEN
                    -- Deactivate after last round complete and data output
                    calc_flag <= '0';
                END IF;
            END IF;
        END IF;
    END PROCESS calc_flag_set;

    -- Calculation counter management
    calc_cntr_manage : PROCESS(clk)
    BEGIN
        IF RISING_EDGE(clk) THEN
            IF reset_n = '0' THEN
                calc_cntr  <= 0;
                round_cntr <= 0;
                last_round <= '0';
            ELSE
                IF calc_flag = '1' THEN
                    IF calc_cntr = 4 AND last_round = '0' THEN
                        -- All rounds except last end after cycle 4
                        calc_cntr  <= 0;
                        round_cntr <= round_cntr + 1;
                        IF round_cntr = max_round THEN
                            -- Indicate final round reached
                            last_round <= '1';
                        END IF;
                    ELSIF calc_cntr = 8 AND last_round = '1' THEN
                        -- Last round complete
                        calc_cntr  <= 0;
                        round_cntr <= round_cntr + 1;
                    ELSE
                        calc_cntr <= calc_cntr + 1;
                    END IF;
                ELSE
                    calc_cntr  <= 0;
                    round_cntr <= 0;
                    last_round <= '0';
                END IF;
            END IF;
        END IF;
    END PROCESS calc_cntr_manage;

    -- Calculate subkeys required for round operations
    subkey_calc : PROCESS(clk)
    BEGIN
        IF RISING_EDGE(clk) THEN
            IF reset_n = '0' THEN
                subkey <= (OTHERS => '0');
                sum    <= (OTHERS => '0');
            ELSE
                IF key_data_valid_d = '1' AND key_data_valid = '0' THEN
                    IF encryption = '1' THEN
                        -- Set initial sum value to 0 for encryption
                        sum <= (OTHERS => '0');
                    ELSE
                        -- Set sum to correct initial value for 64-round decryption
                        sum <= x"C6EF3720";
                    END IF;
                ELSIF calc_cntr = 1 THEN
                    -- Perform first subkey calculation
                    IF encryption = '1' THEN
                        -- Perform addition and AND operations to generate subkey
                        subkey <= sum + key_block(TO_INTEGER(sum AND x"00000003"));
                        -- Recalculate internal sum variable
                        sum    <= sum + delta;
                    ELSE
                        -- Perform shifting, addition and AND operations to generate reverse subkey
                        subkey <= sum + key_block(TO_INTEGER(("00000000000" & sum(31 DOWNTO 11)) AND x"00000003"));
                        -- Recalculate internal sum variable
                        sum    <= sum - delta;
                    END IF;
                ELSIF calc_cntr = 3 THEN
                    -- Perform second subkey calculation
                    IF encryption = '1' THEN
                        -- Perform shifting, addition and AND operations to generate subkey
                        subkey <= sum + key_block(TO_INTEGER(("00000000000" & sum(31 DOWNTO 11)) AND x"00000003"));
                    ELSE
                        -- Perform addition and AND operations to generate subkey
                        subkey <= sum + key_block(TO_INTEGER(sum AND x"00000003"));
                    END IF;
                END IF;
            END IF;
        END IF;
    END PROCESS subkey_calc;

    -- Sequence input to combinatorial section and add result to output values
    output_accumulate : PROCESS(clk)
    BEGIN
        IF RISING_EDGE(clk) THEN
            IF reset_n = '0' THEN
                output_word_00 <= (OTHERS => '0');
                output_word_01 <= (OTHERS => '0');
                output_word_10 <= (OTHERS => '0');
                output_word_11 <= (OTHERS => '0');
                comb_input_0   <= (OTHERS => '0');
                comb_input_1   <= (OTHERS => '0');
                data_ready     <= '0';
                data_word_out  <= (OTHERS => '0');
            ELSE
                IF key_data_valid_d = '1' AND key_data_valid = '0' THEN
                    -- Read in new data values
                    output_word_00 <= data_word_00;
                    output_word_01 <= data_word_01;
                    output_word_10 <= data_word_10;
                    output_word_11 <= data_word_11;
                ELSIF calc_cntr = 1 THEN
                    -- Set correct input for combinatorial sections
                    comb_input_0 <= STD_LOGIC_VECTOR(output_word_01);
                    comb_input_1 <= STD_LOGIC_VECTOR(output_word_11);
                ELSIF calc_cntr = 2 THEN
                    -- Add/subtract newly calculated temp value from output values
                    IF encryption = '1' THEN
                        output_word_00 <= output_word_00 + UNSIGNED(comb_out_0);
                        output_word_10 <= output_word_10 + UNSIGNED(comb_out_1);
                    ELSE
                        output_word_00 <= output_word_00 - UNSIGNED(comb_out_0);
                        output_word_10 <= output_word_10 - UNSIGNED(comb_out_1);
                    END IF;
                ELSIF calc_cntr = 3 THEN
                    -- Set correct input for combinatorial sections
                    comb_input_0 <= STD_LOGIC_VECTOR(output_word_00);
                    comb_input_1 <= STD_LOGIC_VECTOR(output_word_10);
                ELSIF calc_cntr = 4 THEN
                    -- Add/subtract newly calculated temp value from output values
                    IF encryption = '1' THEN
                        output_word_01 <= output_word_01 + UNSIGNED(comb_out_0);
                        output_word_11 <= output_word_11 + UNSIGNED(comb_out_1);
                    ELSE
                        output_word_01 <= output_word_01 - UNSIGNED(comb_out_0);
                        output_word_11 <= output_word_11 - UNSIGNED(comb_out_1);
                    END IF;
                END IF;

                IF last_round = '1' THEN
                    -- Data written opposite way for decryption, same as data input above
                    IF encryption = '1' THEN
                        -- Output final results
                        IF calc_cntr = 5 THEN
                            -- Output first 32 bits of data
                            data_ready    <= '1';
                            data_word_out <= STD_LOGIC_VECTOR(output_word_11);
                        ELSIF calc_cntr = 6 THEN
                            -- Output second 32 bits of data
                            data_ready    <= '1';
                            data_word_out <= STD_LOGIC_VECTOR(output_word_10);
                        ELSIF calc_cntr = 7 THEN
                            -- Output third 32 bits of data
                            data_ready    <= '1';
                            data_word_out <= STD_LOGIC_VECTOR(output_word_01);
                        ELSIF calc_cntr = 8 THEN
                            -- Output final 32 bits of data
                            data_ready    <= '1';
                            data_word_out <= STD_LOGIC_VECTOR(output_word_00);
                        ELSE
                            -- Data output complete
                            data_ready    <= '0';
                            data_word_out <= (OTHERS => '0');
                        END IF;
                    ELSE
                        -- Output final results
                        IF calc_cntr = 5 THEN
                            -- Output first 32 bits of data
                            data_ready    <= '1';
                            data_word_out <= STD_LOGIC_VECTOR(output_word_10);
                        ELSIF calc_cntr = 6 THEN
                            -- Output second 32 bits of data
                            data_ready    <= '1';
                            data_word_out <= STD_LOGIC_VECTOR(output_word_11);
                        ELSIF calc_cntr = 7 THEN
                            -- Output third 32 bits of data
                            data_ready    <= '1';
                            data_word_out <= STD_LOGIC_VECTOR(output_word_00);
                        ELSIF calc_cntr = 8 THEN
                            -- Output final 32 bits of data
                            data_ready    <= '1';
                            data_word_out <= STD_LOGIC_VECTOR(output_word_01);
                        ELSE
                            -- Data output complete
                            data_ready    <= '0';
                            data_word_out <= (OTHERS => '0');
                        END IF;
                    END IF;
                ELSE
                    data_ready <= '0';
                END IF;
            END IF;
        END IF;
    END PROCESS output_accumulate;

    -- Combinatorial logic section
    -- NOTE - may cause timing violations, register may need adding
    -- Perform bit shifts and XOR
    temp_vector_00 <= (comb_input_0(27 DOWNTO 0) & "0000") XOR ("00000" & comb_input_0(31 DOWNTO 5));
    temp_vector_10 <= (comb_input_1(27 DOWNTO 0) & "0000") XOR ("00000" & comb_input_1(31 DOWNTO 5));
    -- Add temp value to original input value
    temp_vector_01 <= STD_LOGIC_VECTOR(UNSIGNED(temp_vector_00) + UNSIGNED(comb_input_0));
    temp_vector_11 <= STD_LOGIC_VECTOR(UNSIGNED(temp_vector_10) + UNSIGNED(comb_input_1));
    -- XOR with subkey to complete calculation
    comb_out_0     <= temp_vector_01 XOR STD_LOGIC_VECTOR(subkey);
    comb_out_1     <= temp_vector_11 XOR STD_LOGIC_VECTOR(subkey);

END rtl;
