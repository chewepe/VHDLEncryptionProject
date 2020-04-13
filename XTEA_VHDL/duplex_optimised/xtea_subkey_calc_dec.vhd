--########################################################################################
--## Developer: Jack Sampford (j.w.sampford-15@student.lboro.ac.uk)                     ##
--##                                                                                    ##
--## Design name: xtea                                                                  ##
--## Module name: xtea_subkey_calc_dec - RTL                                            ##
--## Target devices: ARM MPS2+ FPGA Prototyping Board                                   ##
--## Tool versions: Quartus Prime 19.1, ModelSim Intel FPGA Starter Edition 10.5b       ##
--##                                                                                    ##
--## Description: XTEA subkey calculation component. Creates subkeys from initial input ##
--## key. Key is input 32 bits at a time on key_word_in whilst setting key_valid high,  ##
--## subkeys are fed to decryption block along with enable flag and state control.      ##
--##                                                                                    ##
--## Dependencies: none                                                                 ##
--########################################################################################

-- Library declarations
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

-- Entity declaration
ENTITY xtea_subkey_calc_dec IS
    PORT(
        -- Clock and active low reset
        clk          : IN  STD_LOGIC;
        reset_n      : IN  STD_LOGIC;

        -- Key input, one 32-bit word at a time
        key_word_in  : IN  STD_LOGIC_VECTOR(31 DOWNTO 0);
        -- Flag to enable key input
        key_valid    : IN  STD_LOGIC;

        -- Subkey output, one 32-bit word at a time
        key_word_out : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
    );
END ENTITY xtea_subkey_calc_dec;

-- Architecture definition
ARCHITECTURE rtl OF xtea_subkey_calc_dec IS

    -- Set number of rounds minus one, standard is 32 rounds
    CONSTANT max_round : INTEGER := 31;

    -- Value to modify internal sum by, fixed as per XTEA standard
    CONSTANT delta     : UNSIGNED := UNSIGNED'(x"9E3779B9");

    -- Key array
    TYPE key_arr_t IS ARRAY(0 TO 3) OF UNSIGNED(31 DOWNTO 0);
    SIGNAL key_block   : key_arr_t;
    -- Key input counter
    SIGNAL key_cntr    : INTEGER RANGE 0 TO 3;

    -- Calculation and round counters
    SIGNAL calc_flag   : STD_LOGIC;
    -- Calculation counter (state) is STD_LOGIC since it only needs to flip between 0 and 1
    SIGNAL calc_state  : STD_LOGIC;
    SIGNAL round_cntr  : INTEGER RANGE 0 TO max_round+1;

    -- Subkey calculation signal
    SIGNAL sum         : UNSIGNED(31 DOWNTO 0);

BEGIN

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

    -- Calculation flag management
    calc_flag_set : PROCESS(clk)
    BEGIN
        IF RISING_EDGE(clk) THEN
            IF reset_n = '0' THEN
                calc_flag <= '0';
            ELSE
                IF key_valid = '1' AND key_cntr = 3 THEN
                    -- Begin calculation once key loaded
                    -- Trigger off of key_cntr to save 1 clock cycle
                    calc_flag <= '1';
                ELSIF calc_state = '1' AND round_cntr = max_round THEN
                    -- Deactivate after last round complete
                    calc_flag <= '0';
                END IF;
            END IF;
        END IF;
    END PROCESS calc_flag_set;

    -- Calculation state management
    calc_state_manage : PROCESS(clk)
    BEGIN
        IF RISING_EDGE(clk) THEN
            IF reset_n = '0' THEN
                calc_state <= '0';
                round_cntr <= 0;
            ELSE
                IF calc_flag = '1' THEN
                    IF calc_state = '1' THEN
                        -- Increment round counter
                        round_cntr <= round_cntr + 1;
                    END IF;
                    -- Flip to next state
                    calc_state <= NOT(calc_state);
                ELSE
                    calc_state <= '0';
                    round_cntr <= 0;
                END IF;
            END IF;
        END IF;
    END PROCESS calc_state_manage;

    -- Calculate subkeys required for round operations
    subkey_calc : PROCESS(clk)
    BEGIN
        IF RISING_EDGE(clk) THEN
            IF reset_n = '0' THEN
                key_word_out <= (OTHERS => '0');
                -- Set to correct initial value for 32-round decryption
                sum          <= x"C6EF3720";
            ELSE
                IF key_valid = '1' AND key_cntr = 3 THEN
                    -- Reset when new key is being input
                    -- Same key_cntr optimisation previously described
                    sum          <= x"C6EF3720";
                ELSIF calc_state = '0' AND calc_flag = '1' THEN
                    -- Perform first subkey calculation
                    key_word_out <= STD_LOGIC_VECTOR(sum + key_block(TO_INTEGER(("00000000000" & sum(31 DOWNTO 11)) AND x"00000003")));
                    -- Update internal sum variable
                    sum          <= sum - delta;
                ELSIF calc_state = '1' THEN
                    -- Perform second subkey calculation
                    key_word_out <= STD_LOGIC_VECTOR(sum + key_block(TO_INTEGER(sum AND x"00000003")));
                END IF;
            END IF;
        END IF;
    END PROCESS subkey_calc;

END rtl;
