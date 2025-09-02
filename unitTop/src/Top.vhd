library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity unit_FPU is 
    generic(
        EXP_WIDTH  : integer := 11;
        MANT_WIDTH : integer := 52;
        BIAS       : integer := 1023;
        ADD_LATENCY : integer := 5; -- The Adder is a 5 staged Pipline
        MUL_LATENCY : integer := 4  -- The Multiplier is a 4 staged Piplie 
    );
    port(
        i_clk_100MHz : in  std_ulogic;
        i_nrst_async : in  std_ulogic;
        i_add_enable : in  std_ulogic;
        i_mul_enable : in  std_ulogic;
        i_operand_1  : in  std_ulogic_vector(1+EXP_WIDTH+MANT_WIDTH-1 downto 0);
        i_operand_2  : in  std_ulogic_vector(1+EXP_WIDTH+MANT_WIDTH-1 downto 0);
        o_sum        : out std_ulogic_vector(1+EXP_WIDTH+MANT_WIDTH-1 downto 0);
        o_product    : out std_ulogic_vector(1+EXP_WIDTH+MANT_WIDTH-1 downto 0)
    );
end entity unit_FPU; 

architecture RTL of unit_FPU is 
    constant WORD_WIDTH     : integer := 1 + EXP_WIDTH + MANT_WIDTH;
    signal add_a, add_b, mul_1, mul_2, sum, product : std_ulogic_vector(1+EXP_WIDTH+MANT_WIDTH-1 downto 0) := (others => '0');
    
    begin
    
    DUT_FPU_ADDER : entity work.fp_adder(RTL) 
        generic map(
            EXP_WIDTH  => EXP_WIDTH,
            MANT_WIDTH => MANT_WIDTH
        )
        port map(
            i_clk_100MHz => i_clk_100MHz,
            i_nrst_async => i_nrst_async,
            i_operand_a  => add_a,
            i_operand_b  => add_b,
            o_result     => sum
        );

    DUT_FPU_MULTIPLIER : entity work.fp_mul(RTL)
        generic map(
                EXP_WIDTH  => EXP_WIDTH,
                MANT_WIDTH => MANT_WIDTH,
                BIAS => BIAS
            ) 
        port map(
            i_clk_100MHz => i_clk_100MHz,
            i_nrst_async => i_nrst_async,
            i_operand_1  => mul_1,
            i_operand_2  => mul_2,
            o_result     => product
        );
    
    proc_top : process(i_clk_100MHz,i_nrst_async) 
        begin 
            if(i_nrst_async = '0') then 
                add_a <= (others=>'0'); 
                add_b <= (others=>'0');
                mul_1 <= (others=>'0'); 
                mul_2 <= (others=>'0');
            elsif(rising_edge(i_clk_100MHz)) then 
                if (i_add_enable ='1') then 
                    add_a <= i_operand_1; 
                    add_b <= i_operand_2; 
                    o_sum <= sum;
                end if;
                if (i_mul_enable='1') then 
                    mul_1 <= i_operand_1; 
                    mul_2 <= i_operand_2; 
                    o_product <= product;
                end if;
            end if;
    end process proc_top;
end architecture RTL;


