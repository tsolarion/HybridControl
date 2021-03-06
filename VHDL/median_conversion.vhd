--==========================================================
-- Unit		:	median_conversion(rtl)
-- File		:	median_conversion.vhd
-- Purpose	:	
-- Author	:	Michael Hersche - HPE - ETH Zuerich
-- Device	:	Altera FPGA - Cyclone V
-- EDA syn	:	Altera Quartus II
-- EDA sim	:	Modelsim SE 10.1c
-- misc		:	--
-- depdcy	:	my_16_mult, signed_limiter, median_filt
--==========================================================

--! @file median_conversion.vhd
--! @author Michael Hersche
--! @date  15.11.2018
--! @version 1.0

-- use standard library
library ieee;
--! Use logic elements
use ieee.std_logic_1164.all;
--! Use numeric elements
use ieee.numeric_std.all;


--! @brief Input value gets meidan filtered and transformed  
--! @details 
--! @details
--! @details 

entity median_conversion is 
	generic( 	
				INW_G				: natural range 1 to 16 := 13; --! input Data width   	
				OUTW_G				: natural range 1 to 16 := 16; --! Datawidth of output 
				FRAC_O_G			: natural range 0 to 15 := 5; --! Number of output fractional bits 
				
				FRAC_F_G			: natural range 0 to 15 := 10; --! factor fractional bits 
				-- 
				OFFSET_G			: real := 30.0; -- Offset to add 
				FACTOR_G 			: real := -9.5; --factor to divide 
				--
				NMEDIAN_TAPS_G		: natural range 1 to 99 := 3; --! number of taps for median filtering l
				MAX_VAL_G			: real := 100.0 --! maximum value allowed, corresponds to effective value (here 100A or 100V). If too high/low :  over/undershoot 
			);		
	port( 	clk_i			: in std_logic; --! Main clock 
			nreset_i 		: in std_logic; --! Asynchronous reset 
			din_valid_i		: in std_logic; --! New input data valid 
			x_i				: in signed(INW_G -1 downto 0); --! input value as signed fixed point INT_I_G.FRAC_I_G 
			x_o				: out signed(OUTW_G -1 downto 0); --! output value as signed fixed point INT_I_G.FRAC_O_C
			nover_undershoot_o: out std_logic --! low active overshoot, undershoot output 
			);		
end median_conversion;


architecture structural of median_conversion is
-- ================== CONSTANTS ==================================================				
constant OFFSET_C : signed(INW_G downto 0) := to_signed(integer(OFFSET_G),INW_G+1);
constant FACTOR_C : std_logic_vector(15 downto 0) := std_logic_vector(to_signed(integer((2.0**FRAC_F_G)/FACTOR_G),16)); 

--
constant LIMIT_IN_BIT_C: natural := 32 - (FRAC_F_G - FRAC_O_G); --! number of bits of the input of limiter 

constant MAX_VAL_C : signed(INW_G-1 downto 0) := to_signed(integer(MAX_VAL_G*abs(FACTOR_G) -OFFSET_G),INW_G); 
constant MIN_VAL_C : signed(INW_G-1 downto 0) := to_signed(integer(-MAX_VAL_G*abs(FACTOR_G) -OFFSET_G),INW_G); 
-- =================== STATES ====================================================


-- =================== SIGNALS ===================================================
signal x_median_s: signed(INW_G -1 downto 0) := (others => '0'); --! median filtered signal 
signal x_p_offs_next_s, x_p_offs_s: signed(INW_G downto 0) := (others => '0'); --! result of offset calibrated signal 
signal mult_i_s : std_logic_vector(15 downto 0) := (others => '0');  --! input of multiplier for calibration 
signal mult_o_s	: std_logic_vector(31 downto 0) := (others => '0'); --! output of multiplier 
signal limit_i_s: signed(LIMIT_IN_BIT_C-1 downto 0) := (others => '0'); --! input of limiter (some fractional bits already removed)
signal limit_o_s: signed(OUTW_G -1 downto 0) := (others => '0'); --! output of limiter: some integer bits removed 
signal nover_undershoot_s, nover_undershoot_next_s : std_logic; --! low active overshoot/ undershoot signal 
-- ================== COMPONENTS =================================================
component median_filt is
	generic(
		NTAPS : natural := 32; 					-- Number of taps 
		IN_WIDTH : natural range 8 to 17 := 12
	);
	port(
			clk_i 		: in std_logic;					--! Clock
			nreset_i 	: in std_logic;					--! Reset
			din_valid_i : in std_logic;					--! Flag for valid input data
			sample_i 	: in signed(IN_WIDTH-1 downto 0);	--! Signal to be averaged
			median_o 	: out signed(IN_WIDTH-1 downto 0)	--! Average value
		);
	end component;
	
component my_16_mult IS
	PORT
	(
		clock		: IN STD_LOGIC ;
		dataa		: IN STD_LOGIC_VECTOR (15 DOWNTO 0);
		datab		: IN STD_LOGIC_VECTOR (15 DOWNTO 0);
		result		: OUT STD_LOGIC_VECTOR (31 DOWNTO 0)
	);
END component;

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


begin
--
	
REG: process (clk_i, nreset_i)
begin 
	if nreset_i = '0' then 
		x_p_offs_s <= (others => '0');
		nover_undershoot_s <= '1'; 
	elsif rising_edge(clk_i) then 
		x_p_offs_s <= x_p_offs_next_s;
		nover_undershoot_s <= nover_undershoot_next_s; 
	end if; 
end process REG;
 
median_inst: median_filt
generic map(
	NTAPS => NMEDIAN_TAPS_G, 
	IN_WIDTH =>INW_G
	)
port map(
	clk_i 		=> clk_i, 
	nreset_i 	=> nreset_i, 
	din_valid_i => din_valid_i, 
	sample_i 	=> x_i, 
	median_o 	=> x_median_s
	);

arithmetic_proc: process(x_median_s,x_p_offs_s,mult_o_s)
begin 
	if x_median_s > MAX_VAL_C or x_median_s < MIN_VAL_C then 
		nover_undershoot_next_s	<= '0'; 
		x_p_offs_next_s			<= (others => '0'); 
		mult_i_s				<= (others => '0'); 
		limit_i_s				<= (others => '0'); 
	else 
		nover_undershoot_next_s	<= '1'; 
		x_p_offs_next_s <= resize(x_median_s,INW_G+1) + OFFSET_C; 
		mult_i_s		<= std_logic_vector(resize(x_p_offs_s, 16)); 
		limit_i_s		<= signed(mult_o_s(31 downto (32-LIMIT_IN_BIT_C)));
	end if; 
end process; 

mult_inst: my_16_mult
port map	(
		clock	=> clk_i, 	
		dataa	=> FACTOR_C, 
		datab	=> 	mult_i_s, 
		result	=> 	mult_o_s
	);
	
limit_inst: signed_limiter  
	generic map( 	IN_BITS_G => LIMIT_IN_BIT_C, 
				OUT_BITS_G	=> OUTW_G 
			)	
	port map( 	clk_i	=> clk_i, 
			nreset_i 	=> nreset_i, 
			data_i		=> limit_i_s,
			data_o		=> limit_o_s
			);
	
x_o <= limit_o_s;
nover_undershoot_o <= nover_undershoot_s;  
end structural; 