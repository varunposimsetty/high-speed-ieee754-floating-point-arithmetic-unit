library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity fp_mul is 
    generic(
        EXP_WIDTH  : integer := 11;
        MANT_WIDTH : integer := 52;
        BIAS       : integer := 1023
    );
    port(
        i_clk_100MHz : in  std_ulogic;
        i_nrst_async : in  std_ulogic;
        i_operand_1  : in  std_ulogic_vector(1+EXP_WIDTH+MANT_WIDTH-1 downto 0);
        i_operand_2  : in  std_ulogic_vector(1+EXP_WIDTH+MANT_WIDTH-1 downto 0);
        o_result     : out std_ulogic_vector(1+EXP_WIDTH+MANT_WIDTH-1 downto 0)
    );
end entity fp_mul;

architecture RTL of fp_mul is
    function or_reduce(v: std_ulogic_vector) return std_ulogic is
        variable a: std_ulogic := '0';
    begin
        for i in v'range loop a := a or v(i); end loop;
        return a;
    end;
    function lzc(v: std_ulogic_vector) return integer is
        variable c : integer := 0;
    begin
        for i in v'high downto v'low loop
            if v(i)='0' then c := c + 1; else exit; end if;
        end loop;
        return c;
    end;

    constant WORD_WIDTH     : integer := 1 + EXP_WIDTH + MANT_WIDTH;
    constant SIG_EXT_WIDTH  : integer := 1 + MANT_WIDTH + 3;
    constant PROD_WIDTH     : integer := 2*(MANT_WIDTH+1);
    constant PROD_HIGH      : integer := PROD_WIDTH - 1;

    constant EXP_ALL_ZERO   : std_ulogic_vector(EXP_WIDTH-1 downto 0) := (others=>'0');
    constant EXP_ALL_ONES   : std_ulogic_vector(EXP_WIDTH-1 downto 0) := (others=>'1');
    constant MANT_ZERO      : std_ulogic_vector(MANT_WIDTH-1 downto 0) := (others=>'0');
    constant ZERO_WORD      : std_ulogic_vector(WORD_WIDTH-1 downto 0) := (others=>'0');
    constant QNAN_PAYLOAD   : std_ulogic_vector(MANT_WIDTH-1 downto 0)
        := std_ulogic_vector(shift_left(to_unsigned(1, MANT_WIDTH), MANT_WIDTH-1));

    signal s1_sign1, s1_sign2 : std_ulogic := '0';
    signal s1_exp1, s1_exp2   : std_ulogic_vector(EXP_WIDTH-1 downto 0) := (others=>'0');
    signal s1_man1, s1_man2   : std_ulogic_vector(MANT_WIDTH-1 downto 0) := (others=>'0');
    signal s1_is_zero1, s1_is_zero2 : std_ulogic := '0';
    signal s1_is_sub1,  s1_is_sub2  : std_ulogic := '0';
    signal s1_is_inf1,  s1_is_inf2  : std_ulogic := '0';
    signal s1_is_nan1,  s1_is_nan2  : std_ulogic := '0';

    signal s2_sig1, s2_sig2 : std_ulogic_vector(MANT_WIDTH downto 0) := (others=>'0');
    signal s2_exp_field     : std_ulogic_vector(EXP_WIDTH-1 downto 0) := (others=>'0');
    signal s2_sign_out      : std_ulogic := '0';
    signal s2_bypass        : std_ulogic := '0';
    signal s2_bypass_word   : std_ulogic_vector(WORD_WIDTH-1 downto 0) := (others=>'0');

    signal s3_product       : std_ulogic_vector(PROD_WIDTH-1 downto 0) := (others=>'0');
    signal s3_exp_field     : std_ulogic_vector(EXP_WIDTH-1 downto 0) := (others=>'0');
    signal s3_sign_out      : std_ulogic := '0';
    signal s3_bypass        : std_ulogic := '0';
    signal s3_bypass_word   : std_ulogic_vector(WORD_WIDTH-1 downto 0) := (others=>'0');

    signal s5_result        : std_ulogic_vector(WORD_WIDTH-1 downto 0) := (others=>'0');
begin
    proc_capture: process(i_clk_100MHz, i_nrst_async)
        variable e1,e2: std_ulogic_vector(EXP_WIDTH-1 downto 0);
        variable m1,m2: std_ulogic_vector(MANT_WIDTH-1 downto 0);
    begin
        if i_nrst_async='0' then
            s1_sign1<='0'; s1_sign2<='0';
            s1_exp1<=(others=>'0'); s1_exp2<=(others=>'0');
            s1_man1<=(others=>'0'); s1_man2<=(others=>'0');
            s1_is_zero1<='0'; s1_is_zero2<='0';
            s1_is_sub1<='0'; s1_is_sub2<='0';
            s1_is_inf1<='0'; s1_is_inf2<='0';
            s1_is_nan1<='0'; s1_is_nan2<='0';
        elsif rising_edge(i_clk_100MHz) then
            s1_sign1 <= i_operand_1(i_operand_1'high);
            s1_sign2 <= i_operand_2(i_operand_2'high);
            e1 := i_operand_1(EXP_WIDTH+MANT_WIDTH-1 downto MANT_WIDTH);
            e2 := i_operand_2(EXP_WIDTH+MANT_WIDTH-1 downto MANT_WIDTH);
            m1 := i_operand_1(MANT_WIDTH-1 downto 0);
            m2 := i_operand_2(MANT_WIDTH-1 downto 0);
            s1_exp1 <= e1; s1_exp2 <= e2;
            s1_man1 <= m1; s1_man2 <= m2;

            if (e1=EXP_ALL_ZERO) and (or_reduce(m1)='0') then s1_is_zero1<='1'; else s1_is_zero1<='0'; end if;
            if (e2=EXP_ALL_ZERO) and (or_reduce(m2)='0') then s1_is_zero2<='1'; else s1_is_zero2<='0'; end if;

            if (e1=EXP_ALL_ZERO) and (or_reduce(m1)='1') then s1_is_sub1<='1'; else s1_is_sub1<='0'; end if;
            if (e2=EXP_ALL_ZERO) and (or_reduce(m2)='1') then s1_is_sub2<='1'; else s1_is_sub2<='0'; end if;

            if (e1=EXP_ALL_ONES) and (or_reduce(m1)='0') then s1_is_inf1<='1'; else s1_is_inf1<='0'; end if;
            if (e2=EXP_ALL_ONES) and (or_reduce(m2)='0') then s1_is_inf2<='1'; else s1_is_inf2<='0'; end if;

            if (e1=EXP_ALL_ONES) and (or_reduce(m1)='1') then s1_is_nan1<='1'; else s1_is_nan1<='0'; end if;
            if (e2=EXP_ALL_ONES) and (or_reduce(m2)='1') then s1_is_nan2<='1'; else s1_is_nan2<='0'; end if;
        end if;
    end process;

    proc_denorm: process(i_clk_100MHz, i_nrst_async)
        variable imp1,imp2: std_ulogic;
        variable exp_i: integer;
        variable res: std_ulogic_vector(WORD_WIDTH-1 downto 0);
    begin
        if i_nrst_async='0' then
            s2_sig1 <= (others=>'0'); s2_sig2 <= (others=>'0');
            s2_exp_field <= (others=>'0'); s2_sign_out<='0';
            s2_bypass<='0'; s2_bypass_word<=(others=>'0');
        elsif rising_edge(i_clk_100MHz) then
            s2_sign_out <= s1_sign1 xor s1_sign2;

            if (s1_is_nan1='1') or (s1_is_nan2='1') or
               ((s1_is_inf1='1') and (s1_is_zero2='1')) or
               ((s1_is_inf2='1') and (s1_is_zero1='1')) then
                s2_bypass <= '1';
                res := '0' & EXP_ALL_ONES & QNAN_PAYLOAD;
                s2_bypass_word <= res;
            elsif (s1_is_inf1='1') or (s1_is_inf2='1') then
                s2_bypass <= '1';
                res := (s1_sign1 xor s1_sign2) & EXP_ALL_ONES & MANT_ZERO;
                s2_bypass_word <= res;
            elsif (s1_is_zero1='1') or (s1_is_zero2='1') then
                s2_bypass <= '1';
                res := (s1_sign1 xor s1_sign2) & EXP_ALL_ZERO & MANT_ZERO;
                s2_bypass_word <= res;
            else
                s2_bypass <= '0';
                imp1 := '0'; if s1_exp1/=EXP_ALL_ZERO then imp1:='1'; end if;
                imp2 := '0'; if s1_exp2/=EXP_ALL_ZERO then imp2:='1'; end if;
                s2_sig1 <= imp1 & s1_man1;
                s2_sig2 <= imp2 & s1_man2;

                exp_i := to_integer(unsigned(s1_exp1)) + to_integer(unsigned(s1_exp2)) - BIAS;
                if exp_i < 0 then
                    s2_exp_field <= (others=>'0');
                elsif exp_i > (2**EXP_WIDTH - 1) then
                    s2_exp_field <= EXP_ALL_ONES;
                else
                    s2_exp_field <= std_ulogic_vector(to_unsigned(exp_i, EXP_WIDTH));
                end if;
            end if;
        end if;
    end process;

    proc_sig_mul: process(i_clk_100MHz, i_nrst_async)
    begin
        if i_nrst_async='0' then
            s3_product <= (others=>'0');
            s3_exp_field <= (others=>'0');
            s3_sign_out <= '0';
            s3_bypass<='0';
            s3_bypass_word<=(others=>'0');
        elsif rising_edge(i_clk_100MHz) then
            s3_bypass <= s2_bypass;
            s3_bypass_word <= s2_bypass_word;
            s3_sign_out <= s2_sign_out;
            s3_exp_field <= s2_exp_field;
            s3_product <= std_ulogic_vector(unsigned(s2_sig1) * unsigned(s2_sig2));
        end if;
    end process;

    proc_norm: process(i_clk_100MHz, i_nrst_async)
        variable prod_u  : unsigned(PROD_WIDTH-1 downto 0);
        variable prod_v  : std_ulogic_vector(PROD_WIDTH-1 downto 0);
        variable exp_t   : std_ulogic_vector(EXP_WIDTH-1 downto 0);
        variable tmp     : std_ulogic_vector(SIG_EXT_WIDTH-1 downto 0);
        variable widen   : unsigned(SIG_EXT_WIDTH downto 0);
        variable mant    : std_ulogic_vector(MANT_WIDTH-1 downto 0);
        variable sign_o  : std_ulogic;
        variable G,R,S,LSB,round_up : std_ulogic;
        variable lzv,shift_left_amt : integer;
        variable exp_u  : unsigned(EXP_WIDTH-1 downto 0);
        variable sticky : std_ulogic;
        variable outw   : std_ulogic_vector(WORD_WIDTH-1 downto 0);
        variable need_left : boolean;
    begin
        if i_nrst_async='0' then
            s5_result <= (others=>'0');
        elsif rising_edge(i_clk_100MHz) then
            if s3_bypass='1' then
                s5_result <= s3_bypass_word;
            else
                prod_u := unsigned(s3_product);
                exp_t  := s3_exp_field;
                sign_o := s3_sign_out;

                if prod_u(PROD_HIGH)='1' then
                    prod_u := shift_right(prod_u,1);
                    exp_t  := std_ulogic_vector(unsigned(exp_t)+1);
                else
                    need_left := (prod_u(PROD_HIGH-1)='0');
                    if need_left then
                        lzv := lzc(std_ulogic_vector(prod_u));
                        shift_left_amt := lzv - 1;
                        if shift_left_amt > 0 then
                            if shift_left_amt >= prod_u'length then
                                prod_u := (others=>'0');
                                exp_t := (others=>'0');
                            else
                                prod_u := shift_left(prod_u, shift_left_amt);
                                if to_integer(unsigned(exp_t)) > shift_left_amt then
                                    exp_t := std_ulogic_vector(unsigned(exp_t) - to_unsigned(shift_left_amt, EXP_WIDTH));
                                else
                                    sticky := '0';
                                    if shift_left_amt >= prod_u'length then
                                        sticky := or_reduce(std_ulogic_vector(prod_u));
                                        prod_u := (others=>'0');
                                    end if;
                                    exp_t := (others=>'0');
                                end if;
                            end if;
                        end if;
                    end if;
                end if;

                prod_v := std_ulogic_vector(prod_u);
                tmp := (others=>'0');
                tmp(tmp'high) := prod_v(PROD_HIGH-1);
                if MANT_WIDTH>0 then
                    tmp(tmp'high-1 downto 3) := prod_v(PROD_HIGH-2 downto MANT_WIDTH);
                else
                    tmp(tmp'high-1 downto 3) := (others=>'0');
                end if;
                if MANT_WIDTH>=1 then G := prod_v(MANT_WIDTH-1); else G := '0'; end if;
                if MANT_WIDTH>=2 then R := prod_v(MANT_WIDTH-2); else R := '0'; end if;
                if MANT_WIDTH>=3 then
                    S := '0';
                    for i in 0 to MANT_WIDTH-3 loop S := S or prod_v(i); end loop;
                else
                    S := '0';
                end if;
                LSB := tmp(3);
                tmp(2) := G; tmp(1) := R; tmp(0) := S;

                if (G='1') and (R='1' or S='1' or LSB='1') then round_up:='1'; else round_up:='0'; end if;

                widen := (others=>'0');
                widen(widen'high-1 downto 0) := unsigned(tmp);
                if round_up='1' then
                    widen := widen + shift_left(to_unsigned(1, widen'length), 3);
                end if;

                if widen(widen'high)='1' then
                    widen := shift_right(widen,1);
                    exp_t := std_ulogic_vector(unsigned(exp_t)+1);
                end if;

                tmp  := std_ulogic_vector(widen(widen'high-1 downto 0));
                mant := tmp(tmp'high-1 downto 3);

                if unsigned(exp_t)=0 then
                    if or_reduce(mant)='0' then
                        outw := ZERO_WORD;
                    else
                        outw := sign_o & EXP_ALL_ZERO & mant;
                    end if;
                elsif exp_t=EXP_ALL_ONES then
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
