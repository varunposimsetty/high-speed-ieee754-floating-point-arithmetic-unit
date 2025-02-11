library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;
use IEEE.math_real.all;

entity tb is 
end entity tb;

architecture bhv of tb is
    signal clk : std_ulogic := '0';
    signal rst : std_ulogic := '0';
    signal num_1 : std_ulogic_vector(63 downto 0) := (others => '0');
    signal num_2 : std_ulogic_vector(63 downto 0) := (others => '0');
    signal result : std_ulogic_vector(63 downto 0) := (others => '0');

    begin 

    FU_ADDER : entity work.fp_mul(RTL) 
    port map(
        i_clk_100MHz => clk,
        i_nrst_async => rst,
        i_operand_1  => num_1,
        i_operand_2  => num_2,
        o_result     => result
    );

    proc_clock_gen : process is
        begin
            wait for 5 ns;
            clk <= not clk;
        end process proc_clock_gen;

    proc_tb : process is 
        begin 
            wait for 100 ns;
            rst <= '1';
            wait for 50 ns;
            num_1 <=  x"3FF0000000000000";
            wait for 10 ns;
            num_2 <= x"3FF0000000000000";
            wait for 10 ns;
            num_1 <= x"4000000000000000"; 
            wait for 10 ns;
            num_2 <= x"4000000000000000";
            wait for 10 ns;
            num_1 <= x"3FE0000000000000";
            wait for 10 ns;
            num_2 <= x"3FE0000000000000";
            wait for 10 ns;
            num_1 <= x"3FF8000000000000";
            wait for 10 ns;
            num_2 <= x"3FF8000000000000";
            wait for 10 ns;
            num_1 <= x"3FF4000000000000";
            wait for 10 ns;
            num_2 <= x"3FF4000000000000";
            wait for 10 ns;
            num_1 <= x"0000000000000000";
            wait for 10 ns;
            num_2 <=  x"40C81CDD6E9E0B6E";
            wait for 10 ns;
            num_1 <= x"BFF0000000000000";
            wait for 10 ns;
            num_2 <= x"3FF0000000000000";
            wait for 10 ns;
            num_1 <= x"400921FB54442D18";
            wait for 10 ns;
            num_2 <= x"4005BF0A8B145769";
            wait for 10 ns;
            num_1 <= x"7FE1CCF385EBC8A0";
            wait for 10 ns;
            num_2 <= x"3CB0000000000000";
            wait for 10 ns;
            num_1 <= x"5B19E96A19C0C3FA";
            wait for 10 ns;
            num_2 <=  x"5B19E96A19C0C3FA";
            wait for 10 ns;
            num_1 <= x"1A37E43C8800759C";
            wait for 10 ns;
            num_2 <= x"1A37E43C8800759C";
            wait for 10 ns;
            num_1 <= x"7FF0000000000000";
            wait for 10 ns;
            num_2 <= x"4000000000000000";
            wait for 10 ns;
            num_1 <= x"4000000000000000";
            wait for 10 ns;
            num_1 <= x"7FF0000000000000"; 
            wait for 10 ns;
            num_2 <= x"7FF8000000000000";
            wait for 10 ns;
            num_1 <= x"3FF0000000000000"; 
            wait for 10 ns;
            num_2 <= x"3FF0000000000000"; 
            wait for 10 ns;
            num_1 <= x"3FF0000000000000"; 
            wait for 10 ns;
            num_2 <= x"7FF8000000000000"; 
            wait for 10 ns; 
            num_1 <= x"C000000000000000"; 
            wait for 10 ns;
            num_2 <= x"0000000000000002"; 
            wait for 10 ns;
            num_1 <= x"C000000000000000"; 
            wait for 10 ns;
            num_2 <= x"3FFFFFFFFFFFFFFF"; 
            wait for 10 ns;
            num_1 <= x"3FFFFFFFFFFFFFFF"; 
            wait for 10 ns;
            num_2 <= x"3FB999999999999A"; 
            wait for 10 ns;
            num_1 <= x"3FC999999999999A"; 
            wait for 10 ns;
            num_2 <= x"09C4000000000000"; 
            wait for 10 ns; 
            num_1 <= x"7E37E43C8800759C"; 
            wait for 10 ns;
            num_2 <= x"7E37E43C8800759C"; 
            wait for 10 ns;
            num_1 <= x"c000000000000000"; 
            wait for 10 ns;
            num_2 <= x"3FFFFFFFFFFFFFFF"; 
            wait for 10 ns;
            num_1 <= x"3FFFFFFFFFFFFFFF"; 
            wait for 10 ns;
            num_2 <= x"3FB999999999999A"; 
            wait for 10 ns;
            num_1 <= x"3FC999999999999A"; 
            wait for 10 ns;
            num_2 <= x"09C4000000000000"; 
            wait for 10 ns;
            wait;
    end process proc_tb;
end architecture bhv;


