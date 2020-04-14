--########################################################################################
--## Developer: Jack Sampford (j.w.sampford-15@student.lboro.ac.uk)                     ##
--##                                                                                    ##
--## Design name: xtea                                                                  ##
--## Module name: xtea_dec - RTL                                                        ##
--## Target devices: ARM MPS2+ FPGA Prototyping Board                                   ##
--## Tool versions: Quartus Prime 19.1, ModelSim Intel FPGA Starter Edition 10.5b       ##
--##                                                                                    ##
--## Description: XTEA decryption core component. Takes ciphertext data in and creates  ##
--## plaintext. Requires connection to subkey calculation block to provide requested    ##
--## subkeys. Data is read in 32 bits at a time when data_valid flag is set and output  ##
--## 32 bits at a time when decryption complete, marked by data_ready going high.       ##
--##                                                                                    ##
--## Dependencies: none                                                                 ##
--########################################################################################

-- Library declarations
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

-- Entity declaration
ENTITY xtea_dec IS
    PORT(
        -- Clock and active low reset
        clk           : IN  STD_LOGIC;
        reset_n       : IN  STD_LOGIC;

        -- Ciphertext input, one 32-bit word at a time
        data_word_in  : IN  STD_LOGIC_VECTOR(31 DOWNTO 0);
        -- Flag to enable ciphertext input
        data_valid    : IN  STD_LOGIC;

        -- Subkey input from subkey calculation component
        key_word_in   : IN  STD_LOGIC_VECTOR(31 DOWNTO 0);

        -- Flag to indicate decryption completion
        data_ready    : OUT STD_LOGIC;
        -- Data output, one 32-bit word at a time
        data_word_out : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
    );
END ENTITY xtea_dec;

-- Architecture definition
ARCHITECTURE rtl OF xtea_dec IS

    -- Set number of rounds minus two, standard is 32
    CONSTANT max_round    : INTEGER := 30;

    -- Delay signal for input flag to allow sequencing of calculation
    SIGNAL data_valid_d   : STD_LOGIC;

    -- Data input counter
    SIGNAL data_cntr      : INTEGER RANGE 0 TO 3;

    -- Calculation and round counters
    SIGNAL calc_flag      : STD_LOGIC;
    SIGNAL calc_cntr      : INTEGER RANGE 0 TO 5;
    SIGNAL round_cntr     : INTEGER RANGE 0 TO max_round+2;
    -- Last round flag
    SIGNAL last_round     : STD_LOGIC;

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
                data_valid_d <= '0';
            ELSE
                data_valid_d <= data_valid;
            END IF;
        END IF;
    END PROCESS input_delay;

    -- Calculation flag management
    calc_flag_set : PROCESS(clk)
    BEGIN
        IF RISING_EDGE(clk) THEN
            IF reset_n = '0' THEN
                calc_flag <= '0';
            ELSE
                IF data_valid_d = '1' AND data_valid = '0' THEN
                    -- Begin calculation once data loaded
                    calc_flag <= '1';
                ELSIF calc_cntr = 5 AND last_round = '1' THEN
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
                    IF calc_cntr = 1 AND last_round = '0' THEN
                        -- All round except last end after cycle 2
                        calc_cntr  <= 0;
                        round_cntr <= round_cntr + 1;
                        IF round_cntr = max_round THEN
                            -- Indicate final round reached
                            last_round <= '1';
                        END IF;
                    ELSIF calc_cntr = 5 AND last_round = '1' THEN
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

    -- Sequence input to combinatorial section and add result to output values
    output_accumulate : PROCESS(clk)
    BEGIN
        IF RISING_EDGE(clk) THEN
            IF reset_n = '0' THEN
                output_word_00 <= (OTHERS => '0');
                output_word_01 <= (OTHERS => '0');
                output_word_10 <= (OTHERS => '0');
                output_word_11 <= (OTHERS => '0');
                data_cntr      <= 0;
                comb_input_0   <= (OTHERS => '0');
                comb_input_1   <= (OTHERS => '0');
                data_ready     <= '0';
                data_word_out  <= (OTHERS => '0');
            ELSE
                -- Read input data
                IF data_valid = '1' THEN
                    IF data_cntr = 0 THEN
                        output_word_10 <= UNSIGNED(data_word_in);
                        data_cntr      <= data_cntr + 1;
                    ELSIF data_cntr = 1 THEN
                        output_word_11 <= UNSIGNED(data_word_in);
                        data_cntr      <= data_cntr + 1;
                    ELSIF data_cntr = 2 THEN
                        output_word_00 <= UNSIGNED(data_word_in);
                        data_cntr      <= data_cntr + 1;
                    ELSIF data_cntr = 3 THEN
                        output_word_01 <= UNSIGNED(data_word_in);
                        data_cntr      <= 0;
                    END IF;
                END IF;

                -- Perform calculations
                IF data_valid_d = '1' AND data_valid = '0' THEN
                    -- Set correct input for combinatorial sections
                    comb_input_0   <= STD_LOGIC_VECTOR(output_word_01);
                    comb_input_1   <= STD_LOGIC_VECTOR(output_word_11);
                ELSIF calc_cntr = 0 AND calc_flag = '1' THEN
                    -- Add newly calculated temp value to output values
                    output_word_00 <= output_word_00 - UNSIGNED(comb_out_0);
                    output_word_10 <= output_word_10 - UNSIGNED(comb_out_1);
                    -- Set correct input for combinatorial sections
                    comb_input_0   <= STD_LOGIC_VECTOR(output_word_00 - UNSIGNED(comb_out_0));
                    comb_input_1   <= STD_LOGIC_VECTOR(output_word_10 - UNSIGNED(comb_out_1));
                ELSIF calc_cntr = 1 THEN
                    -- Add newly calculated temp value to output values
                    output_word_01 <= output_word_01 - UNSIGNED(comb_out_0);
                    output_word_11 <= output_word_11 - UNSIGNED(comb_out_1);
                    -- Set correct input for combinatorial sections
                    comb_input_0   <= STD_LOGIC_VECTOR(output_word_01 - UNSIGNED(comb_out_0));
                    comb_input_1   <= STD_LOGIC_VECTOR(output_word_11 - UNSIGNED(comb_out_1));
                END IF;

                IF last_round = '1' THEN
                    -- Output final results
                    IF calc_cntr = 2 THEN
                        -- Output first 32 bits of data
                        data_ready    <= '1';
                        data_word_out <= STD_LOGIC_VECTOR(output_word_10);
                    ELSIF calc_cntr = 3 THEN
                        -- Output second 32 bits of data
                        data_ready    <= '1';
                        data_word_out <= STD_LOGIC_VECTOR(output_word_11);
                    ELSIF calc_cntr = 4 THEN
                        -- Output third 32 bits of data
                        data_ready    <= '1';
                        data_word_out <= STD_LOGIC_VECTOR(output_word_00);
                    ELSIF calc_cntr = 5 tHEN
                        -- Output final 32 bits of data
                        data_ready    <= '1';
                        data_word_out <= STD_LOGIC_VECTOR(output_word_01);
                    ELSE
                        -- Data output complete
                        data_ready    <= '0';
                        data_word_out <= (OTHERS => '0');
                    END IF;
                ELSE
                    data_ready <= '0';
                END IF;
            END IF;
        END IF;
    END PROCESS output_accumulate;

    -- Combinatorial logic section
    -- NOTE - may cause timing violations, additional calculation cycle may need adding
    -- Perform bit shifts and XOR
    temp_vector_00 <= (comb_input_0(27 DOWNTO 0) & "0000") XOR ("00000" & comb_input_0(31 DOWNTO 5));
    temp_vector_10 <= (comb_input_1(27 DOWNTO 0) & "0000") XOR ("00000" & comb_input_1(31 DOWNTO 5));
    -- Add temp value to original input value
    temp_vector_01 <= STD_LOGIC_VECTOR(UNSIGNED(temp_vector_00) + UNSIGNED(comb_input_0));
    temp_vector_11 <= STD_LOGIC_VECTOR(UNSIGNED(temp_vector_10) + UNSIGNED(comb_input_1));
    -- XOR with subkey to complete calculation
    comb_out_0     <= temp_vector_01 XOR key_word_in;
    comb_out_1     <= temp_vector_11 XOR key_word_in;

END rtl;
