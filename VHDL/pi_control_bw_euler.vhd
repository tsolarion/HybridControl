--==========================================================
-- Unit		:	pi_ctrl_bw_euler(rtl)
-- File		:	pi_control_bw_euler.vhd
-- Purpose	:	
-- Author	:	Michael Hersche - HPE - ETH Zuerich
-- Device	:	Altera FPGA - Cyclone V
-- EDA syn	:	Altera Quartus II
-- EDA sim	:	Modelsim SE 10.1c
-- misc		:	--
-- depdcy	:	my_16_18_mult
--==========================================================

--! @file pi_control_bw_euler.vhd
--! @author Michael Hersche
--! @date  26.09.2017

-- use standard library
library ieee;
--! Use logic elements
use ieee.std_logic_1164.all;
--! Use numeric elements
use ieee.numeric_std.all;

--! @brief PI Control block using backward euler approximation
entity pi_control_bw_euler is 
	generic( 	-- default Kp = 2; Ki = 20000 -> KIs = 0.5, assuming fs = 20000 Hz
			INW_G 		: natural range 1 to 64 := 16; 		--! input bits
			OUTW_G		: natural range 1 to 64 := 16; 
			ANTI_WINDUP_G: integer 				:= 20*(2**5); --! maximum error for integration active 
			GAINBM_G	: natural range 0 to 16 := 1; 		--! fractional fixed points bit
			GAINBP_G	: natural range 1 to 16 := 2 		--! integer bits
			);		
	port( 	clk_i		: in std_logic; --! Main clock 
				nreset_i	: in std_logic; --! Main asynchronous reset low active
				nsoftreset_i: in std_logic; --! Synchronous reset signal low active 
				int_enable_i: in std_logic; --! Enable integral part 
				data_i		: in signed(INW_G-1 downto 0); --! Input data 
				data_valid_i: in std_logic; --! rising edge indicates new data 
				kprop_i		: in signed(GAINBM_G + GAINBP_G -1 downto 0);  --! Proportional gain:  kprop_i = Kp*(2**GAINBM)
				kixts_i		: in signed(GAINBM_G + GAINBP_G -1 downto 0);  --! Integral gain:  kixts = (Ki/fs)*(2**GAINBM)	
				result_o 	: out signed(OUTW_G-1 downto 0); --! Output data 			
				result_valid_o: out std_logic
			);
			
end pi_control_bw_euler;

architecture structural of pi_control_bw_euler is
-- ================== CONSTANTS ==================================================	
constant MULTW_C 	: natural := GAINBM_G + GAINBP_G;  -- multiplier constant width			
--constant INT_MULT_C	: signed(MULTW_C-1 downto 0) := to_signed(KixTs_G,MULTW_C); 
--constant PROP_MULT_C: signed(MULTW_C-1 downto 0) := to_signed(Kprop_G,MULTW_C); 

constant ONES_C		: signed(OUTW_G + GAINBM_G -2 downto 0) := (others => '1');
constant LIMIT_TMP_C: signed(OUTW_G+MULTW_C downto 0) := resize('0' & ONES_C,OUTW_G+MULTW_C+1);
constant LIMIT_C 	: signed(OUTW_G+MULTW_C+2 downto 0) := resize(LIMIT_TMP_C, OUTW_G+MULTW_C+3);	
constant NO_CYCLES 	: integer := 40; 
-- ================== COMPONENTS =================================================

component my_16_18_mult is
	port
	(
		clock		: in std_logic ;
		dataa		: in std_logic_vector (15 downto 0);
		datab		: in std_logic_vector (17 downto 0);
		result		: out std_logic_vector (33 downto 0)
	);		
end component ;
	
-- =================== STATES ====================================================
	

-- =================== SIGNALS ===================================================
-- Signals for synchronization
signal data_valid_s : std_logic_vector(1 downto 0); --! Vector of data_valid_i for detecting rising edge of signal  
signal int_enable_s : std_logic; 
-- Signals for calculation
signal in_data_s, in_data_next_s			: signed(INW_G - 1 downto 0); --! Input data read with rising edge of data_valid_i  
signal in_data_del_s, in_data_del_next_s	: signed(INW_G - 1 downto 0); --! Input data delayed by one cycle of data_valid_i 
signal out_data_s, out_data_next_s			: signed(OUTW_G + MULTW_C downto 0); --! Output data  
signal out_data_del_s, out_data_del_next_s	: signed(OUTW_G + MULTW_C downto 0); --! Output data delayed by one cycle of data_valid_i 
-- first stage signals 
signal diff_in_data_s, diff_in_data_next_s	: signed(INW_G downto 0); --! Difference in_data_s - in_data_del_s
signal int_data_s							: signed(INW_G downto 0); --! Input data used for integration term, extended by one bit  
-- second stage signals 
signal P_data_s, I_data_s					: std_logic_vector(INW_G + MULTW_C downto 0); 
signal P_data_next_s, I_data_next_s			: std_logic_vector(INW_G + MULTW_C  downto 0);
-- third stage signals
signal PplusI_data_s, PplusI_data_next_s	: signed(INW_G + MULTW_C + 2 downto 0); 
-- output counter 
signal output_cntr : integer range 0 to NO_CYCLES+1:= 0;
-- Anti Windup signal 
signal anti_windup_s : std_logic := '0'; -- high if Integral term can be enabled 
 

begin		

--! @brief Input registers for data_valid_s,  in_data_s  
--! @details Asynchronous(nreset_i) and synchronous(nsoftreset_i) reset possible
IN_REG: process(clk_i, nreset_i, nsoftreset_i)
	begin 
		if nreset_i = '0' then -- asynchronous reset 
			data_valid_s 	<= (others => '0');
			int_enable_s	<= '0'; 
			in_data_s 		<= (others => '0');
			in_data_del_s 	<= (others => '0');
			out_data_del_s	<= (others => '0'); 
		elsif rising_edge(clk_i) then 
			if nsoftreset_i = '0' then -- softreset
				data_valid_s 	<= (others => '0');
				int_enable_s	<= '0'; 
				in_data_s 		<= (others => '0');
				in_data_del_s 	<= (others => '0');
				out_data_del_s	<= (others => '0'); 
			else -- now write data into registers 
				data_valid_s 	<= data_valid_s(data_valid_s'left -1 downto 0) & data_valid_i; 
				int_enable_s	<= int_enable_i AND anti_windup_s; 
				in_data_s 	 	<= in_data_next_s; 
				in_data_del_s 	<= in_data_del_next_s; 
				out_data_del_s	<= out_data_del_next_s; 
			end if; 			
		end if; 
end process IN_REG; 	

--! @brief Input process for data_i 
--! @details Only update data at rising edge of 
DATA_INPUT_LOGIC: process(data_valid_s,data_i, in_data_s,out_data_s,in_data_del_s,out_data_del_s)
	begin	
		if data_valid_s = "01" then -- new data arrived 
			in_data_next_s 		<= data_i;
			in_data_del_next_s 	<= in_data_s; 
			out_data_del_next_s <= out_data_s;
		else 
			in_data_next_s 		<= in_data_s; 
			in_data_del_next_s 	<= in_data_del_s;			
			out_data_del_next_s <= out_data_del_s; 	
		end if; 
end process DATA_INPUT_LOGIC; 

-- Anti windup logic 
anti_windup_s <= '1' when (in_data_s < ANTI_WINDUP_G) and (in_data_s > -ANTI_WINDUP_G) else '0'; 


-- Calculations for PI controller 
-- 1. Stage 
diff_in_data_next_s <= resize(in_data_s,INW_G+1) - resize(in_data_del_s, INW_G +1); -- resize used for avoiding overflow

-- 2. Stage 
--! @brief P_data_next_s <= kprop_i * diff_in_data_s; 
mult_P : my_16_18_mult
port map 
(
	clock		=> clk_i, 
	dataa		=> std_logic_vector(kprop_i), 
	datab		=> std_logic_vector(diff_in_data_s), 
	result		=> P_data_next_s
);		

--! @brief I_data_next_s <= kixts_i * int_data_s; 
mult_I : my_16_18_mult
port map 
(
	clock		=> clk_i, 
	dataa		=> std_logic_vector(kixts_i), 
	datab		=> std_logic_vector(int_data_s), 
	result		=> I_data_next_s
);		
	
-- 3. Stage ADD Anti_windup with LIMIT_Cs 
PROC_ANTI_WINDUP: process(P_data_s, I_data_s, int_enable_s,out_data_del_s)
begin 
	if int_enable_s = '1' then 
		PplusI_data_next_s <= resize(signed(P_data_s),INW_G+MULTW_C+3) + resize(signed(I_data_s),INW_G+MULTW_C+3) + resize(out_data_del_s,INW_G+MULTW_C+3) ; 
	else 
		PplusI_data_next_s <= resize(signed(P_data_s),INW_G+MULTW_C+3) + resize(out_data_del_s,INW_G+MULTW_C+3); 		
	end if; 
end process;
 
-- 4. Stage 
PROC_LIMIT: process(PplusI_data_s)
begin
	if PplusI_data_s > LIMIT_C then 
		out_data_next_s <= LIMIT_TMP_C; 	
	elsif PplusI_data_s < -LIMIT_C then 
		out_data_next_s <= -LIMIT_TMP_C; 
	else 
		out_data_next_s <= resize(PplusI_data_s, OUTW_G + MULTW_C+1); 
	end if; 
end process; 



--! @brief Registers for calculation stages 
--! @details Asynchronous(nreset_i) and synchronous(nsoftreset_i) reset possible
CALC_REG: process(clk_i, nreset_i, nsoftreset_i)
	begin 
		if nreset_i = '0' then -- asynchronous reset 
			diff_in_data_s	<= (others => '0');
			int_data_s		<= (others => '0'); 
			P_data_s		<= (others => '0');
			I_data_s		<= (others => '0');
			PplusI_data_s	<= (others => '0');
		elsif rising_edge(clk_i) then 
			if nsoftreset_i = '0' then -- softreset
				diff_in_data_s 	<= (others => '0');
				int_data_s		<= (others => '0');
				P_data_s		<= (others => '0');
				I_data_s		<= (others => '0'); 
				PplusI_data_s	<= (others => '0');		
			else -- now write data into registers 
				-- first stage 
				diff_in_data_s 	<= diff_in_data_next_s; 
				int_data_s		<= resize(in_data_del_s,INW_G+1); 
				-- second stage 
				P_data_s		<= P_data_next_s;
				I_data_s		<= I_data_next_s;
				-- third stage 
				PplusI_data_s	<= PplusI_data_next_s;
			end if; 			
		end if; 
end process CALC_REG;


OUT_REG: process(clk_i, nreset_i,nsoftreset_i)
	begin 
		if nreset_i = '0' then -- asynchronous reset 
			output_cntr <= 0; 
			out_data_s	<= (others => '0');
			result_valid_o <= '0'; 
		elsif rising_edge(clk_i) then 
			if nsoftreset_i = '0' then -- softreset
				output_cntr <= 0; 
				out_data_s	<= (others => '0');
				result_valid_o <= '0'; 
			else -- now write data into registers 
				if data_valid_s = "01" then 
					output_cntr <= 0; 
					out_data_s <= out_data_s;
					result_valid_o <= '0'; 
				elsif output_cntr = NO_CYCLES then 
					output_cntr <= NO_CYCLES+1; 
					out_data_s <= out_data_next_s; 
					result_valid_o <= '1'; 
				elsif output_cntr = NO_CYCLES+1 then 
					output_cntr <= NO_CYCLES+1; 
					out_data_s <= out_data_s; 
					result_valid_o <= '0'; 
				else 
					output_cntr <= output_cntr + 1; 
					out_data_s <= out_data_s;
					result_valid_o <= '0'; 
				end if; 
				
			end if; 			
		end if; 
end process OUT_REG;


result_o <= out_data_s(OUTW_G+GAINBM_G-1 downto GAINBM_G); 

end structural;
						