--==========================================================
-- Unit		:	calc_hyst_bounds(rtl)
-- File		:	calc_hyst_bounds.vhd
-- Purpose	:	
-- Author	:	Michael Hersche - HPE - ETH Zuerich
-- Device	:	Altera FPGA - Cyclone V
-- EDA syn	:	Altera Quartus II
-- EDA sim	:	Modelsim SE 10.1c
-- misc		:	--
-- depdcy	:	--
--==========================================================

--! @file calc_hyst_bounds.vhd
--! @author Michael Hersche
--! @date  24.10.2017

-- use standard library
library ieee;
--! Use logic elements
use ieee.std_logic_1164.all;
--! Use numeric elements
use ieee.numeric_std.all;

--! @brief Calculate hystersis bound Hss. 
--! @details Hss is caclulated as follows: 
--! @details Hss = 1/(2*L*fs)*(1 - (V2 + Vc)/(V1 + V2))*(V2+Vc)
--! @details Multiplications and divisions are done with dedicated IP blocks 


entity calc_hyst_bounds is 
	generic( 	DATAWIDTH_G : natural := 16; 
				NINTERLOCK_G: natural := 50 -- number of interlock clocks 
			);		
	port( 	clk_i			: in std_logic; --! Main clock 
			nreset_i 		: in std_logic; --! Asynchronous reset 
			vbush_i    		: in signed(DATAWIDTH_G-1 downto 0); --! V1 measured voltage 
			vbusl_i     	: in signed(DATAWIDTH_G-1 downto 0); --! V2 measured voltage
			vc_i 			: in signed(DATAWIDTH_G-1 downto 0); --! Vc measured voltage
			iset_i			: in signed(DATAWIDTH_G-1 downto 0); --! set current 
			phase_shift_en_i: in std_logic;  --! start of calculation 		
			H_bount_fac_i	: in signed(12 downto 0); --! 1/(2*fs*L) 
			hss_bound_o 	: out signed(DATAWIDTH_G-1 downto 0) --! signed output value
			);
			
end calc_hyst_bounds;

architecture structural of calc_hyst_bounds is
-- ================== CONSTANTS ==================================================				
constant CNT_SQUARE_C : integer := 22; --! number of clock cycles for squaring (18 bits)
constant CNT_DIV_C	  : integer := 38; --! number of clock cycles for division (36 bits)
constant CNT_SCL_C	  : integer := 39; --! number of clock cycles for scaling (37 bits)
constant CNT_DIFF_C	  : integer := 5; --! number of clock cycles for difference 

-- scaling constants 
constant MANT_SCALE_C : integer := 13; --! Mantissa for increasing resolution in Sacling
--constant SCALE_DIV_C  : integer := 30; --! Denominator for Scaling 2*L*F_pwm = 2*250e-6*60e3
--constant SCALE_MUL_C  : std_logic_vector(MANT_SCALE_C -1 downto 0):= std_logic_vector(to_signed((2**MANT_SCALE_C)/ SCALE_DIV_C,MANT_SCALE_C)); --! Multiplicative scaling factor (*2^MANT_SCALE_C)

-- Maximum of constants  
constant SIGNED_16_MAX		: signed(15 downto 0) := to_signed(2**15-1,16); 
constant SIGNED_16_MIN		: signed(15 downto 0) := to_signed(-2**15,16); 

-- ================== COMPONENTS =================================================
--! @brief Signed multiplier 18 bits x 18 bits 
component my_18_mult is
	port
	(
		clock		: in std_logic ;
		dataa		: in std_logic_vector (17 downto 0);
		datab		: in std_logic_vector (17 downto 0);
		result		: out std_logic_vector (35 downto 0)
	);
end component;
--! @brief Signed divider (36 bits) / (17 bits) 
component my_36_17_div is
	port
	(
		clock		: in std_logic ;
		denom		: in std_logic_vector (16 downto 0);
		numer		: in std_logic_vector (35 downto 0);
		quotient	: out std_logic_vector (35 downto 0);
		remain		: out std_logic_vector (16 downto 0)
	);
end component;

--! @brief Signed multiplier (35 bits) x (13 bits) 
component my_37_mult is 
	port
	(
		clock		: in std_logic ;
		dataa		: in std_logic_vector (36 downto 0);
		datab		: in std_logic_vector (12 downto 0);
		result		: out std_logic_vector (49 downto 0)
	);
end component;
	
-- =================== STATES ====================================================
type hss_calcstate is (IDLE, CALC_SQUARE , DIVIDING, DIFFERENCE, SCALING); --! States supervising the main calculation steps 

-- =================== SIGNALS ===================================================
-- All variables denoted with x are inputs of operations
-- 							  y are outputs of operations 
-- The x are updated as soon as the statemachine allows it(for propper multiplication and division)
signal hss_cnt_s, hss_cnt_next_s : integer := 0;  --! counter for hss state machine supervising timing of calculations
signal vbush_s, vbush_next_s: signed(DATAWIDTH_G downto 0) := (others => '0'); --! sampled vbush_i signal 
signal vbusl_s, vbusl_next_s: signed(DATAWIDTH_G+1 downto 0) := (others => '0'); --! sampled vbusl_i signal 
signal vc_s, vc_next_s		: signed(DATAWIDTH_G+1 downto 0) := (others => '0'); --! sampled vc_i signal 
signal hss_state_s, hss_state_next_s : hss_calcstate := IDLE; -- hss states for supervision of calculation steps 

-- 
signal x10_s, x10_next_s: signed(DATAWIDTH_G+1 downto 0) := (others => '0'); --! vc_s + vbusl_s + vtd_s
signal y1_s : std_logic_vector( 2*(DATAWIDTH_G+2)-1 downto 0) := (others => '0'); --! (vc_s + vbusl_s+vtd_s)**2
     
signal x21_s, x21_next_s: signed(DATAWIDTH_G downto 0) := (others => '0'); --! vbush_s + vbusl_s
signal x20_s, x20_next_s : std_logic_vector(2*(DATAWIDTH_G+2)-1 downto 0) := (others => '0'); --! (vc_s + vbusl_s+vtd_s)**2
signal y2_s :  std_logic_vector(2*(DATAWIDTH_G+2)-1 downto 0) := (others => '0'); --!(vc_s + vbusl_s)**2/(vbush_s + vbusl_s)        	

signal x31_s, x31_next_s: signed(2*(DATAWIDTH_G+2) downto 0) := (others => '0'); --!(vc_s + vbusl_s+vtd_s)**2/(vbush_s + vbusl_s)           	
signal x30_s : signed(2*(DATAWIDTH_G+2) downto 0) := (others => '0'); --! (vc_s + vbusl_s)

signal y3_s, y3_next_s: signed(2*(DATAWIDTH_G+2) downto 0) := (others => '0'); --! (vc_s + vbusl_s) - (vc_s + vbusl_s)**2/(vbush_s + vbusl_s) 

signal x40_s, x40_next_s: signed(2*(DATAWIDTH_G+2) downto 0) := (others => '0'); --! (vc_s + vbusl_s) - (vc_s + vbusl_s)**2/(vbush_s + vbusl_s) 
signal y4_s : std_logic_vector(2*(DATAWIDTH_G+2)+MANT_SCALE_C downto 0) := (others => '0'); --! x40_s* (2**MANT_SCALE_C/SCALE_DIV_C)  

signal result_s, result_next_s : signed(36 downto 0) := (others => '0');   
signal hss_bound_s, hss_bound_next_s: signed(DATAWIDTH_G-1 downto 0) := (others => '0');  

signal phase_shift_en_vec_s : std_logic_vector(1 downto 0) := "00"; 

constant vtd_s : signed(DATAWIDTH_G+1 downto 0) := to_signed(850*(2**5)*6*NINTERLOCK_G/(10000),DATAWIDTH_G+2);  

constant X21_INIT_C : signed(DATAWIDTH_G downto 0) := to_signed(24800+2400,DATAWIDTH_G+1); --! INIT value (for Divider) vbush_s + vbusl_s

constant COMP_THRESH_C : signed(DATAWIDTH_G+1 downto 0) := to_signed(20*(2**5),DATAWIDTH_G+2); 

begin		

	--! @brief Registers for Hss state machine 
	--! @details Asynchronous reset nreset_i, no softreset 
	hss_reg : process(clk_i,nreset_i)
	begin
		if nreset_i = '0' then
			phase_shift_en_vec_s <= "00"; 
			hss_state_s <= IDLE; 
			hss_cnt_s <= 0;
			vbush_s	<= (others => '0'); 
			vbusl_s <= (others => '0'); 
			vc_s	<= (others => '0'); 
			-- calculation registers 
			x10_s <= (others => '0'); 
			x21_s <= X21_INIT_C; 
			x20_s <= (others => '0'); 
			x31_s <= (others => '0'); 
			y3_s <= (others => '0'); 
			x40_s <= (others => '0'); 
			result_s <= (others => '0'); 
			hss_bound_s <= (others => '0'); 
		elsif rising_edge(clk_i) then
			phase_shift_en_vec_s <=phase_shift_en_vec_s(0) & phase_shift_en_i; 
			hss_state_s <= hss_state_next_s; 
			hss_cnt_s <= hss_cnt_next_s; 
			vbush_s	<= vbush_next_s; 
			vbusl_s <= vbusl_next_s; 
			vc_s	<= vc_next_s; 
			-- calculation registers 
			x10_s <= x10_next_s;
			x21_s <= x21_next_s; 
			x20_s <= x20_next_s; 
			x31_s <= x31_next_s; 
			y3_s <= y3_next_s;
			x40_s <= x40_next_s; 
			result_s <= result_next_s; 
			hss_bound_s <= hss_bound_next_s; 
		end if; 
	end process; 
			
	--! @brief Hss state machine and counter logic 
	--! @details Statemachine leaves IDLE when phase_shift_en_i goes high 
	--! @details The inputs of the operators (x_) are updated with the outputs of the operators (y_) as soon
	--! @details as the time for operation is over. 
	hss_proc_logic: process(vbush_s,vbusl_s,vbush_i,vc_s,vbusl_i,vc_i,phase_shift_en_vec_s,hss_state_s, hss_cnt_s,y1_s,y2_s,y3_s,y4_s,x20_s,x31_s,x40_s,result_s) 
	begin
		-- default assignments for avoiding latches 
		vbush_next_s 	<= vbush_s; 
		vbusl_next_s	<= vbusl_s; 
		vc_next_s		<= vc_s; 
		hss_state_next_s <= hss_state_s; 
		hss_cnt_next_s <= hss_cnt_s; 
		x20_next_s <= x20_s; 
		x31_next_s <= x31_s; 
		x40_next_s <= x40_s; 
		result_next_s <= result_s; 
		
		case hss_state_s is 
			when IDLE => 
				if phase_shift_en_vec_s = "01" then 
					hss_state_next_s <= CALC_SQUARE; 
					vbush_next_s <= resize(vbush_i,DATAWIDTH_G+1); 
					vbusl_next_s <= resize(vbusl_i,DATAWIDTH_G+2); 
					vc_next_s 	 <= resize(vc_i,DATAWIDTH_G+2); 
					hss_cnt_next_s <= 0; 
				end if; 
			when CALC_SQUARE => 
				if hss_cnt_s < CNT_SQUARE_C then 
					hss_cnt_next_s <= hss_cnt_s +1; 
				else -- calculation done 
					hss_cnt_next_s <= 0; 
					hss_state_next_s <= DIVIDING ; 
					x20_next_s <= y1_s; 
				end if; 				
			when DIVIDING => 
				if hss_cnt_s < CNT_DIV_C then 
					hss_cnt_next_s <= hss_cnt_s +1; 
				else 
					hss_cnt_next_s <= 0; 
					hss_state_next_s <= DIFFERENCE;  
					x31_next_s <= resize(signed(y2_s),2*(DATAWIDTH_G+2)+1); 
				end if; 				
			when DIFFERENCE => 
				if hss_cnt_s < CNT_DIFF_C then 
					hss_cnt_next_s <= hss_cnt_s +1; 
				else 
					hss_state_next_s <= SCALING; 
					x40_next_s <= y3_s; 
					hss_cnt_next_s <= 0; 
				end if; 
				
			when SCALING => 
				if hss_cnt_s < CNT_SCL_C then 
					hss_cnt_next_s <= hss_cnt_s +1; 
				else -- Finally done 
					hss_cnt_next_s <= 0; 
					hss_state_next_s <= IDLE;  		
					result_next_s <= signed(y4_s(2*(DATAWIDTH_G+2)+MANT_SCALE_C downto MANT_SCALE_C)); 
				end if; 		
			when others => 		
			end case;  
			
			
		-- Clipping of output signal 
		if result_s > SIGNED_16_MAX then -- overflow 
			hss_bound_next_s <= SIGNED_16_MAX; 
		elsif result_s < SIGNED_16_MIN then -- underflow  
			hss_bound_next_s <= SIGNED_16_MIN; 
		else -- everything ok 
			hss_bound_next_s <= resize(signed(result_s),DATAWIDTH_G); 
		end if; 	
		
	end process; 

	--! @brief Hss arithmetic logic  
	hss_arithmetic: process(iset_i,vc_s,vbusl_s,vbush_s,x10_s,x30_s,x31_s)
	begin 	
	
		if iset_i >= COMP_THRESH_C then 
			x10_next_s <= vc_s + vbusl_s + vtd_s; 
		else 
			x10_next_s <= vc_s + vbusl_s;
		end if; 
		
		x21_next_s <= vbush_s + resize(vbusl_s,DATAWIDTH_G+1);
		
		-- third stage 
		x30_s <= resize(x10_s,2*(DATAWIDTH_G+2)+1);
		y3_next_s <= x30_s - x31_s; 
	end process;

	square_inst:  my_18_mult 
	port map (
		clock		=> clk_i,
		dataa		=> std_logic_vector(x10_s), 
		datab		=> std_logic_vector(x10_s), 
		result		=> y1_s
	);

	
	div_inst: my_36_17_div
	port map(
		clock		=> clk_i,
		denom		=> std_logic_vector(x21_s), 
		numer		=> x20_s, 
		quotient	=> y2_s,
		remain		=> open
	);
	
	scale_inst : my_37_mult
	port map(
		clock		=> clk_i, 
		dataa		=> std_logic_vector(x40_s), 
		datab		=> std_logic_vector(H_bount_fac_i),
		result		=> y4_s
	);

	-- OUTPUT ANOTAITON
	hss_bound_o <= hss_bound_s; 
			
end structural; 