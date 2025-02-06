library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;
use IEEE.math_real.all;

entity fp_mul is 
    generic(
        EXP_WIDTH  : integer := 11; -- EXPONENT WIDTH (Float := 8 , Double := 11 )
        MANT_WIDTH : integer := 52; -- MANTISSA WIDTH (Float := 23, Double := 52 )
        BAIS       : integer := 1023 -- BIAS VALUE (Float := 127 , Double := 1023)
    );
    port(
        i_clk_100MHz : in std_ulogic;
        i_nrst_async : in std_ulogic;
        i_operand_1  : in std_ulogic_vector(1+EXP_WIDTH+MANT_WIDTH-1 downto 0);
        i_operand_2  : in std_ulogic_vector(1+EXP_WIDTH+MANT_WIDTH-1 downto 0);
        o_result     : out std_ulogic_vector(1+EXP_WIDTH+MANT_WIDTH-1 downto 0)
        );
end entity fp_mul;

architecture RTL of fp_mul is 
    -- GENERAL 
    constant zero : std_ulogic_vector(EXP_WIDTH-1 downto 0) := (others => '0');
    constant all_one  : std_ulogic_vector(MANT_WIDTH downto 0)  := (others => '1');   
    -- CAPTURE 
    signal sign_1      : std_ulogic := '0';
    signal sign_2      : std_ulogic := '0';
    signal exponent_1  : std_ulogic_vector(EXP_WIDTH-1 downto 0) := (others => '0');
    signal exponent_2  : std_ulogic_vector(EXP_WIDTH-1 downto 0) := (others => '0');
    signal mantissa_1  : std_ulogic_vector(MANT_WIDTH-1 downto 0) := (others => '0');
    signal mantissa_2  : std_ulogic_vector(MANT_WIDTH-1 downto 0) := (others => '0');
    -- DENORMALIZATION
    signal unnorm_exponent_integer : integer := 0;
    signal unnorm_exponent : std_ulogic_vector(EXP_WIDTH-1 downto 0) := (others => '0');
    signal implicit_1 : std_ulogic := '0';
    signal implicit_2 : std_ulogic := '0';
    signal significand_1 : std_ulogic_vector(MANT_WIDTH downto 0) := (others => '0');
    signal significand_2 : std_ulogic_vector(MANT_WIDTH downto 0) := (others => '0');
    signal output_sign : std_ulogic := '0';
    -- SIGNIFICAND MULTIPLICATION
    signal output_sign_stage : std_ulogic := '0';
    signal unnorm_exponent_stage : std_ulogic_vector(EXP_WIDTH-1 downto 0) := (others => '0');
    signal product : std_ulogic_vector(2*(MANT_WIDTH + 1) - 1 downto 0) := (others => '0'); -- 2 x (m+1) bits 
    -- NORMALIZATION 
    shared variable l : std_ulogic := '0';
    shared variable g : std_ulogic := '0';
    shared variable s : std_ulogic := '0';
    shared variable r : std_ulogic := '0';
    signal significand_product : std_ulogic_vector(MANT_WIDTH downto 0) := (others => '0');
    signal norm_exponent_temp : std_ulogic_vector(EXP_WIDTH-1 downto 0) := (others => '0');
    signal norm_exponent : std_ulogic_vector(EXP_WIDTH-1 downto 0) := (others => '0');
    signal temp_significand_product : std_ulogic_vector(MANT_WIDTH downto 0);
    signal norm_significand : std_ulogic_vector(MANT_WIDTH-1 downto 0) := (others => '0');
    signal k : integer := 0;
    signal result : std_ulogic_vector(1+EXP_WIDTH+MANT_WIDTH-1 downto 0) := (others => '0');



    begin 
        -- CAPTURE 
        proc_capture : process(i_clk_100MHz,i_nrst_async) is 
            begin 
                if(i_nrst_async = '0') then 
                    sign_1 <= '0';
                    sign_2 <= '0';
                    exponent_1 <= (others => '0');
                    exponent_2 <= (others => '0');
                    mantissa_1 <= (others => '0');
                    mantissa_2 <= (others => '0');
                elsif(rising_edge(i_clk_100MHz)) then  
                    sign_1     <= i_operand_1(i_operand_1'high);
                    sign_2     <= i_operand_2(i_operand_2'high);
                    exponent_1 <= i_operand_1(EXP_WIDTH+MANT_WIDTH-1 downto MANT_WIDTH);
                    exponent_2 <= i_operand_2(EXP_WIDTH+MANT_WIDTH-1 downto MANT_WIDTH);
                    mantissa_1 <= i_operand_1(MANT_WIDTH-1 downto 0);
                    mantissa_2 <= i_operand_2(MANT_WIDTH-1 downto 0);
                end if;
        end process proc_capture;

        -- DENORMALIZATION 
        proc_denorm : process(i_clk_100MHz,i_nrst_async) is 
            begin 
                if(i_nrst_async = '0') then 
                    unnorm_exponent <= (others => '0');
                    implicit_1 <= '0';
                    implicit_2 <= '0';
                elsif(rising_edge(i_clk_100MHz)) then 
                    unnorm_exponent_integer <= to_integer(unsigned(exponent_1)) + to_integer(unsigned(exponent_2)) - BAIS;
                    if (unnorm_exponent_integer <= 0) then 
                        unnorm_exponent <= (others => '0');
                    elsif (unnorm_exponent_integer > 2*BAIS) then
                        unnorm_exponent <= std_ulogic_vector(to_unsigned(2 * BAIS + 1, unnorm_exponent'length));
                    else
                        unnorm_exponent <= std_ulogic_vector(std_logic_vector(to_unsigned(unnorm_exponent_integer, unnorm_exponent'length)));
                    end if;
                    if (exponent_1 = zero) then 
                        implicit_1 <= '0';
                    else 
                        implicit_1 <= '1';
                    end if;
                    if (exponent_2 = zero) then 
                        implicit_2 <= '0';
                    else 
                        implicit_2 <= '1';
                    end if;
                    significand_1 <= implicit_1 & mantissa_1;
                    significand_2 <= implicit_2 & mantissa_2;
                    output_sign <= sign_1 xor sign_2;
                end if;
        end process proc_denorm;

        -- SIGNIFICAND MULTIPLICATION
        proc_sig_mul : process(i_clk_100MHz,i_nrst_async) is 
            begin 
                if(i_nrst_async = '0') then 
                    output_sign_stage <= '0';
                    unnorm_exponent_stage <= (others => '0');
                    product <= (others => '0');
                elsif(rising_edge(i_clk_100MHz)) then
                    output_sign_stage <= output_sign;
                    unnorm_exponent_stage <= unnorm_exponent;
                    product <= std_ulogic_vector(unsigned(significand_1) * unsigned(significand_2));
                end if;
        end process proc_sig_mul;
        
        -- NORMALIZATION
        proc_norm : process(i_clk_100MHz,i_nrst_async) is 
            begin 
                if(i_nrst_async = '0') then 
                    l := '0';
                    g := '0';
                    s := '0';
                    r := '0';
                    significand_product <= (others => '0');
                    norm_exponent_temp <= (others => '0');
                    norm_exponent <= (others => '0');
                    norm_significand <= (others => '0');
                    result <= (others => '0');
                elsif(rising_edge(i_clk_100MHz)) then
                    significand_product <= product(2*(MANT_WIDTH+1)-1 downto MANT_WIDTH + 1);
                    l := product((MANT_WIDTH + 2)); -- (m + 2)th bit 
                    g := product((MANT_WIDTH + 1)); -- (m + 1)th bit
                    s := '0';
                    s_loop : for i in 0 to MANT_WIDTH loop 
                        s := s or product(i);
                    end loop;
                    r := (g and (l or s));
                    if (r = '0') then 
                        k <= 0;
                    else 
                        k <= 1;
                    end if;
                    norm_exponent_temp <= unnorm_exponent_stage;
                    if ((significand_product = all_one) and (r = '1')) then 
                        norm_significand <= (others => '0');
                        norm_exponent <= std_ulogic_vector(to_unsigned(to_integer(unsigned(norm_exponent_temp)) + 1, norm_exponent'length));
                    else 
                        temp_significand_product <= std_ulogic_vector(to_unsigned(to_integer(unsigned(significand_product)) + k, significand_product'length));
                        norm_significand <= temp_significand_product(temp_significand_product'high - 1 downto 0);
                        norm_exponent <= norm_exponent_temp;
                    end if;
                    result <= output_sign_stage & norm_exponent & norm_significand;
                end if;
        end process proc_norm;
        o_result <= result;
end architecture RTL;