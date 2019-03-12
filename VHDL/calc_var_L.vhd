--==========================================================
-- Unit		:	cal_var_L(rtl)
-- File		:	cal_var_L.vhd
-- Purpose	:	
-- Author	:	Michael Hersche - HPE - ETH Zuerich
-- Device	:	Altera FPGA - Cyclone V
-- EDA syn	:	Altera Quartus II
-- EDA sim	:	Modelsim SE 10.1c
-- misc		:	--
-- depdcy	:	--
--==========================================================

--! @file cal_var_L.vhd
--! @author Michael Hersche
--! @date  22.05.2018

-- use standard library
library ieee;
--! Use logic elements
use ieee.std_logic_1164.all;
--! Use numeric elements
use ieee.numeric_std.all;
--! use real valued library 
use ieee.math_real.all; 


--! @brief variable L generator 
entity cal_var_L is 
	generic(DATAWIDTH_G	: integer:= 16;  --! General internal datawidth
			FS_G 			: real 	 := 60000.0; --! Switching frequency 
			F_CLK_G			: real 	 := 100.0*(10**6); --! Clock frequency  
			L1_G			: real 	 := 0.00025;--0.00013; --! Inductance [H] at point 1 
			L2_G 			: real 	 :=  0.00025;--0.000115; --! Inductance [H] at point 2 
			L3_G 			: real 	 :=  0.00025;--0.00003; --! Inductance [H] at point 3 
			A1_G			: real	 := 160.0; --! Current [A] corner 1 
			A2_G 			: real	 := 250.0; --! Current [A] corner 2 
			A3_G 			: real	 := 300.0  --! Current [A] corner 3 
			);		
	port( 	clk_i			: in std_logic; --! Main clock 
			nreset_i 		: in std_logic; --! Asynchronous reset 
			current_i		: in signed(DATAWIDTH_G -1 downto 0); 
			H_bound_fac_o	: out signed (12 downto 0); 
			dH_fac_o		: out signed (15 downto 0) 
			);
			
end cal_var_L;


architecture structural of cal_var_L is
-- ================== CONSTANTS ==================================================		
constant MANT_C : natural := 11; --! Mantissa : all factors are shifted 11 bits to left 
constant a_LEN_C : natural := 16; --! length of a's 
constant b_LEN_C : natural := 28; --! length of b's 

constant MULT_CNT_C: natural := 18; --! Time for first multiplication 
-- calculation constants for H bound 
constant L1_2fs_C: real := L1_G*2.0*FS_G; 
constant L2_2fs_C: real := L2_G*2.0*FS_G; 
constant L3_2fs_C: real := L3_G*2.0*FS_G; 

constant b1_C: signed(b_LEN_C-1 downto 0) := to_signed(integer(L1_2fs_C*(2.0**MANT_C)),b_LEN_C); 

constant a2_C: signed(a_LEN_C-1 downto 0) := to_signed(integer(((L1_2fs_C-L2_2fs_C)/(A2_G-A1_G))*(2.0**MANT_C)),a_LEN_C); 
constant b2_C: signed(b_LEN_C-1 downto 0) := to_signed(integer((L1_2fs_C+A1_G*(L1_2fs_C-L2_2fs_C)/(A2_G-A1_G))*2.0**MANT_C),b_LEN_C); 

constant a3_C: signed(a_LEN_C-1 downto 0) := to_signed(integer(((L2_2fs_C-L3_2fs_C)/(A3_G-A2_G))*(2.0**MANT_C)),a_LEN_C); 
constant b3_C: signed(b_LEN_C-1 downto 0) := to_signed(integer((L2_2fs_C+A2_G*(L2_2fs_C-L3_2fs_C)/(A3_G-A2_G))*(2.0**MANT_C)),b_LEN_C); 

constant A1_sign: signed(10 downto 0) :=  to_signed(integer(A1_G),11); 
constant A2_sign: signed(10 downto 0) :=  to_signed(integer(A2_G),11); 
constant A3_sign: signed(10 downto 0) :=  to_signed(integer(A3_G),11); 

constant NUM_C: signed(25 downto 0) := to_signed(2**(24),26);


-- calculation constants for delta H bound 
constant L1_fclk_C: real := L1_G*F_CLK_G; 
constant L2_fclk_C: real := L2_G*F_CLK_G; 
constant L3_fclk_C: real := L3_G*F_CLK_G; 

constant b1_d_C: signed(b_LEN_C-1 downto 0) := to_signed(integer(L1_fclk_C),b_LEN_C); 

constant a2_d_C: signed(a_LEN_C-1 downto 0) := to_signed(integer((L1_fclk_C-L2_fclk_C)/(A2_G-A1_G)),a_LEN_C); 
constant b2_d_C: signed(b_LEN_C-1 downto 0) := to_signed(integer(L1_fclk_C+A1_G*(L1_fclk_C-L2_fclk_C)/(A2_G-A1_G)),b_LEN_C); 

constant a3_d_C: signed(a_LEN_C-1 downto 0) := to_signed(integer((L2_fclk_C-L3_fclk_C)/(A3_G-A2_G)),a_LEN_C); 
constant b3_d_C: signed(b_LEN_C-1 downto 0) := to_signed(integer(L2_fclk_C+A2_G*(L2_fclk_C-L3_fclk_C)/(A3_G-A2_G)),b_LEN_C); 

-- =================== STATES ====================================================

-- =================== SIGNALS ===================================================

signal current_s : signed(10 downto 0) := (others => '0'); 
-- signals for H bounds
signal a_s, a_next_s: signed(a_LEN_C-1 downto 0) := (others => '0'); 
signal b_s, b_next_s: signed(b_LEN_C-1 downto 0) := (others => '0'); 
signal x1_s : std_logic_vector(26 downto 0) := (others => '0'); --! a_s * current_s
signal x2_s, x2_next_s : signed(b_LEN_C-1 downto 0) := (others => '0'); --! b_s - a_s * current_s 
signal x3_s : signed(25 downto 0);-- := (others => '0'); --! limit (b_s - a_s * current_s ) to 25 bits  
signal x4_s : std_logic_vector(25 downto 0) := (others => '0'); --! 2^(13+11)/(b_s - a_s * current_s )
signal x5_s : signed (12 downto 0):= (others => '0'); --! limit (2^(13+11)/(b_s - a_s * current_s )) to 13 bits 

-- signals for dH bounds 
signal a_d_s, a_d_next_s: signed(a_LEN_C-1 downto 0) := (others => '0'); 
signal b_d_s, b_d_next_s: signed(b_LEN_C-1 downto 0) := (others => '0'); 
signal x1_d_s : std_logic_vector(26 downto 0) := (others => '0'); --! a_d_s * current_s
signal x2_d_s, x2_d_next_s : signed(b_LEN_C-1 downto 0) :=b1_d_C; --! b_d_s - a_d_s * current_s 
signal x3_d_s : signed(15 downto 0) := (others => '0'); --! limit (b_d_s - a_d_s * current_s ) to 16 bits  

-- timing 
signal cnt_s, cnt_next_s: integer range 0 to MULT_CNT_C := 0;  

-- ================== COMPONENTS =================================================
--! @brief reduces the number of bits by limiting input singal and prevents over/underflow 
component signed_limiter is 
	generic( 	IN_BITS_G 	: natural := 16;  --! Number of input bits
				OUT_BITS_G	: natural := 16 --! Number of output bits 
			);		
	port( 	clk_i			: in std_logic; --! Main clock 
			nreset_i 		: in std_logic; --! Asynchronous reset 
			data_i			: in signed(IN_BITS_G-1 downto 0); --! Input value  
			data_o			: out signed(OUT_BITS_G-1 downto 0) --! Input value  
			);
end component;


component my_16_11_mult is
	port
	(
		clock		: in std_logic ;
		dataa		: in std_logic_vector (15 downto 0);
		datab		: in std_logic_vector (10 downto 0);
		result		: out std_logic_vector (26 downto 0)
	);
end component;

component my_26_divider is
	port
	(
		clock		: in std_logic ;
		denom		: in std_logic_vector (25 downto 0);
		numer		: in std_logic_vector (25 downto 0);
		quotient	: out std_logic_vector (25 downto 0);
		remain		: out std_logic_vector (25 downto 0)
	);
end component;



begin	
	
	--! @brief Register 
	--! @details Asynchronous reset nreset_i
	input_reg : process(clk_i,nreset_i)
	begin
		if nreset_i = '0' then
			current_s <= (others => '0');
			-- H bound 
			a_s <= (others => '0'); 
			b_s <= b1_C; -- init values 
			x2_s<= b1_C; -- init values 
			-- dH bound 
			a_d_s  <=  (others => '0');
			b_d_s  <=  b1_d_C;
			x2_d_s  <=  b1_d_C;
			-- Timing
			cnt_s <= 0; 
		elsif rising_edge(clk_i) then
			current_s <= current_i(DATAWIDTH_G-1 downto 5); 
			-- H bound 
			a_s <= a_next_s; 
			b_s <= b_next_s;  
			x2_s<= x2_next_s; 
			-- dH bound 
			a_d_s  <=  a_d_next_s; 
			b_d_s  <=  b_d_next_s;
			x2_d_s <= x2_d_next_s;
			-- Timing 
			cnt_s <= cnt_next_s; 
		end if; 
	end process; 
	
	
		
	--! @brief Logic for assigning a's and b's depending on current 
	WEIGHTS_LOGIC: process(current_i,current_s,cnt_s,a_s,b_s,x1_s,a_d_s,b_d_s,x1_d_s,x2_s,x2_d_s)
		begin			
			a_next_s <= a_s; 
			b_next_s <= b_s; 
			a_d_next_s <= a_d_s; 
			b_d_next_s <= b_d_s; 
			cnt_next_s <= cnt_s; 
			x2_next_s <= x2_s; 
			x2_d_next_s <= x2_d_s; 
			
			if current_i(DATAWIDTH_G-1 downto 5) /= current_s then -- new calculation 
				
				if current_i(DATAWIDTH_G-1 downto 5) <= A1_sign then 
					a_next_s <= (others => '0'); 
					b_next_s <= b1_C; 
					a_d_next_s <= (others => '0'); 
					b_d_next_s <= b1_d_C; 
				elsif (current_i(DATAWIDTH_G-1 downto 5) <= A2_sign) then 
					a_next_s <= a2_C; 
					b_next_s <= b2_C; 
					a_d_next_s <= a2_d_C; 
					b_d_next_s <= b2_d_C; 
				else 
					a_next_s <= a3_C; 
					b_next_s <= b3_C; 
					a_d_next_s <= a3_d_C; 
					b_d_next_s <= b3_d_C; 
				end if; 
				cnt_next_s <= 0; 
				
			elsif cnt_s = MULT_CNT_C then -- first stage done 
				x2_next_s <= b_s - resize(signed(x1_s),b_LEN_C); 
				x2_d_next_s <= b_d_s - resize(signed(x1_d_s),b_LEN_C); 
				cnt_next_s <= MULT_CNT_C; 
			else 
				cnt_next_s <= cnt_s + 1;
			end if; 
				
 
			
		end process; 
		
	------------------ H bound ----------------------------------------	
	mult_a_curr_inst : my_16_11_mult
	port map (clock	=> clk_i, 
	          dataa	=> std_logic_vector(a_s), 
	          datab	=> std_logic_vector(current_s), 
	          result =>x1_s ); 	
	
	
	
	lim_inst1: signed_limiter 
	generic map( IN_BITS_G => 28,   --! Number of input bits
				OUT_BITS_G => 	26 --! Number of output bits 
			)		
	port map(clk_i	 => clk_i,
			nreset_i => nreset_i, 
			data_i	 => x2_s, 
			data_o	=> x3_s
			);
			
			
	div_inst:  my_26_divider 
	port map 
	(
		clock		=> clk_i, 
		denom		=> std_logic_vector(x3_s),
		numer		=> std_logic_vector(NUM_C),
		quotient	=> x4_s, 
		remain		=> open 
	);
	
	lim_inst2: signed_limiter 
	generic map( 	IN_BITS_G => 26,   --! Number of input bits
				OUT_BITS_G => 	13 --! Number of output bits 
			)		
	port map(clk_i	 => clk_i,
			nreset_i => nreset_i, 
			data_i	 => signed(x4_s), 
			data_o	=> x5_s
			);

------------------ dH factor -------------------------------------
	mult_d_curr_inst : my_16_11_mult
	port map (clock	=> clk_i, 
	          dataa	=> std_logic_vector(a_d_s), 
	          datab	=> std_logic_vector(current_s), 
	          result =>x1_d_s ); 			
			
	lim_inst_d1: signed_limiter 
	generic map( 	IN_BITS_G => 28,   --! Number of input bits
				OUT_BITS_G => 	16 --! Number of output bits 
			)		
	port map(clk_i	 => clk_i,
			nreset_i => nreset_i, 
			data_i	 => x2_d_s, 
			data_o	=> x3_d_s
			);		
						
H_bound_fac_o <= signed(x5_s); 
dH_fac_o <= signed(x3_d_s); 

end structural; 