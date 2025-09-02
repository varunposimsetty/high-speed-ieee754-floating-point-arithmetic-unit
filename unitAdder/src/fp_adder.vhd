library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity fp_adder is 
    generic(
        EXP_WIDTH  : integer := 11; -- EXPONENT WIDTH (Float := 8 , Double := 11 )
        MANT_WIDTH : integer := 52  -- MANTISSA WIDTH (Float := 23, Double := 52 )
    );
    port(
        i_clk_100MHz : in  std_ulogic;
        i_nrst_async : in  std_ulogic;
        i_operand_a  : in  std_ulogic_vector(1+EXP_WIDTH+MANT_WIDTH-1 downto 0);
        i_operand_b  : in  std_ulogic_vector(1+EXP_WIDTH+MANT_WIDTH-1 downto 0);
        o_result     : out std_ulogic_vector(1+EXP_WIDTH+MANT_WIDTH-1 downto 0)
    );
end entity fp_adder;

architecture RTL of fp_adder is
    function or_reduce(v: std_ulogic_vector) return std_ulogic is
        variable acc: std_ulogic := '0';
    begin
        for i in v'range loop acc := acc or v(i); end loop;
        return acc;
    end;
    function lzc(v: std_ulogic_vector) return integer is
        variable c : integer := 0;
    begin
        for i in v'high downto v'low loop
            if v(i)='0' then c := c + 1; else exit; end if;
        end loop;
        return c;
    end;

    function get_sign(x: std_ulogic_vector) 
        return std_ulogic is begin return x(x'high); 
    end function get_sign;

    function get_exp(x: std_ulogic_vector; EXPW,MANTW: integer) return std_ulogic_vector is
        begin return x(EXPW+MANTW-1 downto MANTW); 
    end function get_exp;

    function get_man(x: std_ulogic_vector; MANTW: integer) return std_ulogic_vector is
        begin return x(MANTW-1 downto 0); 
    end function get_man;

    constant WORD_WIDTH    : integer := 1 + EXP_WIDTH + MANT_WIDTH;
    constant SIG_EXT_WIDTH : integer := 1 + MANT_WIDTH + 3;
    constant ZERO_WORD     : std_ulogic_vector(WORD_WIDTH-1 downto 0) := (others=>'0');
    constant EXP_ALL_ZERO  : std_ulogic_vector(EXP_WIDTH-1 downto 0) := (others=>'0');
    constant EXP_ALL_ONES  : std_ulogic_vector(EXP_WIDTH-1 downto 0) := (others=>'1');
    constant MANT_ZERO     : std_ulogic_vector(MANT_WIDTH-1 downto 0) := (others=>'0');

    -- stage 1 signals 
    signal s1_sign_a, s1_sign_b : std_ulogic := '0';
    signal s1_exp_a,  s1_exp_b  : std_ulogic_vector(EXP_WIDTH-1 downto 0) := (others=>'0');
    signal s1_man_a,  s1_man_b  : std_ulogic_vector(MANT_WIDTH-1 downto 0) := (others=>'0');
    signal s1_is_zero_a, s1_is_zero_b : std_ulogic := '0';
    signal s1_is_sub_a, s1_is_sub_b : std_ulogic := '0';
    signal s1_is_inf_a, s1_is_inf_b : std_ulogic := '0';
    signal s1_is_nan_a, s1_is_nan_b : std_ulogic := '0';

    -- stage 2 signals 
    signal s2_larger, s2_smaller : std_ulogic_vector(WORD_WIDTH-1 downto 0) := (others=>'0');
    signal s2_exp_diff : std_ulogic_vector(EXP_WIDTH-1 downto 0) := (others=>'0');
    signal s2_operation : std_ulogic := '0';  -- '0' = add, '1' = sub
    signal s2_result_sign : std_ulogic := '0';  -- sign of the larger 
    signal s2_result_exp : std_ulogic_vector(EXP_WIDTH-1 downto 0) := (others=>'0');
    signal s2_bypass : std_ulogic := '0';  -- 1 => NaN/Inf cases
    signal s2_bypass_word : std_ulogic_vector(WORD_WIDTH-1 downto 0) := (others=>'0');

    -- stage 3 signals
    signal s3_large_sig, s3_small_sig : std_ulogic_vector(SIG_EXT_WIDTH-1 downto 0) := (others=>'0');
    signal s3_operation               : std_ulogic := '0';
    signal s3_result_sign             : std_ulogic := '0';
    signal s3_result_exp              : std_ulogic_vector(EXP_WIDTH-1 downto 0) := (others=>'0');

    -- stage 4 signals 
    signal s4_sum                     : std_ulogic_vector(SIG_EXT_WIDTH-1 downto 0) := (others=>'0');
    signal s4_carry : std_ulogic := '0';
    signal s4_result_sign : std_ulogic := '0';
    signal s4_result_exp : std_ulogic_vector(EXP_WIDTH-1 downto 0) := (others=>'0');
    signal s4_both_zero : std_ulogic := '0';
    signal s4_operation : std_ulogic := '0';

    -- stage 5 signals 
    signal s5_result : std_ulogic_vector(WORD_WIDTH-1 downto 0) := (others=>'0');
    signal s4_exact_zero : std_ulogic := '0';
begin
    -- Stage 1 : Fetch stage : fetch the sign,exponent and mantissa from the two operands
    s1_proc: process(i_clk_100MHz, i_nrst_async)
        variable man_a_v, man_b_v : std_ulogic_vector(MANT_WIDTH-1 downto 0);
        variable exp_a_v, exp_b_v : std_ulogic_vector(EXP_WIDTH-1 downto 0);
        variable z_a, z_b         : std_ulogic;
        variable sub_a, sub_b     : std_ulogic;
        variable inf_a, inf_b     : std_ulogic;
        variable nan_a, nan_b     : std_ulogic;
    begin
        if i_nrst_async = '0' then
            s1_sign_a <= '0'; s1_sign_b <= '0';
            s1_exp_a  <= (others=>'0'); s1_exp_b <= (others=>'0');
            s1_man_a  <= (others=>'0'); s1_man_b <= (others=>'0');
            s1_is_zero_a <= '0'; s1_is_zero_b <= '0';
            s1_is_sub_a  <= '0'; s1_is_sub_b  <= '0';
            s1_is_inf_a  <= '0'; s1_is_inf_b  <= '0';
            s1_is_nan_a  <= '0'; s1_is_nan_b  <= '0';
        elsif rising_edge(i_clk_100MHz) then
            s1_sign_a <= get_sign(i_operand_a);
            s1_sign_b <= get_sign(i_operand_b);
            exp_a_v   := get_exp(i_operand_a, EXP_WIDTH, MANT_WIDTH);
            exp_b_v   := get_exp(i_operand_b, EXP_WIDTH, MANT_WIDTH);
            man_a_v   := get_man(i_operand_a, MANT_WIDTH);
            man_b_v   := get_man(i_operand_b, MANT_WIDTH);
            s1_exp_a  <= exp_a_v; s1_exp_b <= exp_b_v;
            s1_man_a  <= man_a_v; s1_man_b <= man_b_v;
            -- zero: exp=0 and mant=0
            if ((exp_a_v = EXP_ALL_ZERO) and (or_reduce(man_a_v)='0')) then 
                z_a:='1'; 
            else 
                z_a:='0'; 
            end if;
            if ((exp_b_v = EXP_ALL_ZERO) and (or_reduce(man_b_v)='0')) then 
                z_b:='1'; 
            else 
                z_b:='0'; 
            end if;
            -- subnormal: exp=0 and mant!=0
            if ((exp_a_v = EXP_ALL_ZERO) and (or_reduce(man_a_v)='1')) then 
                sub_a:='1'; 
            else 
                sub_a:='0'; 
            end if;
            if (exp_b_v = EXP_ALL_ZERO) and (or_reduce(man_b_v)='1') then 
                sub_b:='1'; 
            else 
                sub_b:='0'; 
            end if;
            -- infinity: exp=all1 and mant=0
            if ((exp_a_v = EXP_ALL_ONES) and (or_reduce(man_a_v)='0')) then 
                inf_a:='1'; 
            else 
                inf_a:='0'; 
            end if;
            if ((exp_b_v = EXP_ALL_ONES) and (or_reduce(man_b_v)='0')) then 
                inf_b:='1'; 
            else 
                inf_b:='0'; 
            end if;
            -- NaN: exp=all1 and mant!=0
            if ((exp_a_v = EXP_ALL_ONES) and (or_reduce(man_a_v)='1')) then 
                nan_a:='1'; 
            else 
                nan_a:='0'; 
            end if;
            if ((exp_b_v = EXP_ALL_ONES) and (or_reduce(man_b_v)='1')) then 
                nan_b:='1'; 
            else 
                nan_b:='0'; 
            end if;
            -- Register flags
            s1_is_zero_a <= z_a;  s1_is_zero_b <= z_b;
            s1_is_sub_a  <= sub_a; s1_is_sub_b <= sub_b;
            s1_is_inf_a  <= inf_a; s1_is_inf_b <= inf_b;
            s1_is_nan_a  <= nan_a; s1_is_nan_b <= nan_b;
        end if;
    end process;

    -- Stage 2 : Preparation stage : Identify the Large number, Small number and the Exponent Difference (Shift Amount).
    s2_proc: process(i_clk_100MHz, i_nrst_async)
        variable a_gt_b       : boolean;
        variable exp_a_u      : unsigned(EXP_WIDTH-1 downto 0);
        variable exp_b_u      : unsigned(EXP_WIDTH-1 downto 0);
        variable man_a_u      : unsigned(MANT_WIDTH-1 downto 0);
        variable man_b_u      : unsigned(MANT_WIDTH-1 downto 0);
        variable res_word_v   : std_ulogic_vector(WORD_WIDTH-1 downto 0);
        constant QNAN_MSB    : std_ulogic := '1';  
    begin
        if i_nrst_async='0' then
            s2_larger      <= (others=>'0');
            s2_smaller     <= (others=>'0');
            s2_exp_diff    <= (others=>'0');
            s2_operation   <= '0';
            s2_result_sign <= '0';
            s2_result_exp  <= (others=>'0');
            s2_bypass      <= '0';
            s2_bypass_word <= (others=>'0');
        elsif rising_edge(i_clk_100MHz) then
            -- NaN case
            if (s1_is_nan_a='1') or (s1_is_nan_b='1') then
                s2_bypass      <= '1';
                -- Return a qNaN: sign=0, exp=all1, mant with msb=1 (quiet)
                res_word_v     := '0' & EXP_ALL_ONES & (QNAN_MSB & (MANT_ZERO(MANT_WIDTH-2 downto 0)));
                s2_bypass_word <= res_word_v;
            -- Infinity case
            elsif (s1_is_inf_a='1') and (s1_is_inf_b='1') then
                if s1_sign_a /= s1_sign_b then
                    s2_bypass      <= '1';
                    res_word_v     := '0' & EXP_ALL_ONES & (QNAN_MSB & (MANT_ZERO(MANT_WIDTH-2 downto 0)));
                    s2_bypass_word <= res_word_v;
                else
                    s2_bypass      <= '1';
                    s2_bypass_word <= s1_sign_a & EXP_ALL_ONES & MANT_ZERO;
                end if;
            elsif (s1_is_inf_a='1') then
                s2_bypass      <= '1';
                s2_bypass_word <= s1_sign_a & EXP_ALL_ONES & MANT_ZERO;

            elsif (s1_is_inf_b='1') then
                s2_bypass      <= '1';
                s2_bypass_word <= s1_sign_b & EXP_ALL_ONES & MANT_ZERO;
            -- Regular case
            else
                s2_bypass <= '0';
                exp_a_u := unsigned(s1_exp_a);  exp_b_u := unsigned(s1_exp_b);
                man_a_u := unsigned(s1_man_a);  man_b_u := unsigned(s1_man_b);
                if exp_a_u > exp_b_u then
                    a_gt_b := true;
                elsif exp_a_u < exp_b_u then
                    a_gt_b := false;
                else
                    if man_a_u > man_b_u then
                        a_gt_b := true;
                    elsif man_a_u < man_b_u then
                        a_gt_b := false;
                    else
                        a_gt_b := true;
                    end if;
                end if;

                if a_gt_b then
                    s2_larger <= s1_sign_a & s1_exp_a & s1_man_a;
                    s2_smaller <= s1_sign_b & s1_exp_b & s1_man_b;
                    s2_exp_diff <= std_ulogic_vector(exp_a_u - exp_b_u);
                    s2_result_sign <= s1_sign_a; 
                    s2_result_exp  <= s1_exp_a;  
                    
                    if s1_sign_a = s1_sign_b then 
                        s2_operation <= '0'; 
                    else
                        s2_operation <= '1'; 
                    end if;
                else
                    s2_larger <= s1_sign_b & s1_exp_b & s1_man_b;
                    s2_smaller <= s1_sign_a & s1_exp_a & s1_man_a;
                    s2_exp_diff <= std_ulogic_vector(exp_b_u - exp_a_u);
                    s2_result_sign <= s1_sign_b;
                    s2_result_exp  <= s1_exp_b;
                    if s1_sign_a = s1_sign_b then s2_operation <= '0'; else s2_operation <= '1'; end if;
                end if;
            end if;
        end if;
    end process;


    -- Stage 3 : Denormalizer stage
    s3_proc: process(i_clk_100MHz, i_nrst_async)
        variable large_sig_v, small_sig_v : std_ulogic_vector(SIG_EXT_WIDTH-1 downto 0);
        variable shift_amt : integer;
        variable sticky_v : std_ulogic;
        variable exp_larger, exp_smaller  : std_ulogic_vector(EXP_WIDTH-1 downto 0);
        variable sign_larger, sign_smaller: std_ulogic;
        variable man_larger, man_smaller  : std_ulogic_vector(MANT_WIDTH-1 downto 0);
        variable hidden_larger, hidden_smaller : std_ulogic;
        variable max_shift : integer;
    begin
        if i_nrst_async='0' then
            s3_large_sig   <= (others=>'0');
            s3_small_sig   <= (others=>'0');
            s3_operation   <= '0';
            s3_result_sign <= '0';
            s3_result_exp  <= (others=>'0');
        elsif rising_edge(i_clk_100MHz) then
            exp_larger   := get_exp(s2_larger,EXP_WIDTH,MANT_WIDTH);
            exp_smaller  := get_exp(s2_smaller,EXP_WIDTH,MANT_WIDTH);
            sign_larger  := get_sign(s2_larger);
            sign_smaller := get_sign(s2_smaller);
            man_larger   := get_man(s2_larger,MANT_WIDTH);
            man_smaller  := get_man(s2_smaller,MANT_WIDTH);
            hidden_larger  := '0'; if exp_larger  /= EXP_ALL_ZERO then hidden_larger  := '1'; end if;
            hidden_smaller := '0'; if exp_smaller /= EXP_ALL_ZERO then hidden_smaller := '1'; end if;
            large_sig_v := hidden_larger  & man_larger  & "000";
            small_sig_v := hidden_smaller & man_smaller & "000";
            max_shift := to_integer(unsigned(EXP_ALL_ONES));
            -- Right-shift the small significand by the exponent difference
            shift_amt := to_integer(unsigned(s2_exp_diff));
            sticky_v  := '0';
            if (shift_amt = 0) then
                null;
            elsif (shift_amt >= SIG_EXT_WIDTH) then
                sticky_v    := or_reduce(small_sig_v);
                small_sig_v := (others=>'0');
            else
                for i in 0 to (SIG_EXT_WIDTH-1) loop
                    if(i < shift_amt) then 
                         sticky_v := sticky_v or small_sig_v(i);
                     end if;
                end loop;
                small_sig_v := std_ulogic_vector(shift_right(unsigned(small_sig_v), shift_amt));
            end if;
            -- Merge sticky into S 
            small_sig_v(0) := small_sig_v(0) or sticky_v;
            -- Register outputs for the next stage
            s3_large_sig   <= large_sig_v;
            s3_small_sig   <= small_sig_v;
            s3_operation   <= s2_operation;    
            s3_result_sign <= s2_result_sign;   
            s3_result_exp  <= s2_result_exp; 
        end if;
    end process;


    -- Stage 4: Significand addition / subtraction
    s4_proc: process(i_clk_100MHz, i_nrst_async)
        variable a, b : std_ulogic_vector(SIG_EXT_WIDTH-1 downto 0);
        variable sum_ext_v : std_ulogic_vector(SIG_EXT_WIDTH downto 0);
        variable zero_v : std_ulogic;
    begin
        if i_nrst_async='0' then
            s4_sum <= (others=>'0');
            s4_carry <= '0';
            s4_result_sign <= '0';
            s4_result_exp <= (others=>'0');
            s4_both_zero <= '0';
            s4_operation <= '0';
            s4_exact_zero <= '0';
        elsif rising_edge(i_clk_100MHz) then
            a := s3_large_sig;
            b := s3_small_sig;
            if s3_operation = '0' then
                sum_ext_v := std_ulogic_vector(unsigned('0' & a) + unsigned('0' & b));
            else
                sum_ext_v := std_ulogic_vector(unsigned('0' & a) - unsigned('0' & b));
            end if;
            s4_sum <= sum_ext_v(sum_ext_v'high-1 downto 0);
            s4_carry <= sum_ext_v(sum_ext_v'high);
            s4_result_sign <= s3_result_sign; 
            s4_result_exp <= s3_result_exp;  
            s4_operation <= s3_operation;
            if or_reduce(sum_ext_v(sum_ext_v'high-1 downto 0))='0' then
                zero_v := '1';
            else
                zero_v := '0';
            end if;
            s4_both_zero  <= zero_v;
            s4_exact_zero <= zero_v;
        end if;
    end process;

    -- Stage 5: Normalizer + Rounding (Round-to-Nearest, ties-to-even)
    s5_proc: process(i_clk_100MHz, i_nrst_async)
        variable tmp        : std_ulogic_vector(SIG_EXT_WIDTH-1 downto 0);
        variable exp_t      : std_ulogic_vector(EXP_WIDTH-1 downto 0);
        variable exp_u      : unsigned(EXP_WIDTH-1 downto 0);
        variable G, R, S, LSB, round_up : std_ulogic;
        variable widen      : unsigned(SIG_EXT_WIDTH downto 0);
        variable mant       : std_ulogic_vector(MANT_WIDTH-1 downto 0);
        variable sign_o     : std_ulogic;
        variable outw       : std_ulogic_vector(WORD_WIDTH-1 downto 0);
        variable lz         : integer;
        variable norm_to_E1 : integer;
        variable leftover   : integer;     -- <-- renamed from 'rem' (reserved keyword)
        variable sticky2    : std_ulogic;
        variable exp_int    : integer;
    begin
        if i_nrst_async='0' then
            s5_result <= (others=>'0');
        elsif rising_edge(i_clk_100MHz) then
            -- Early decisions
            if s2_bypass='1' then
                s5_result <= s2_bypass_word;            -- NaN/Inf decided in Stage 2
            elsif s4_exact_zero='1' or s4_both_zero='1' then
                s5_result <= ZERO_WORD;                 -- canonical +0
            else
                -- Inputs from Stage 4
                tmp    := s4_sum;
                exp_t  := s4_result_exp;
                sign_o := s4_result_sign;

                -- Carry-out => shift right once and bump exponent
                if s4_carry='1' then
                    tmp   := std_ulogic_vector(shift_right(unsigned(tmp), 1));
                    exp_t := std_ulogic_vector(unsigned(exp_t) + 1);
                end if;

                -- Left normalization if MSB not set
                if tmp(tmp'high)='0' then
                    lz := lzc(tmp);
                    if lz > 0 then
                        exp_u   := unsigned(exp_t);
                        exp_int := to_integer(exp_u);

                        if exp_int > lz then
                            -- Still a normal result after left shift
                            if lz >= SIG_EXT_WIDTH then
                                tmp   := (others=>'0');
                                exp_t := (others=>'0');
                            else
                                tmp   := std_ulogic_vector(shift_left(unsigned(tmp), lz));
                                exp_t := std_ulogic_vector(exp_u - lz);
                            end if;
                        else
                            if exp_int > 1 then
                                norm_to_E1 := exp_int - 1;
                            else
                                norm_to_E1 := 0;
                            end if;

                            if norm_to_E1 > 0 then
                                tmp := std_ulogic_vector(shift_left(unsigned(tmp), norm_to_E1));
                            end if;

                            leftover := lz - norm_to_E1; 
                            if leftover >= SIG_EXT_WIDTH then
                                sticky2 := or_reduce(tmp);
                                tmp     := (others=>'0');
                            else
                                sticky2 := '0';
                                if leftover > 0 then
                                    for idx in 0 to SIG_EXT_WIDTH-1 loop
                                        if(idx < leftover) then
                                            sticky2 := sticky2 or tmp(idx);
                                         end if;
                                    end loop;
                                    tmp := std_ulogic_vector(shift_right(unsigned(tmp), leftover));
                                end if;
                            end if;
                            tmp(0) := tmp(0) or sticky2;
                            exp_t  := (others=>'0');         
                        end if;
                    end if;
                end if;
                S   := tmp(0); R := tmp(1); G := tmp(2); LSB := tmp(3);
                if (G='1') and (R='1' or S='1' or LSB='1') then
                    round_up := '1';
                else
                    round_up := '0';
                end if;
                widen := (others=>'0');
                widen(widen'high-1 downto 0) := unsigned(tmp);
                if round_up='1' then
                    widen := widen + shift_left(to_unsigned(1, widen'length), 3);
                end if;
                if widen(widen'high)='1' then
                    widen := shift_right(widen, 1);
                    exp_t := std_ulogic_vector(unsigned(exp_t) + 1);
                end if;
                tmp  := std_ulogic_vector(widen(widen'high-1 downto 0));
                mant := tmp(tmp'high-1 downto 3);

                if unsigned(exp_t) = 0 then
                    if or_reduce(mant)='0' then
                        outw := ZERO_WORD; 
                    else
                        outw := sign_o & EXP_ALL_ZERO & mant;
                    end if;
                elsif exp_t = EXP_ALL_ONES then
                    outw := sign_o & EXP_ALL_ONES & MANT_ZERO;
                else
                    outw := sign_o & exp_t & mant;
                end if;

                s5_result <= outw;
            end if;
        end if;
    end process;

    o_result <= s5_result;
end architecture RTL;
