--########################################################################################
--## Developer: Jack Sampford (j.w.sampford-15@student.lboro.ac.uk)                     ##
--##                                                                                    ##
--## Design name: aes                                                                   ##
--## Module name: aes_dec - RTL                                                         ##
--## Target devices: ARM MPS2+ FPGA Prototyping Board                                   ##
--## Tool versions: Quartus Prime 19.1, ModelSim Intel FPGA Starter Edition 10.5b       ##
--##                                                                                    ##
--## Description: AES decryption core component. Takes ciphertext data in and creates   ##
--## plaintext. Requires connection to key expansion block to provide requested         ##
--## subkeys. Data is read in 32 bits at a time when data_valid flag is set and output  ##
--## 32 bits at a time when decryption complete, marked by data_ready going high.       ##
--##                                                                                    ##
--## Dependencies: aes_pkg.vhd                                                          ##
--########################################################################################

-- Library declarations
LIBRARY IEEE;
LIBRARY aes;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;
USE aes.aes_pkg.ALL;

-- Entity definition
ENTITY aes_dec IS
    GENERIC(
        -- Length of input key, 0, 1 or 2 for 128, 192 or 256 respectively
        key_length : IN INTEGER RANGE 0 TO 2 := 0
    );
    PORT(
        -- Clock and active low reset
        clk            : IN  STD_LOGIC;
        reset_n        : IN  STD_LOGIC;

        -- Ciphertext input, one 32-bit word at a time
        data_word_in   : IN  STD_LOGIC_VECTOR(31 DOWNTO 0);
        -- Flag to enable ciphertext input
        data_valid     : IN  STD_LOGIC;

        -- Subkey input from key expansion component
        key_word_in    : IN  STD_LOGIC_VECTOR(31 DOWNTO 0);

        -- Flag to request subkey output from key expansion block
        get_key        : OUT STD_LOGIC;
        -- Which subkey to retrieve (0-43 for 128, 0-51 for 192, 0-59 for 256)
        get_key_number : OUT STD_LOGIC_VECTOR(5 DOWNTO 0);

        -- Flag to indicate decryption completion
        data_ready     : OUT STD_LOGIC;
        -- Data output, one 32-bit word at a time
        data_word_out  : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
    );
END ENTITY aes_dec;

-- Architecture definition
ARCHITECTURE rtl OF aes_dec IS

    -- Delay signals for control
    SIGNAL data_word_in_d  : STD_LOGIC_VECTOR(31 DOWNTO 0);
    SIGNAL data_word_in_d2 : STD_lOGIC_VECTOR(31 DOWNTO 0);
    SIGNAL data_valid_d    : STD_LOGIC;
    SIGNAL data_valid_d2   : STD_LOGIC;
    SIGNAL get_key_d       : STD_LOGIC;

    -- Internal get key signal to read output
    SIGNAL get_key_int     : STD_LOGIC;

    -- Temporary subkey number, unsigned to allow mathematical operations
    SIGNAL get_key_number_temp : UNSIGNED(5 DOWNTO 0);

    -- State table array
    SIGNAL state_table : state_table_t;

    -- State RAM array
    SIGNAL state_sram : state_ram_t;

    -- State RAM read/write signals
    SIGNAL state_sram_wen   : STD_LOGIC;
    SIGNAL state_sram_waddr : INTEGER RANGE 0 TO 3;
    SIGNAL state_sram_raddr : INTEGER RANGE 0 TO 3;
    SIGNAL state_sram_din   : STD_LOGIC_VECTOR(31 DOWNTO 0);
    SIGNAL state_sram_dout  : STD_LOGIC_VECTOR(31 DOWNTO 0);

    -- Temporary vectors for round key XOR and inverse mix columns calculations
    SIGNAL state_temp   : state_table_t;
    SIGNAL state_col_2x : state_table_t;
    SIGNAL state_col_4x : state_table_t;
    SIGNAL state_col_8x : state_table_t;

    -- Calculation and round counters
    SIGNAL calc_flag  : STD_LOGIC;
    SIGNAL calc_cntr  : INTEGER RANGE 0 TO 10;
    SIGNAL round_cntr : INTEGER RANGE 0 TO 14;
    SIGNAL max_round  : INTEGER RANGE 0 TO 14;
    -- Last round flag
    SIGNAL last_round : STD_LOGIC;

BEGIN

    -- Delay input to allow correct sequencing of key retrieval
    input_delay : PROCESS(clk)
    BEGIN
        IF RISING_EDGE(clk) THEN
            data_word_in_d  <= data_word_in;
            -- Reverse byte order to match key expansion
            data_word_in_d2 <= data_word_in_d(7 DOWNTO 0) & data_word_in_d(15 DOWNTO 8) & data_word_in_d(23 DOWNTO 16) & data_word_in_d(31 DOWNTO 24);
            data_valid_d    <= data_valid;
            data_valid_d2   <= data_valid_d;
            get_key_d       <= get_key_int;
            -- get_key_d should go high the same cycle as the key arrives from key expansion block
            state_sram_wen  <= get_key_d;
        END IF;
    END PROCESS input_delay;

    -- Manage the setting of get_key flag to request subkeys from key expansion component
    get_key_flag : PROCESS(clk)
    BEGIN
        IF RISING_EDGE(clk) THEN
            IF data_valid = '1' THEN
                -- Flag to get first round key for initial data
                get_key_int <= '1';
            ELSIF calc_cntr >= 4 AND calc_cntr <= 7 THEN
                -- Get subkeys for required computation steps
                get_key_int <= '1';
            ELSE
                -- Unset at all other times
                get_key_int <= '0';
            END IF;
        END IF;
    END PROCESS get_key_flag;

    -- Output internal signal
    get_key <= get_key_int;

    -- Sequence key number to request
    get_key_sequence : PROCESS(clk)
    BEGIN
        IF RISING_EDGE(clk) THEN
            IF reset_n = '0' THEN
                -- Begin with final subkey minus 3 for each key length
                IF key_length = 0 THEN
                    -- Subkey 43 for AES-128
                    get_key_number_temp <= "101000";
                ELSIF key_length = 1 THEN
                    -- Subkey 51 for AES-192
                    get_key_number_temp <= "110000";
                ELSIF key_length = 2 THEN
                    -- Subkey 59 for AES-256
                    get_key_number_temp <= "111000";
                END IF;
            ELSE
                IF data_valid = '1' AND data_valid_d = '0' THEN
                    -- Reset to end value on input of new data
                    IF key_length = 0 THEN
                        get_key_number_temp <= "101000";
                    ELSIF key_length = 1 THEN
                        get_key_number_temp <= "110000";
                    ELSIF key_length = 2 THEN
                        get_key_number_temp <= "111000";
                    END IF;
                ELSIF get_key_int = '1' THEN
                    -- Subkey number cycles 40, 41, 42, 43, 36, 37, 38, 39, 32, 33, 34, 35, etc. for AES-128
                    IF (get_key_number_temp MOD 4) = 3 THEN
                        get_key_number_temp <= get_key_number_temp - 7;
                    ELSE
                        -- Cycle correct subkey key number values
                        get_key_number_temp <= get_key_number_temp + 1;
                    END IF;
                END IF;
            END IF;
        END IF;
    END PROCESS get_key_sequence;

    -- Output required key number to key expansion component
    get_key_number <= STD_LOGIC_VECTOR(get_key_number_temp);

    -- State RAM write address sequencing
    sram_waddr_seq : PROCESS(clk)
    BEGIN
        IF RISING_EDGE(clk) THEN
            IF reset_n = '0' THEN
                state_sram_waddr <= 0;
            ELSE
                IF data_valid = '1' AND data_valid_d = '0' THEN
                    -- Reset to 0 on input of new data
                    state_sram_waddr <= 0;
                ELSIF state_sram_wen = '1' THEN
                    -- Increment address whilst writing
                    IF state_sram_waddr = 3 THEN
                        state_sram_waddr <= 0;
                    ELSE
                        state_sram_waddr <= state_sram_waddr + 1;
                    END IF;
                END IF;
            END IF;
        END IF;
    END PROCESS sram_waddr_seq;

    -- State RAM address sequencing
    sram_raddr_seq : PROCESS(clk)
    BEGIN
        IF RISING_EDGE(clk) THEN
            IF reset_n = '0' THEN
                state_sram_raddr <= 0;
            ELSE
                IF calc_cntr >= 1 AND calc_cntr <= 3 THEN
                    -- Read from state RAM at required calculation stages
                    state_sram_raddr <= state_sram_raddr + 1;
                ELSIF calc_cntr = 0 THEN
                    -- Reset at beginning of calculation
                    state_sram_raddr <= 0;
                END IF;
            END IF;
        END IF;
    END PROCESS sram_raddr_seq;

    -- State RAM read/write
    sram_read_write : PROCESS(clk)
    BEGIN
        IF RISING_EDGE(clk) THEN
            IF state_sram_wen = '1' THEN
                -- Write to correct address in state RAM
                state_sram(state_sram_waddr) <= state_sram_din;
            END IF;
            -- Read from correct address in state RAM
            state_sram_dout <= state_sram(state_sram_raddr);
        END IF;
    END PROCESS sram_read_write;

    -- Perform key XORing with state table
    key_xor_gen_1 : FOR i IN 0 TO 3 GENERATE
        key_xor_gen_2 : FOR j IN 0 TO 3 GENERATE
            state_temp((i*4) + j) <= state_table((i*4) + j) XOR key_word_in(((j*8) + 7) DOWNTO (j*8));
        END GENERATE;
    END GENERATE;

    -- Precalculate state columns multipled by 2, 4 and 8 for inverse mix columns step
    state_col_mult : FOR i IN 0 TO 15 GENERATE
        state_col_2x(i) <= (x"1B" XOR (state_temp(i)(6 DOWNTO 0) & "0")) WHEN state_temp(i)(7) = '1' ELSE (state_temp(i)(6 DOWNTO 0) & "0");
        state_col_4x(i) <= (x"1B" XOR (state_col_2x(i)(6 DOWNTO 0) & "0")) WHEN state_col_2x(i)(7) = '1' ELSE (state_col_2x(i)(6 DOWNTO 0) & "0");
        state_col_8x(i) <= (x"1B" XOR (state_col_4x(i)(6 DOWNTO 0) & "0")) WHEN state_col_4x(i)(7) = '1' ELSE (state_col_4x(i)(6 DOWNTO 0) & "0");
    END GENERATE;

    -- Perform column mixing and round key XORing using precalculated values
    col_mix_rkey_xor : PROCESS(clk)
    BEGIN
        IF RISING_EDGE(clk) THEN
            IF reset_n = '0' THEN
                state_sram_din <= (OTHERS => '0');
            ELSE
                IF data_valid_d2 = '1' THEN
                    -- Perform XOR of initial round key with delayed original data
                    state_sram_din <= data_word_in_d2 XOR key_word_in;
                ELSIF last_round = '0' THEN
                    -- Perform column mixing in all rounds except last
                    IF calc_cntr = 6 THEN
                        -- Perform column mixing for first column
                        state_sram_din(7 DOWNTO 0)   <= state_col_8x(0)  XOR state_col_4x(0)  XOR state_col_2x(0)  XOR  -- 14x
                                                        state_col_8x(1)  XOR state_col_2x(1)  XOR state_temp(1)    XOR  -- 11x
                                                        state_col_8x(2)  XOR state_col_4x(2)  XOR state_temp(2)    XOR  -- 13x
                                                        state_col_8x(3)  XOR state_temp(3);                             -- 9x
                        state_sram_din(15 DOWNTO 8)  <= state_col_8x(0)  XOR state_temp(0)    XOR                       -- 9x
                                                        state_col_8x(1)  XOR state_col_4x(1)  XOR state_col_2x(1)  XOR  -- 14x
                                                        state_col_8x(2)  XOR state_col_2x(2)  XOR state_temp(2)    XOR  -- 11x
                                                        state_col_8x(3)  XOR state_col_4x(3)  XOR state_temp(3);        -- 13x
                        state_sram_din(23 DOWNTO 16) <= state_col_8x(0)  XOR state_col_4x(0)  XOR state_temp(0)    XOR  -- 13x
                                                        state_col_8x(1)  XOR state_temp(1)    XOR                       -- 9x
                                                        state_col_8x(2)  XOR state_col_4x(2)  XOR state_col_2x(2)  XOR  -- 14x
                                                        state_col_8x(3)  XOR state_col_2x(3)  XOR state_temp(3);        -- 11x
                        state_sram_din(31 DOWNTO 24) <= state_col_8x(0)  XOR state_col_2x(0)  XOR state_temp(0)    XOR  -- 11x
                                                        state_col_8x(1)  XOR state_col_4x(1)  XOR state_temp(1)    XOR  -- 13x
                                                        state_col_8x(2)  XOR state_temp(2)    XOR                       -- 9x
                                                        state_col_8x(3)  XOR state_col_4x(3)  XOR state_col_2x(3);      -- 14x
                    ELSIF calc_cntr = 7 THEN
                        -- Perform column mixing for second column
                        state_sram_din(7 DOWNTO 0)   <= state_col_8x(4)  XOR state_col_4x(4)  XOR state_col_2x(4)  XOR  -- 14x
                                                        state_col_8x(5)  XOR state_col_2x(5)  XOR state_temp(5)    XOR  -- 11x
                                                        state_col_8x(6)  XOR state_col_4x(6)  XOR state_temp(6)    XOR  -- 13x
                                                        state_col_8x(7)  XOR state_temp(7);                             -- 9x
                        state_sram_din(15 DOWNTO 8)  <= state_col_8x(4)  XOR state_temp(4)    XOR                       -- 9x
                                                        state_col_8x(5)  XOR state_col_4x(5)  XOR state_col_2x(5)  XOR  -- 14x
                                                        state_col_8x(6)  XOR state_col_2x(6)  XOR state_temp(6)    XOR  -- 11x
                                                        state_col_8x(7)  XOR state_col_4x(7)  XOR state_temp(7);        -- 13x
                        state_sram_din(23 DOWNTO 16) <= state_col_8x(4)  XOR state_col_4x(4)  XOR state_temp(4)    XOR  -- 13x
                                                        state_col_8x(5)  XOR state_temp(5)    XOR                       -- 9x
                                                        state_col_8x(6)  XOR state_col_4x(6)  XOR state_col_2x(6)  XOR  -- 14x
                                                        state_col_8x(7)  XOR state_col_2x(7)  XOR state_temp(7);        -- 11x
                        state_sram_din(31 DOWNTO 24) <= state_col_8x(4)  XOR state_col_2x(4)  XOR state_temp(4)    XOR  -- 11x
                                                        state_col_8x(5)  XOR state_col_4x(5)  XOR state_temp(5)    XOR  -- 13x
                                                        state_col_8x(6)  XOR state_temp(6)    XOR                       -- 9x
                                                        state_col_8x(7)  XOR state_col_4x(7)  XOR state_col_2x(7);      -- 14x
                    ELSIF calc_cntr = 8 THEN
                        -- Perform column mixing for third column
                        state_sram_din(7 DOWNTO 0)   <= state_col_8x(8)  XOR state_col_4x(8)  XOR state_col_2x(8)  XOR  -- 14x
                                                        state_col_8x(9)  XOR state_col_2x(9)  XOR state_temp(9)    XOR  -- 11x
                                                        state_col_8x(10) XOR state_col_4x(10) XOR state_temp(10)   XOR  -- 13x
                                                        state_col_8x(11) XOR state_temp(11);                            -- 9x
                        state_sram_din(15 DOWNTO 8)  <= state_col_8x(8)  XOR state_temp(8)    XOR                       -- 9x
                                                        state_col_8x(9)  XOR state_col_4x(9)  XOR state_col_2x(9)  XOR  -- 14x
                                                        state_col_8x(10) XOR state_col_2x(10) XOR state_temp(10)   XOR  -- 11x
                                                        state_col_8x(11) XOR state_col_4x(11) XOR state_temp(11);       -- 13x
                        state_sram_din(23 DOWNTO 16) <= state_col_8x(8)  XOR state_col_4x(8)  XOR state_temp(8)    XOR  -- 13x
                                                        state_col_8x(9)  XOR state_temp(9)    XOR                       -- 9x
                                                        state_col_8x(10) XOR state_col_4x(10) XOR state_col_2x(10) XOR  -- 14x
                                                        state_col_8x(11) XOR state_col_2x(11) XOR state_temp(11);       -- 11x
                        state_sram_din(31 DOWNTO 24) <= state_col_8x(8)  XOR state_col_2x(8)  XOR state_temp(8)    XOR  -- 11x
                                                        state_col_8x(9)  XOR state_col_4x(9)  XOR state_temp(9)    XOR  -- 13x
                                                        state_col_8x(10) XOR state_temp(10)   XOR                       -- 9x
                                                        state_col_8x(11) XOR state_col_4x(11) XOR state_col_2x(11);     -- 14x
                    ELSIF calc_cntr = 9 THEN
                        -- Perform column mixing for fourth column
                        state_sram_din(7 DOWNTO 0)   <= state_col_8x(12) XOR state_col_4x(12) XOR state_col_2x(12) XOR  -- 14x
                                                        state_col_8x(13) XOR state_col_2x(13) XOR state_temp(13)   XOR  -- 11x
                                                        state_col_8x(14) XOR state_col_4x(14) XOR state_temp(14)   XOR  -- 13x
                                                        state_col_8x(15) XOR state_temp(15);                            -- 9x
                        state_sram_din(15 DOWNTO 8)  <= state_col_8x(12) XOR state_temp(12)   XOR                       -- 9x
                                                        state_col_8x(13) XOR state_col_4x(13) XOR state_col_2x(13) XOR  -- 14x
                                                        state_col_8x(14) XOR state_col_2x(14) XOR state_temp(14)   XOR  -- 11x
                                                        state_col_8x(15) XOR state_col_4x(15) XOR state_temp(15);       -- 13x
                        state_sram_din(23 DOWNTO 16) <= state_col_8x(12) XOR state_col_4x(12) XOR state_temp(12)   XOR  -- 13x
                                                        state_col_8x(13) XOR state_temp(13)   XOR                       -- 9x
                                                        state_col_8x(14) XOR state_col_4x(14) XOR state_col_2x(14) XOR  -- 14x
                                                        state_col_8x(15) XOR state_col_2x(15) XOR state_temp(15);       -- 11x
                        state_sram_din(31 DOWNTO 24) <= state_col_8x(12) XOR state_col_2x(12) XOR state_temp(12)   XOR  -- 11x
                                                        state_col_8x(13) XOR state_col_4x(13) XOR state_temp(13)   XOR  -- 13x
                                                        state_col_8x(14) XOR state_temp(14)   XOR                       -- 9x
                                                        state_col_8x(15) XOR state_col_4x(15) XOR state_col_2x(15);     -- 14x
                    END IF;
                END IF;
            END IF;
        END IF;
    END PROCESS col_mix_rkey_xor;

    -- Calculation flag management
    calc_flag_set : PROCESS(clk)
    BEGIN
        IF RISING_EDGE(clk) THEN
            IF reset_n = '0' THEN
                calc_flag <= '0';
            ELSE
                IF data_valid_d2 = '1' AND data_valid_d = '0' THEN
                    -- Activate on falling edge of delayed valid data flag (end of data stream)
                    calc_flag <= '1';
                ELSIF calc_cntr = 10 AND last_round = '1' THEN
                    -- Deactivate after last round complete and data output
                    calc_flag <= '0';
                END IF;
            END IF;
        END IF;
    END PROCESS calc_flag_set;

    -- Set max round number for each key length, offset by 1 to account for counter cycle delay
    max_round <= 8  WHEN key_length = 0 ELSE
                 10 WHEN key_length = 1 ELSE
                 12 WHEN key_length = 2 ELSE
                 8;

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
                    IF calc_cntr = 9 AND last_round = '0' THEN
                        -- All rounds except last round end after cycle 9 (end of inverse mix columns step)
                        calc_cntr  <= 0;
                        round_cntr <= round_cntr + 1;
                        IF round_cntr = max_round THEN
                            -- Indicate final round reached
                            last_round <= '1';
                        END IF;
                    ELSIF calc_cntr = 10 AND last_round = '1' THEN
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

    -- Inverse substitute, inverse shift rows, final round XOR and data output
    sub_row_shift_final_round : PROCESS(clk)
    BEGIN
        IF RISING_EDGE(clk) THEN
            IF calc_cntr = 2 THEN
                -- Perform first inverse substitution and inverse row shift
                state_table(0)  <= sbox_rev_c(TO_INTEGER(UNSIGNED(state_sram_dout(7 DOWNTO 0))));
                state_table(5)  <= sbox_rev_c(TO_INTEGER(UNSIGNED(state_sram_dout(15 DOWNTO 8))));
                state_table(10) <= sbox_rev_c(TO_INTEGER(UNSIGNED(state_sram_dout(23 DOWNTO 16))));
                state_table(15) <= sbox_rev_c(TO_INTEGER(UNSIGNED(state_sram_dout(31 DOWNTO 24))));
            ELSIF calc_cntr = 3 THEN
                -- Perform second inverse substitution and inverse row shift
                state_table(4)  <= sbox_rev_c(TO_INTEGER(UNSIGNED(state_sram_dout(7 DOWNTO 0))));
                state_table(9)  <= sbox_rev_c(TO_INTEGER(UNSIGNED(state_sram_dout(15 DOWNTO 8))));
                state_table(14) <= sbox_rev_c(TO_INTEGER(UNSIGNED(state_sram_dout(23 DOWNTO 16))));
                state_table(3)  <= sbox_rev_c(TO_INTEGER(UNSIGNED(state_sram_dout(31 DOWNTO 24))));
            ELSIF calc_cntr = 4 THEN
                -- Perform third inverse substitution and inverse row shift
                state_table(8)  <= sbox_rev_c(TO_INTEGER(UNSIGNED(state_sram_dout(7 DOWNTO 0))));
                state_table(13) <= sbox_rev_c(TO_INTEGER(UNSIGNED(state_sram_dout(15 DOWNTO 8))));
                state_table(2)  <= sbox_rev_c(TO_INTEGER(UNSIGNED(state_sram_dout(23 DOWNTO 16))));
                state_table(7)  <= sbox_rev_c(TO_INTEGER(UNSIGNED(state_sram_dout(31 DOWNTO 24))));
            ELSIF calc_cntr = 5 THEN
                -- Perform fourth inverse substitution and inverse row shift
                state_table(12) <= sbox_rev_c(TO_INTEGER(UNSIGNED(state_sram_dout(7 DOWNTO 0))));
                state_table(1)  <= sbox_rev_c(TO_INTEGER(UNSIGNED(state_sram_dout(15 DOWNTO 8))));
                state_table(6)  <= sbox_rev_c(TO_INTEGER(UNSIGNED(state_sram_dout(23 DOWNTO 16))));
                state_table(11) <= sbox_rev_c(TO_INTEGER(UNSIGNED(state_sram_dout(31 DOWNTO 24))));
            END IF;

            IF last_round = '1' THEN
                IF calc_cntr = 6 THEN
                    -- Perform first XOR for last round
                    state_table(0)  <= key_word_in(7 DOWNTO 0)   XOR state_table(0);
                    state_table(1)  <= key_word_in(15 DOWNTO 8)  XOR state_table(1);
                    state_table(2)  <= key_word_in(23 DOWNTO 16) XOR state_table(2);
                    state_table(3)  <= key_word_in(31 DOWNTO 24) XOR state_table(3);
                ELSIF calc_cntr = 7 THEN
                    -- Perform second XOR for last round
                    state_table(4)  <= key_word_in(7 DOWNTO 0)   XOR state_table(4);
                    state_table(5)  <= key_word_in(15 DOWNTO 8)  XOR state_table(5);
                    state_table(6)  <= key_word_in(23 DOWNTO 16) XOR state_table(6);
                    state_table(7)  <= key_word_in(31 DOWNTO 24) XOR state_table(7);
                    -- Output first 32 bits of plaintext
                    data_ready      <= '1';
                    data_word_out   <= state_table(0) & state_table(1) & state_table(2) & state_table(3);
                ELSIF calc_cntr = 8 THEN
                    -- Perform third XOR for last round
                    state_table(8)  <= key_word_in(7 DOWNTO 0)   XOR state_table(8);
                    state_table(9)  <= key_word_in(15 DOWNTO 8)  XOR state_table(9);
                    state_table(10) <= key_word_in(23 DOWNTO 16) XOR state_table(10);
                    state_table(11) <= key_word_in(31 DOWNTO 24) XOR state_table(11);
                    -- Output second 32 bits of plaintext
                    data_ready      <= '1';
                    data_word_out   <= state_table(4) & state_table(5) & state_table(6) & state_table(7);
                ELSIF calc_cntr = 9 THEN
                    -- Perform final XOR for last round
                    state_table(12) <= key_word_in(7 DOWNTO 0)   XOR state_table(12);
                    state_table(13) <= key_word_in(15 DOWNTO 8)  XOR state_table(13);
                    state_table(14) <= key_word_in(23 DOWNTO 16) XOR state_table(14);
                    state_table(15) <= key_word_in(31 DOWNTO 24) XOR state_table(15);
                    -- Output third 32 bits of plaintext
                    data_ready      <= '1';
                    data_word_out   <= state_table(8) & state_table(9) & state_table(10) & state_table(11);
                ELSIF calc_cntr = 10 THEN
                    -- Output final 32 bits of plaintext
                    data_ready      <= '1';
                    data_word_out   <= state_table(12) & state_table(13) & state_table(14) & state_table(15);
                ELSE
                    -- Finished output
                    data_ready      <= '0';
                    data_word_out   <= (OTHERS => '0');
                END IF;
            ELSE
                data_ready <= '0';
            END IF;
        END IF;
    END PROCESS sub_row_shift_final_round;

END rtl;
