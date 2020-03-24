LIBRARY IEEE;
LIBRARY aes;

USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;
USE aes.aes_pkg.ALL;

ENTITY aes_enc IS
    GENERIC(
        -- Length of input key, 0, 1 or 2 for 128, 192 or 256 respectively
        key_length : IN INTEGER RANGE 0 TO 2 := 0
    );
    PORT(
        -- Clock and active low reset
        clk            : IN  STD_LOGIC;
        reset_n        : IN  STD_LOGIC;

        -- Data input, one 32-bit word at a time
        data_word_in   : IN  STD_LOGIC_VECTOR(31 DOWNTO 0);
        -- Flag to enable data input
        data_valid     : IN  STD_LOGIC;

        -- Subkey input from key expansion component
        key_word_in    : IN  STD_LOGIC_VECTOR(31 DOWNTO 0);

        -- Flag to request subkey output from key expansion block
        get_key        : OUT STD_LOGIC;
        -- Which subkey to retrieve (0-43 for 128, 0-51 for 192, 0-59 for 256)
        get_key_number : OUT STD_LOGIC_VECTOR(5 DOWNTO 0);

        -- Flag to indicate encryption completion
        data_ready     : OUT STD_LOGIC;
        -- Data output, one 32-bit word at a time
        data_word_out  : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
    );
END ENTITY aes_enc;

ARCHITECTURE rtl OF aes_enc IS

    -- Delay signals for control
    SIGNAL data_word_in_d  : STD_LOGIC_VECTOR(31 DOWNTO 0);
    SIGNAL data_word_in_d2 : STD_LOGIC_VECTOR(31 DOWNTO 0);
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

    -- Temporary vector for mix columns calculations
    SIGNAL col_temp : STD_LOGIC_VECTOR(15 DOWNTO 0);

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
            -- Reverse byte order to match key
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
                get_key_number_temp <= (OTHERS => '0');
            ELSE
                IF data_valid = '1' AND data_valid_d = '0' THEN
                    -- Reset to 0 on input of new data
                    get_key_number_temp <= (OTHERS => '0');
                ELSIF get_key_int = '1' THEN
                    -- Increment whilst key is being requested
                    get_key_number_temp <= get_key_number_temp + 1;
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

    -- State RAM read address sequencing
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

    -- Intermediate calculation values
    col_temp(0)  <= state_table(0)(7)  XOR state_table(1)(7);
    col_temp(1)  <= state_table(1)(7)  XOR state_table(2)(7);
    col_temp(2)  <= state_table(2)(7)  XOR state_table(3)(7);
    col_temp(3)  <= state_table(3)(7)  XOR state_table(0)(7);
    col_temp(4)  <= state_table(4)(7)  XOR state_table(5)(7);
    col_temp(5)  <= state_table(5)(7)  XOR state_table(6)(7);
    col_temp(6)  <= state_table(6)(7)  XOR state_table(7)(7);
    col_temp(7)  <= state_table(7)(7)  XOR state_table(4)(7);
    col_temp(8)  <= state_table(8)(7)  XOR state_table(9)(7);
    col_temp(9)  <= state_table(9)(7)  XOR state_table(10)(7);
    col_temp(10) <= state_table(10)(7) XOR state_table(11)(7);
    col_temp(11) <= state_table(11)(7) XOR state_table(8)(7);
    col_temp(12) <= state_table(12)(7) XOR state_table(13)(7);
    col_temp(13) <= state_table(13)(7) XOR state_table(14)(7);
    col_temp(14) <= state_table(14)(7) XOR state_table(15)(7);
    col_temp(15) <= state_table(15)(7) XOR state_table(12)(7);

    -- Perform column mixing and round key XORing
    col_mix_rkey_xor : PROCESS(clk)
    BEGIN
        IF RISING_EDGE(clk) THEN
            IF reset_n = '0' THEN
                state_sram_din <= (OTHERS => '0');
            ELSE
                IF data_valid_d2 = '1' THEN
                    -- Perform XOR of initial round key with delayed original input data
                    state_sram_din <= data_word_in_d2 XOR key_word_in;
                ELSIF last_round = '0' THEN
                    -- Perform column mixing in all rounds except last
                    IF calc_cntr = 6 THEN
                        -- Perform column mixing and round key XORing for first column
                        state_sram_din(7 DOWNTO 0)   <= key_word_in(7 DOWNTO 0) XOR (state_table(0)(6 DOWNTO 0) & "0") XOR ((state_table(1)(6 DOWNTO 0) & "0") XOR state_table(1))
                                                        XOR state_table(2) XOR state_table(3) XOR ("000" & col_temp(0) & col_temp(0) & "0" & col_temp(0) & col_temp(0));
                        state_sram_din(15 DOWNTO 8)  <= key_word_in(15 DOWNTO 8) XOR state_table(0) XOR (state_table(1)(6 DOWNTO 0) & "0") XOR ((state_table(2)(6 DOWNTO 0) & "0")
                                                        XOR state_table(2)) XOR state_table(3) XOR ("000" & col_temp(1) & col_temp(1) & "0" & col_temp(1) & col_temp(1));
                        state_sram_din(23 DOWNTO 16) <= key_word_in(23 DOWNTO 16) XOR state_table(0) XOR state_table(1) XOR (state_table(2)(6 DOWNTO 0) & "0") XOR ((state_table(3)(6 DOWNTO 0) & "0")
                                                        XOR state_table(3)) XOR ("000" & col_temp(2) & col_temp(2) & "0" & col_temp(2) & col_temp(2));
                        state_sram_din(31 DOWNTO 24) <= key_word_in(31 DOWNTO 24) XOR ((state_table(0)(6 DOWNTO 0) & "0") XOR state_table(0)) XOR state_table(1) XOR state_table(2)
                                                        XOR (state_table(3)(6 DOWNTO 0) & "0") XOR ("000" & col_temp(3) & col_temp(3) & "0" & col_temp(3) & col_temp(3));
                    ELSIF calc_cntr = 7 THEN
                        -- Perform column mixing and round key XORing for the second column
                        state_sram_din(7 DOWNTO 0)   <= key_word_in(7 DOWNTO 0) XOR (state_table(4)(6 DOWNTO 0) & "0") XOR ((state_table(5)(6 DOWNTO 0) & "0") XOR state_table(5))
                                                        XOR state_table(6) XOR state_table(7) XOR ("000" & col_temp(4) & col_temp(4) & "0" & col_temp(4) & col_temp(4));
                        state_sram_din(15 DOWNTO 8)  <= key_word_in(15 DOWNTO 8) XOR state_table(4) XOR (state_table(5)(6 DOWNTO 0) & "0") XOR ((state_table(6)(6 DOWNTO 0) & "0")
                                                        XOR state_table(6)) XOR state_table(7) XOR ("000" & col_temp(5) & col_temp(5) & "0" & col_temp(5) & col_temp(5));
                        state_sram_din(23 DOWNTO 16) <= key_word_in(23 DOWNTO 16) XOR state_table(4) XOR state_table(5) XOR (state_table(6)(6 DOWNTO 0) & "0") XOR ((state_table(7)(6 DOWNTO 0) & "0")
                                                        XOR state_table(7)) XOR ("000" & col_temp(6) & col_temp(6) & "0" & col_temp(6) & col_temp(6));
                        state_sram_din(31 DOWNTO 24) <= key_word_in(31 DOWNTO 24) XOR ((state_table(4)(6 DOWNTO 0) & "0") XOR state_table(4)) XOR state_table(5) XOR state_table(6)
                                                        XOR (state_table(7)(6 DOWNTO 0) & "0") XOR ("000" & col_temp(7) & col_temp(7) & "0" & col_temp(7) & col_temp(7));
                    ELSIF calc_cntr = 8 THEN
                        -- Perform column mixing and round key XORING for the third column
                        state_sram_din(7 DOWNTO 0)   <= key_word_in(7 DOWNTO 0) XOR (state_table(8)(6 DOWNTO 0) & "0") XOR ((state_table(9)(6 DOWNTO 0) & "0") XOR state_table(9))
                                                        XOR state_table(10) XOR state_table(11) XOR ("000" & col_temp(8) & col_temp(8) & "0" & col_temp(8) & col_temp(8));
                        state_sram_din(15 DOWNTO 8)  <= key_word_in(15 DOWNTO 8) XOR state_table(8) XOR (state_table(9)(6 DOWNTO 0) & "0") XOR ((state_table(10)(6 DOWNTO 0) & "0")
                                                        XOR state_table(10)) XOR state_table(11) XOR ("000" & col_temp(9) & col_temp(9) & "0" & col_temp(9) & col_temp(9));
                        state_sram_din(23 DOWNTO 16) <= key_word_in(23 DOWNTO 16) XOR state_table(8) XOR state_table(9) XOR (state_table(10)(6 DOWNTO 0) & "0") XOR ((state_table(11)(6 DOWNTO 0) & "0")
                                                        XOR state_table(11)) XOR ("000" & col_temp(10) & col_temp(10) & "0" & col_temp(10) & col_temp(10));
                        state_sram_din(31 DOWNTO 24) <= key_word_in(31 DOWNTO 24) XOR ((state_table(8)(6 DOWNTO 0) & "0") XOR state_table(8)) XOR state_table(9) XOR state_table(10)
                                                        XOR (state_table(11)(6 DOWNTO 0) & "0") XOR ("000" & col_temp(11) & col_temp(11) & "0" & col_temp(11) & col_temp(11));
                    ELSIF calc_cntr = 9 THEN
                        -- Perform column mixing and round key XORING for the fourth column
                        state_sram_din(7 DOWNTO 0)   <= key_word_in(7 DOWNTO 0) XOR (state_table(12)(6 DOWNTO 0) & "0") XOR ((state_table(13)(6 DOWNTO 0) & "0") XOR state_table(13))
                                                        XOR state_table(14) XOR state_table(15) XOR ("000" & col_temp(12) & col_temp(12) & "0" & col_temp(12) & col_temp(12));
                        state_sram_din(15 DOWNTO 8)  <= key_word_in(15 DOWNTO 8) XOR state_table(12) XOR (state_table(13)(6 DOWNTO 0) & "0") XOR ((state_table(14)(6 DOWNTO 0) & "0")
                                                        XOR state_table(14)) XOR state_table(15) XOR ("000" & col_temp(13) & col_temp(13) & "0" & col_temp(13) & col_temp(13));
                        state_sram_din(23 DOWNTO 16) <= key_word_in(23 DOWNTO 16) XOR state_table(12) XOR state_table(13) XOR (state_table(14)(6 DOWNTO 0) & "0") XOR ((state_table(15)(6 DOWNTO 0) & "0")
                                                        XOR state_table(15)) XOR ("000" & col_temp(14) & col_temp(14) & "0" & col_temp(14) & col_temp(14));
                        state_sram_din(31 DOWNTO 24) <= key_word_in(31 DOWNTO 24) XOR ((state_table(12)(6 DOWNTO 0) & "0") XOR state_table(12)) XOR state_table(13) XOR state_table(14)
                                                        XOR (state_table(15)(6 DOWNTO 0) & "0") XOR ("000" & col_temp(15) & col_temp(15) & "0" & col_temp(15) & col_temp(15));
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
                        -- All rounds except last end after cycle 9 (end of mix columns step)
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

    -- Substitute, shift rows, final round XOR and data output
    sub_row_shift_final_round : PROCESS(clk)
    BEGIN
        IF RISING_EDGE(clk) THEN
            IF calc_cntr = 2 THEN
                -- Perform first substitution and row shift
                state_table(0)  <= sbox_c(TO_INTEGER(UNSIGNED(state_sram_dout(7 DOWNTO 0))));
                state_table(13) <= sbox_c(TO_INTEGER(UNSIGNED(state_sram_dout(15 DOWNTO 8))));
                state_table(10) <= sbox_c(TO_INTEGER(UNSIGNED(state_sram_dout(23 DOWNTO 16))));
                state_table(7)  <= sbox_c(TO_INTEGER(UNSIGNED(state_sram_dout(31 DOWNTO 24))));
            ELSIF calc_cntr = 3 THEN
                -- Perform second substitution and row shift
                state_table(4)  <= sbox_c(TO_INTEGER(UNSIGNED(state_sram_dout(7 DOWNTO 0))));
                state_table(1)  <= sbox_c(TO_INTEGER(UNSIGNED(state_sram_dout(15 DOWNTO 8))));
                state_table(14) <= sbox_c(TO_INTEGER(UNSIGNED(state_sram_dout(23 DOWNTO 16))));
                state_table(11) <= sbox_c(TO_INTEGER(UNSIGNED(state_sram_dout(31 DOWNTO 24))));
            ELSIF calc_cntr = 4 THEN
                -- Perform third substitution and row shift
                state_table(8)  <= sbox_c(TO_INTEGER(UNSIGNED(state_sram_dout(7 DOWNTO 0))));
                state_table(5)  <= sbox_c(TO_INTEGER(UNSIGNED(state_sram_dout(15 DOWNTO 8))));
                state_table(2)  <= sbox_c(TO_INTEGER(UNSIGNED(state_sram_dout(23 DOWNTO 16))));
                state_table(15) <= sbox_c(TO_INTEGER(UNSIGNED(state_sram_dout(31 DOWNTO 24))));
            ELSIF calc_cntr = 5 THEN
                -- Perform fourth substitution and row shift
                state_table(12) <= sbox_c(TO_INTEGER(UNSIGNED(state_sram_dout(7 DOWNTO 0))));
                state_table(9)  <= sbox_c(TO_INTEGER(UNSIGNED(state_sram_dout(15 DOWNTO 8))));
                state_table(6)  <= sbox_c(TO_INTEGER(UNSIGNED(state_sram_dout(23 DOWNTO 16))));
                state_table(3)  <= sbox_c(TO_INTEGER(UNSIGNED(state_sram_dout(31 DOWNTO 24))));
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
                    -- Output first 32 bits of ciphertext
                    data_ready      <= '1';
                    data_word_out   <= state_table(0) & state_table(1) & state_table(2) & state_table(3);
                ELSIF calc_cntr = 8 THEN
                    -- Perform third XOR for last round
                    state_table(8)  <= key_word_in(7 DOWNTO 0)   XOR state_table(8);
                    state_table(9)  <= key_word_in(15 DOWNTO 8)  XOR state_table(9);
                    state_table(10) <= key_word_in(23 DOWNTO 16) XOR state_table(10);
                    state_table(11) <= key_word_in(31 DOWNTO 24) XOR state_table(11);
                    -- Output second 32 bits of ciphertext
                    data_ready      <= '1';
                    data_word_out   <= state_table(4) & state_table(5) & state_table(6) & state_table(7);
                ELSIF calc_cntr = 9 THEN
                    -- Perform final XOR for last round
                    state_table(12) <= key_word_in(7 DOWNTO 0)   XOR state_table(12);
                    state_table(13) <= key_word_in(15 DOWNTO 8)  XOR state_table(13);
                    state_table(14) <= key_word_in(23 DOWNTO 16) XOR state_table(14);
                    state_table(15) <= key_word_in(31 DOWNTO 24) XOR state_table(15);
                    -- Output third 32 bits of ciphertext
                    data_ready      <= '1';
                    data_word_out   <= state_table(8) & state_table(9) & state_table(10) & state_table(11);
                ELSIF calc_cntr = 10 THEN
                    -- Output third 32 bits of ciphertext
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
