LIBRARY IEEE;
LIBRARY aes;

USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;
USE aes.aes_pkg.ALL;

ENTITY key_expansion IS
    GENERIC(
        -- Length of input key, 0, 1 or 2 for 128, 192 or 256 respectively
        key_length  : IN INTEGER RANGE 0 TO 2 := 0
    );
    PORT(
        -- Clock and active low reset
        clk              : IN  STD_LOGIC;
        reset_n          : IN  STD_LOGIC;

        -- Key input, one 32-bit word at a time
        key_word_in      : IN  STD_LOGIC_VECTOR(31 DOWNTO 0);
        -- Flag to enable key input
        key_valid        : IN  STD_LOGIC;
        
        -- Flag to request expanded key output on port A
        get_key_a        : IN  STD_LOGIC;
        -- Which subkey to retrieve (0-43 for 128, 0-51 for 192, 0-59 for 256) for port A output
        get_key_number_a : IN  STD_LOGIC_VECTOR(5 DOWNTO 0);
        -- Flag to request expanded key output on port B
        get_key_b        : IN  STD_LOGIC;
        -- Which subkey to retrieve for port B output
        get_key_number_b : IN  STD_LOGIC_VECTOR(5 DOWNTO 0);
        
        -- Flag to indicate completion
        expansion_done   : OUT STD_LOGIC;
        -- Key output port A, one 32-bit word at a time
        key_word_out_a   : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
        -- Key output port B, one 32-bit word at a time
        key_word_out_b   : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
    );
END ENTITY key_expansion;

ARCHITECTURE rtl OF key_expansion IS

    -- SRAM array to hold expanded keys
    SIGNAL expan_key_arr : rkey_table_t;

    -- SBOX constant table, address and substituted byte
    --SIGNAL sbox_table : sbox_t;
    SIGNAL sbox_addr  : UNSIGNED(7 DOWNTO 0);
    SIGNAL sub_byte   : STD_LOGIC_VECTOR(7 DOWNTO 0);

    -- Round number tracker
    SIGNAL current_round : INTEGER RANGE 0 TO 13;

    -- Delayed key input and output flags
    SIGNAL key_valid_d   : STD_LOGIC;
    SIGNAL key_word_in_d : STD_LOGIC_VECTOR(31 DOWNTO 0);
    SIGNAL get_key_a_d   : STD_LOGIC;
    SIGNAL get_key_b_d   : STD_LOGIC;

    -- Calculation flags
    SIGNAL calc_flag       : STD_LOGIC;
    SIGNAL start_calc_flag : STD_LOGIC;

    -- Calculation and round counter
    SIGNAL calc_cntr       : INTEGER;
    SIGNAL round_cntr      : INTEGER;

    -- SRAM read/write signals
    SIGNAL key_sram_wren        : STD_LOGIC;
    SIGNAL key_sram_waddr       : UNSIGNED(5 DOWNTO 0);
    SIGNAL key_sram_raddr_a     : UNSIGNED(5 DOWNTO 0);
    SIGNAL key_sram_raddr_b     : UNSIGNED(5 DOWNTO 0);
    SIGNAL key_sram_din         : STD_LOGIC_VECTOR(31 DOWNTO 0);
    SIGNAL key_sram_dout_a      : STD_LOGIC_VECTOR(31 DOWNTO 0);
    SIGNAL key_sram_dout_b      : STD_LOGIC_VECTOR(31 DOWNTO 0);
    -- Switch between internal and external read addresses for expanded key output
    SIGNAL key_sram_raddr_int   : UNSIGNED(5 DOWNTO 0);
    SIGNAL key_sram_raddr_ext_a : UNSIGNED(5 DOWNTO 0);
    SIGNAL key_sram_raddr_ext_b : UNSIGNED(5 DOWNTO 0);

    -- Intermediate signal vector
    SIGNAL temp_vector : STD_LOGIC_VECTOR(31 DOWNTO 0);

BEGIN

    -- Delay key input enable signal to use for rising/falling edge detection
    input_delay : PROCESS(clk)
    BEGIN
        IF RISING_EDGE(clk) THEN
            IF reset_n = '0' THEN
                key_valid_d   <= '0';
                key_word_in_d <= (OTHERS => '0');
                get_key_a_d   <= '0';
                get_key_b_d   <= '0';
            ELSE
                key_valid_d   <= key_valid;
                IF key_valid = '1' THEN
                    key_word_in_d <= key_word_in(7 DOWNTO 0) & key_word_in(15 DOWNTO 8) & key_word_in(23 DOWNTO 16) & key_word_in(31 DOWNTO 24);
                END IF;
                get_key_a_d   <= get_key_a;
                get_key_b_d   <= get_key_b;
            END IF;
        END IF;
    END PROCESS input_delay;

    -- Manage the write enable of the expanded key storage SRAM
    sram_wren_manage : PROCESS(clk)
    BEGIN
        IF RISING_EDGE(clk) THEN
            IF reset_n = '0' THEN
                -- Disable writing on reset
                key_sram_wren <= '0';
            ELSE
                IF key_valid = '1' THEN
                    -- Write incoming key to first slot in key storage
                    key_sram_wren <= '1';
                ELSIF (calc_cntr >= 8 AND calc_cntr <= 11) THEN
                    -- Write subkeys for 128
                    key_sram_wren <= '1';
                ELSIF (key_length = 1 AND calc_cntr >= 12 AND calc_cntr <= 13) THEN
                    -- Write extra subkeys for 192
                    key_sram_wren <= '1';
                ELSIF (key_length = 2 AND calc_cntr >= 17 AND calc_cntr <= 20) THEN
                    -- Write extra subkeys for 256
                    key_sram_wren <= '1';
                ELSE
                    -- No write if conditions not met
                    key_sram_wren <= '0';
                END IF;
            END IF;
        END IF;
    END PROCESS sram_wren_manage;

    -- Set correct write address
    sram_waddr_manage : PROCESS(clk)
    BEGIN
        IF RISING_EDGE(clk) THEN
            IF reset_n = '0' THEN
                key_sram_waddr <= (OTHERS => '0');
            ELSE
                IF (key_valid = '1' AND key_valid_d = '0') THEN
                    -- Reset when new key is being input
                    key_sram_waddr <= (OTHERS => '0');
                ELSIF key_sram_wren = '1' THEN
                    -- Increment address every cycle whilst writing
                    key_sram_waddr <= key_sram_waddr + 1;
                END IF;
            END IF;
        END IF;
    END PROCESS sram_waddr_manage;

    -- Set correct internal read address
    sram_raddr_manage : PROCESS(clk)
    BEGIN
        IF RISING_EDGE(clk) THEN
            IF reset_n = '0' THEN
                key_sram_raddr_int <= (OTHERS => '0');
            ELSE
                IF (key_valid = '1' AND key_valid_d = '0') THEN
                    -- Reset when new key is being input
                    key_sram_raddr_int <= (OTHERS => '0');
                ELSIF (calc_cntr >= 7 AND calc_cntr <= 10) THEN
                    -- Increment address to output correct subkeys for 128 calculations
                    key_sram_raddr_int <= key_sram_raddr_int + 1;
                ELSIF (key_length = 1 AND calc_cntr >= 11 AND calc_cntr <= 12) THEN
                    -- Increment address to output correct subkeys for 192 calculations
                    key_sram_raddr_int <= key_sram_raddr_int + 1;
                ELSIF (key_length = 2 AND calc_cntr >= 16 AND calc_cntr <= 19) THEN
                    -- Increment address to output correct subkeys for 256 calculations
                    key_sram_raddr_int <= key_sram_raddr_int + 1;
                END IF;
            END IF;
        END IF;
    END PROCESS sram_raddr_manage;

    -- Switch to external SRAM address when key output is requested
    key_sram_raddr_ext_a <= UNSIGNED(get_key_number_a);
    key_sram_raddr_ext_b <= UNSIGNED(get_key_number_b);
    key_sram_raddr_a     <= key_sram_raddr_int WHEN (get_key_a = '0') ELSE key_sram_raddr_ext_a;
    key_sram_raddr_b     <= key_sram_raddr_int WHEN (get_key_b = '0') ELSE key_sram_raddr_ext_b;

    -- Switch between external input and calculated value to write to SRAM
    key_sram_din <= key_word_in_d WHEN (key_valid_d = '1') ELSE
                    temp_vector WHEN (calc_cntr >= 9 AND calc_cntr <= 12) ELSE
                    temp_vector WHEN (key_length = 1 AND calc_cntr >= 13 AND calc_cntr <= 14) ELSE
                    temp_vector WHEN (key_length = 2 AND calc_cntr >= 18 AND calc_cntr <= 21) ELSE
                    (OTHERS => '0');


    -- SRAM read/write process
    sram_ctrl : PROCESS(clk)
    BEGIN
        IF RISING_EDGE(clk) THEN
            IF reset_n = '0' THEN
                expan_key_arr   <= (OTHERS => (OTHERS => '0'));
                key_sram_dout_a <= (OTHERS => '0');
                key_sram_dout_b <= (OTHERS => '0');
            ELSE
                IF key_sram_wren = '1' THEN
                    -- Write SRAM input to correct address
                    expan_key_arr(TO_INTEGER(key_sram_waddr)) <= key_sram_din;
                END IF;
                -- Read data from correct address
                key_sram_dout_a <= expan_key_arr(TO_INTEGER(key_sram_raddr_a));
                key_sram_dout_b <= expan_key_arr(TO_INTEGER(key_sram_raddr_b));
            END IF;
        END IF;
    END PROCESS sram_ctrl;

    -- Write out SRAM data output when requested
    key_word_out_a <= key_sram_dout_a WHEN (get_key_a_d = '1') ELSE (OTHERS => '0');
    key_word_out_b <= key_sram_dout_b WHEN (get_key_b_d = '1') ELSE (OTHERS => '0');

    -- Set SBOX variable to constant table
    --sbox_table <= sbox_c;

    -- Asynchronously set index byte for SBOX substitutions
    sbox_addr <= UNSIGNED(temp_vector(7 DOWNTO 0))   WHEN (calc_cntr = 2 OR (calc_cntr = 12 AND key_length = 2)) else
                 UNSIGNED(temp_vector(15 DOWNTO 8))  WHEN (calc_cntr = 3 OR (calc_cntr = 13 AND key_length = 2)) else
                 UNSIGNED(temp_vector(23 DOWNTO 16)) WHEN (calc_cntr = 4 OR (calc_cntr = 14 AND key_length = 2)) else
                 UNSIGNED(temp_vector(31 DOWNTO 24)) WHEN (calc_cntr = 5 OR (calc_cntr = 15 AND key_length = 2)) else
                 (OTHERS => '0');

    -- Substitute value from SBOX
    sbox_sub : PROCESS(clk)
    BEGIN
        IF RISING_EDGE(clk) THEN
            IF reset_n = '0' THEN
                sub_byte <= (OTHERS => '0');
            ELSE
                sub_byte <= sbox_c(TO_INTEGER(sbox_addr));
            END IF;
        END IF;
    END PROCESS sbox_sub;

    -- Trigger and stop calculation at correct times
    calc_flag_sequence : PROCESS(clk)
    BEGIN
        IF RISING_EDGE(clk) THEN
            IF reset_n = '0' THEN
                calc_flag       <= '0';
                start_calc_flag <= '0';
                expansion_done  <= '0';
            ELSE
                -- Detect falling edge of key valid signal
                IF key_valid = '0' AND key_valid_d = '1' THEN
                    -- Start calculations
                    start_calc_flag <= '1';
                    calc_flag       <= '1';
                    expansion_done  <= '0';
                ELSIF key_length = 0 AND round_cntr = 10 THEN
                    -- Stop calculation after correct number of rounds for AES-128
                    calc_flag      <= '0';
                    expansion_done <= '1';
                ELSIF key_length = 1 AND round_cntr = 8 THEN
                    -- Stop calculation after correct number of rounds for AES-192
                    calc_flag      <= '0';
                    expansion_done <= '1';
                ELSIF key_length = 2 AND round_cntr = 7 THEN
                    -- Stop calculation after correct number of rounds for AES-256
                    calc_flag      <= '0';
                    expansion_done <= '1';
                ELSE
                    -- Unset start flag after one clock cycle
                    start_calc_flag <= '0';
                END IF;
            END IF;
        END IF;
    END PROCESS calc_flag_sequence;

    -- Manage calculation and round counters
    calc_round_counters : PROCESS(clk)
    BEGIN
        IF RISING_EDGE(clk) THEN
            IF reset_n = '0' THEN
                -- Reset counters
                calc_cntr  <= 0;
                round_cntr <= 0;
            ELSE
                IF start_calc_flag = '1' THEN
                    -- Reset counters at beginning of calculation
                    calc_cntr  <= 0;
                    round_cntr <= 0;
                ELSIF key_length = 0 AND calc_cntr = 12 THEN
                    -- Increment round counter for AES-128
                    calc_cntr  <= 0;
                    round_cntr <= round_cntr + 1;
                ELSIF key_length = 1 AND calc_cntr = 14 THEN
                    -- Increment round counter for AES-192
                    calc_cntr  <= 0;
                    round_cntr <= round_cntr + 1;
                ELSIF key_length = 2 AND calc_cntr = 21 THEN
                    -- Increment round counter for AES-256
                    calc_cntr  <= 0;
                    round_cntr <= round_cntr + 1;
                ELSIF calc_flag = '1' THEN
                    -- Increment calculation counter every cycle
                    calc_cntr <= calc_cntr + 1;
                ELSE
                    -- Reset counter if calc flag unset
                    calc_cntr <= 0;
                END IF;
            END IF;
        END IF;
    END PROCESS calc_round_counters;

    -- Set temp_vector to correct value for various calculation stages
    temp_vector_set : PROCESS(clk)
    BEGIN
        IF RISING_EDGE(clk) THEN
            IF reset_n = '0' THEN
                temp_vector <= (OTHERS => '0');
            ELSE
                IF start_calc_flag = '1' THEN
                    -- Use key directly at beginning of calculation
                    temp_vector <= key_word_in_d;
                -- Values for all AES sizes
                -- Sub bytes steps
                ELSIF calc_cntr = 3 THEN
                    temp_vector(7 DOWNTO 0) <= sub_byte;
                ELSIF calc_cntr = 4 THEN
                    temp_vector(15 DOWNTO 8) <= sub_byte;
                ELSIF calc_cntr = 5 THEN
                    temp_vector(23 DOWNTO 16) <= sub_byte;
                ELSIF calc_cntr = 6 THEN
                    temp_vector(31 DOWNTO 24) <= sub_byte;
                -- Rotate and introduce round constant
                ELSIF calc_cntr = 7 THEN
                    temp_vector <= ((temp_vector(7 DOWNTO 0) & temp_vector(31 DOWNTO 8)) XOR (x"000000" & rcon_c(round_cntr)));
                -- XOR with previous term
                ELSIF calc_cntr >= 8 AND calc_cntr <= 11 THEN
                    temp_vector <= temp_vector XOR key_sram_dout_a;
                
                -- Values for AES-192
                ELSIF key_length = 1 THEN
                    IF calc_cntr >= 12 AND calc_cntr <= 13 THEN
                        temp_vector <= temp_vector XOR key_sram_dout_a;
                    END IF;

                -- Values for AES-256
                ELSIF key_length = 2 THEN
                    -- Sub bytes steps
                    IF calc_cntr = 13 THEN
                        temp_vector(7 DOWNTO 0) <= sub_byte;
                    ELSIF calc_cntr = 14 THEN
                        temp_vector(15 DOWNTO 8) <= sub_byte;
                    ELSIF calc_cntr = 15 THEN
                        temp_vector(23 DOWNTO 16) <= sub_byte;
                    ELSIF calc_cntr = 16 THEN
                        temp_vector(31 DOWNTO 24) <= sub_byte;
                    -- XOR with previous term
                    ELSIF calc_cntr >= 17 AND calc_cntr <= 20 THEN
                        temp_vector <= temp_vector XOR key_sram_dout_a;
                    END IF;
                END IF;
            END IF;
        END IF;
    END PROCESS temp_vector_set;

END rtl;
























