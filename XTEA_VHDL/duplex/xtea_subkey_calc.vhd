--########################################################################################
--## Developer: Jack Sampford (j.w.sampford-15@student.lboro.ac.uk)                     ##
--##                                                                                    ##
--## Design name: xtea                                                                  ##
--## Module name: xtea_subkey_calc - RTL                                                ##
--## Target devices: ARM MPS2+ FPGA Prototyping Board                                   ##
--## Tool versions: Quartus Prime 19.1, ModelSim Intel FPGA Starter Edition 10.5b       ##
--##                                                                                    ##
--## Description: XTEA subkey calculation component. Creates subkeys from initial input ##
--## key. Key is input 32 bits at a time on key_word_in whilst setting key_valid high,  ##
--## calculation completion is marked by calc_done going high.                          ##
--##                                                                                    ##
--## Dependencies: none                                                                 ##
--########################################################################################

-- Library declarations
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

-- Entity declaration
ENTITY xtea_subkey_calc IS
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
        -- Which subkey to retrieve (0-63)
        get_key_number_a : IN  STD_LOGIC_VECTOR(5 DOWNTO 0);
        -- Flag to request expanded key output on port B
        get_key_b        : IN  STD_LOGIC;
        -- Which subkey to retrieve (0-63)
        get_key_number_b : IN  STD_LOGIC_VECTOR(5 DOWNTO 0);

        -- Flag to indicate completion
        calc_done        : OUT STD_LOGIC;
        -- Key output port A, one 32-bit word at a time
        key_word_out_a   : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
        -- Key output port B, one 32-bit word at a time
        key_word_out_b   : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
    );
END ENTITY xtea_subkey_calc;

-- Architecture definition
ARCHITECTURE rtl OF xtea_subkey_calc IS

    -- Set number of rounds minus one, standard is 32 rounds
    CONSTANT max_round : INTEGER := 31;

    -- Value to modify internal sum by, fixed as per XTEA standard
    CONSTANT delta     : UNSIGNED := UNSIGNED'(x"9E3779B9");

    -- Delay signals to allow sequencing of calculation
    SIGNAL key_valid_d : STD_LOGIC;
    SIGNAL calc_flag_d : STD_LOGIC;
    SIGNAL get_key_a_d : STD_LOGIC;
    SIGNAL get_key_b_d : STD_LOGIC;

    -- Key array
    TYPE key_arr IS ARRAY(0 TO 3) OF UNSIGNED(31 DOWNTO 0);
    SIGNAL key_block   : key_arr;
    -- Key input counter
    SIGNAL key_cntr    : INTEGER RANGE 0 TO 3;

    -- SRAM array to hold subkeys
    TYPE subkey_arr_t IS ARRAY(0 TO 63) OF STD_LOGIC_VECTOR(31 DOWNTO 0);
    SIGNAL subkey_arr  : subkey_arr_t;

    -- SRAM read/write signals
    SIGNAL key_sram_wren   : STD_LOGIC;
    SIGNAL key_sram_waddr  : UNSIGNED(5 DOWNTO 0);
    SIGNAL key_sram_dout_a : STD_LOGIC_VECTOR(31 DOWNTO 0);
    SIGNAL key_sram_dout_b : STD_LOGIC_VECTOR(31 DOWNTO 0);

    -- Calculation and round counters
    SIGNAL calc_flag   : STD_LOGIC;
    SIGNAL calc_cntr   : STD_LOGIC;
    SIGNAL round_cntr  : INTEGER RANGE 0 TO max_round+1;

    -- Subkey calculation signals
    SIGNAL subkey      : UNSIGNED(31 DOWNTO 0);
    SIGNAL sum         : UNSIGNED(31 DOWNTO 0);

BEGIN

    -- Delay input to allow correct sequencing of calculation
    input_delay : PROCESS(clk)
    BEGIN
        IF RISING_EDGE(clk) THEN
            IF reset_n = '0' THEN
                key_valid_d <= '0';
                calc_flag_d <= '0';
                get_key_a_d <= '0';
                get_key_b_d <= '0';
            ELSE
                key_valid_d <= key_valid;
                calc_flag_d <= calc_flag;
                get_key_a_d <= get_key_a;
                get_key_b_d <= get_key_b;
            END IF;
        END IF;
    END PROCESS input_delay;

    -- Load key into 128-bit block
    key_read : PROCESS(clk)
    BEGIN
        IF RISING_EDGE(clk) THEN
            IF reset_n = '0' THEN
                key_block <= (OTHERS => (OTHERS => '0'));
                key_cntr  <= 0;
            ELSE
                IF key_valid = '1' THEN
                    IF key_cntr = 0 THEN
                        key_block(3) <= UNSIGNED(key_word_in);
                        key_cntr     <= key_cntr + 1;
                    ELSIF key_cntr = 1 THEN
                        key_block(2) <= UNSIGNED(key_word_in);
                        key_cntr     <= key_cntr + 1;
                    ELSIF key_cntr = 2 THEN
                        key_block(1) <= UNSIGNED(key_word_in);
                        key_cntr     <= key_cntr + 1;
                    ELSIF key_cntr = 3 THEN
                        key_block(0) <= UNSIGNED(key_word_in);
                        key_cntr     <= 0;
                    END IF;
                END IF;
            END IF;
        END IF;
    END PROCESS key_read;

    -- Manage the write enable of the subkey storage SRAM
    sram_wren_manage : PROCESS(clk)
    BEGIN
        IF RISING_EDGE(clk) THEN
            IF reset_n = '0' THEN
                -- Disable writing on reset
                key_sram_wren <= '0';
            ELSE
                IF calc_flag = '1' THEN
                    -- Start writing subkeys when calculation begins
                    key_sram_wren <= '1';
                ELSE
                    -- Stop writing after final subkey written
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
                -- Set address to 0 on reset
                key_sram_waddr <= (OTHERS => '0');
            ELSE
                IF (calc_flag_d = '0' AND calc_flag = '1') THEN
                    -- Reset to zero when calculation begins
                    key_sram_waddr <= (OTHERS => '0');
                ELSIF key_sram_wren = '1' THEN
                    -- Increment each cycle whilst writing
                    key_sram_waddr <= key_sram_waddr + 1;
                END IF;
            END IF;
        END IF;
    END PROCESS sram_waddr_manage;

    -- SRAM read/write control
    sram_ctrl : PROCESS(clk)
    BEGIN
        IF RISING_EDGE(clk) THEN
            IF reset_n = '0' THEN
                subkey_arr      <= (OTHERS => (OTHERS => '0'));
                key_sram_dout_a <= (OTHERS => '0');
                key_sram_dout_b <= (OTHERS => '0');
            ELSE
                IF key_sram_wren = '1' THEN
                    -- Write subkey to correct address
                    subkey_arr(TO_INTEGER(key_sram_waddr)) <= STD_LOGIC_VECTOR(subkey);
                END IF;
                -- Ready data from requested address
                key_sram_dout_a <= subkey_arr(TO_INTEGER(UNSIGNED(get_key_number_a)));
                key_sram_dout_b <= subkey_arr(TO_INTEGER(UNSIGNED(get_key_number_b)));
            END IF;
        END IF;
    END PROCESS sram_ctrl;

    -- Write out subkeys when requested
    key_word_out_a <= key_sram_dout_a WHEN (get_key_a_d = '1') ELSE (OTHERS => '0');
    key_word_out_b <= key_sram_dout_b WHEN (get_key_b_d = '1') ELSE (OTHERS => '0');

    -- Calculation flag management
    calc_flag_set : PROCESS(clk)
    BEGIN
        IF RISING_EDGE(clk) THEN
            IF reset_n = '0' THEN
                calc_flag <= '0';
                calc_done <= '0';
            ELSE
                IF key_valid_d = '1' AND key_valid = '0' THEN
                    -- Begin calculation once key loaded
                    calc_flag <= '1';
                    calc_done <= '0';
                ELSIF calc_cntr = '1' AND round_cntr = max_round THEN
                    -- Deactivate after last round complete
                    calc_flag <= '0';
                    calc_done <= '1';
                END IF;
            END IF;
        END IF;
    END PROCESS calc_flag_set;

    -- Calculation counter management
    calc_cntr_manage : PROCESS(clk)
    BEGIN
        IF RISING_EDGE(clk) THEN
            IF reset_n = '0' THEN
                calc_cntr  <= '0';
                round_cntr <= 0;
            ELSE
                IF calc_flag = '1' THEN
                    IF calc_cntr = '1' THEN
                        -- Reset calculation counter and increment round counter
                        calc_cntr  <= '0';
                        round_cntr <= round_cntr + 1;
                    ELSE
                        calc_cntr  <= '1';
                    END IF;
                ELSE
                    calc_cntr  <= '0';
                    round_cntr <= 0;
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
                IF key_valid_d = '1' AND key_valid = '0' THEN
                    -- Reset when new key is being input
                    sum <= (OTHERS => '0');
                ELSIF calc_cntr = '0' AND calc_flag = '1' THEN
                    -- Perform first subkey calculation
                    subkey <= sum + key_block(TO_INTEGER(sum AND x"00000003"));
                    -- Update internal sum variable
                    sum    <= sum + delta;
                ELSIF calc_cntr = '1' THEN
                    -- Perform second subkey calculation
                    subkey <= sum + key_block(TO_INTEGER(("00000000000" & sum(31 DOWNTO 11)) AND x"00000003"));
                END IF;
            END IF;
        END IF;
    END PROCESS subkey_calc;

END rtl;
