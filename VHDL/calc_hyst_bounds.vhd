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
				NO_CONTROLER_G 	: integer := 2;--! Total number of controler used
                DELAY_COMP_CONSTANT : integer := 250000*(2**5); -- Constant for delay compensation in the 2nd rise. (2*H0*L*10**8) (Ho is 5A here)
                TIME_DELAY_CONSTANT : integer := 115; --! Delay/L * 2**12. By default this is 7/250 * 4096. This is used for the initial compensation for the hysteresis bounds.
				NINTERLOCK_G: natural := 50 -- number of interlock clocks 
			);		
	port( 	clk_i			: in std_logic; --! Main clock 
			nreset_i 		: in std_logic; --! Asynchronous reset 
			hyst_i			: in std_logic; --! hysteresis control signal
			vbush_i    		: in signed(DATAWIDTH_G-1 downto 0); --! V1 measured voltage 
			vbusl_i     	: in signed(DATAWIDTH_G-1 downto 0); --! V2 measured voltage
			vc_i 			: in signed(DATAWIDTH_G-1 downto 0); --! Vc measured voltage
			iset_i			: in signed(DATAWIDTH_G-1 downto 0); --! set current
            Rset_i          : in unsigned(DATAWIDTH_G-1 downto 0);--! set resistance (R*2**12)
			phase_shift_en_i: in std_logic;  --! start of calculation 		
			H_bount_fac_i	: in signed(12 downto 0); --! 1/(2*fs*L)
            Tss_bound_o     : out signed(DATAWIDTH_G-1 downto 0); --! signed output value
            Tss_bound_fall_o     : out signed(DATAWIDTH_G-1 downto 0); --! signed output value
            Tss2_bound_o     : out signed(DATAWIDTH_G-1 downto 0); --! signed output value
            Tss2_bound_fall_o: out signed(DATAWIDTH_G-1 downto 0); --! signed output value
            Hcomp_bound_rise_o    : out signed(DATAWIDTH_G-1 downto 0); --! signed output value of the initial compensation for the overshoot (V1-Vc_set)*TIME_DELAY_CONSTANT
            Hcomp_bound_fall_o    : out signed(DATAWIDTH_G-1 downto 0); --! signed output value of the initial compensation for the overshoot (V2+Vc_set)*TIME_DELAY_CONSTANT
			hss_bound_o 	: out signed(DATAWIDTH_G-1 downto 0) --! signed output value
			);
			
end calc_hyst_bounds;

architecture structural of calc_hyst_bounds is
-- ================== CONSTANTS ==================================================				
constant CNT_SQUARE_C : integer := 22; --! number of clock cycles for squaring (18 bits)
constant CNT_DIV_C	  : integer := 38; --! number of clock cycles for division (36 bits)
constant CNT_SCL_C	  : integer := 39; --! number of clock cycles for scaling (37 bits)
constant CNT_DIFF_C	  : integer := 5; --! number of clock cycles for difference 

constant DELAY_COMP_CONSTANT_SS	  : integer := DELAY_COMP_CONSTANT/10; --! L*10**8 * 2**5. This is for the compensation of the delay during the final rise of the hysteretic mode

-- scaling constants 
constant MANT_SCALE_C : integer := 13; --! Mantissa for increasing resolution in Sacling
--constant SCALE_DIV_C  : integer := 30; --! Denominator for Scaling 2*L*F_pwm = 2*250e-6*60e3
--constant SCALE_MUL_C  : std_logic_vector(MANT_SCALE_C -1 downto 0):= std_logic_vector(to_signed((2**MANT_SCALE_C)/ SCALE_DIV_C,MANT_SCALE_C)); --! Multiplicative scaling factor (*2^MANT_SCALE_C)

-- Maximum of constants  
constant SIGNED_16_MAX		: signed(15 downto 0) := to_signed(2**15-1,16); 
constant SIGNED_16_MIN		: signed(15 downto 0) := to_signed(-2**15,16); 
constant SIGNED_32_MAX		: signed(31 downto 0) := to_signed(2**30-1,32); 
constant SIGNED_32_MIN		: signed(31 downto 0) := to_signed(-2**30-1,32); 

constant TRISE_MAX          : signed(15 downto 0) := to_signed(2000,16);
constant TRISE_MIN          : signed(15 downto 0) := to_signed(100,16);

constant TFALL_MAX          : signed(15 downto 0) := to_signed(12000,16); 
constant TFALL_MIN          : signed(15 downto 0) := to_signed(200,16); 

constant VC_GUESS           :integer := 100; -- Guessed value for the initial voltage in case it is not available from the Rset

 
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

--! @brief Signed multiplier (37 bits) x (37 bits) 
component my_37_37_mult is 
	port
	(
		clock		: in std_logic ;
		dataa		: in std_logic_vector (36 downto 0);
		datab		: in std_logic_vector (36 downto 0);
		result		: out std_logic_vector (73 downto 0)
	);
end component;

--! @brief 32 Divider 
component my_integer_divider is
	port
	(
		clock		: in std_logic ;
		denom		: in std_logic_vector (31 downto 0);
		numer		: in std_logic_vector (31 downto 0);
		quotient	: out std_logic_vector (31 downto 0);
		remain		: out std_logic_vector (31 downto 0)
	);
end component;

--! @brief 16 Multiplier 
component MY_16_MULTIPLIER is
	port
	(
		clock		: in std_logic ;
		dataa		: in std_logic_vector (15 downto 0);
		datab		: in std_logic_vector (15 downto 0);
		result		: out std_logic_vector (31 downto 0)
	);
end component;

	
-- =================== STATES ====================================================
type hss_calcstate is (IDLE, CALC_SQUARE , DIVIDING, DIFFERENCE, SCALING); --! States supervising the main calculation steps 
type Tss_calcstate is (IDLE_T, VOLT_REG, CALC_DIFF , CALC_DIV, RES); --! States supervising the main calculation steps
type Tss_fall_calcstate is (IDLE_T, VOLT_REG, CALC_DIFF , CALC_DIV, RES); --! States supervising the main calculation steps 
 
type Tss2_calcstate is (IDLE_T2, VOLT_REG, CALC_DIFF2 , CALC_DIV2, MULT, RES2); --! States supervising the main calculation steps for the final compensation in hysteretic rise
type Tss2_fall_calcstate is (IDLE_T2, VOLT_REG, CALC_DIFF2 , CALC_DIV2, MULT, RES2); --! States supervising the main calculation steps for the final compensation in hysteretic rise
type Hcomp_calcstate is (IDLE, VOLT_REG, CALC_DIFF , MULT); --! State supervising the main compensation steps 


-- =================== SIGNALS ===================================================
-- All variables denoted with x are inputs of operations
-- 							  y are outputs of operations 
-- The x are updated as soon as the statemachine allows it(for propper multiplication and division)
signal hss_cnt_s, hss_cnt_next_s : integer := 0;  --! counter for hss state machine supervising timing of calculations
signal Tss_cnt_s, Tss_cnt_next_s : integer := 0;  --! counter for hss state machine supervising timing of calculations
signal Tss_cnt_fall_s, Tss_cnt_fall_next_s : integer := 0;  --! counter for hss state machine supervising timing of calculations

signal Tss2_cnt_s, Tss2_cnt_next_s : integer := 0;  --! counter for hss state machine supervising timing of calculations
signal Tss2_cnt_fall_s, Tss2_cnt_fall_next_s : integer := 0;  --! counter for hss state machine supervising timing of calculations

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

signal t0_max_s, t0_max_next_s :  signed(31 downto 0) := (others => '0');
signal t0_max_fall_s, t0_max_fall_next_s :  signed(31 downto 0) := (others => '0');

signal t0_max2_s, t0_max2_next_s    :  signed(36 downto 0) := (others => '0');
signal t0_max2_fall_s, t0_max2_fall_next_s    :  signed(36 downto 0) := (others => '0');

signal t0_comp_s, t0_comp_next_s    :  signed(73 downto 0) := (others => '0');
signal t0_comp_fall_s, t0_comp_fall_next_s    :  signed(73 downto 0) := (others => '0');

signal yRise_Div_s,yRise_Div_fall_s, yRise2_Div_s, yRise2_Div_fall_s: std_logic_vector(31 downto 0):= (others => '0');

signal x31_s, x31_next_s: signed(2*(DATAWIDTH_G+2) downto 0) := (others => '0'); --!(vc_s + vbusl_s+vtd_s)**2/(vbush_s + vbusl_s)           	
signal x30_s : signed(2*(DATAWIDTH_G+2) downto 0) := (others => '0'); --! (vc_s + vbusl_s)

signal y3_s, y3_next_s: signed(2*(DATAWIDTH_G+2) downto 0) := (others => '0'); --! (vc_s + vbusl_s) - (vc_s + vbusl_s)**2/(vbush_s + vbusl_s) 

signal x40_s, x40_next_s: signed(2*(DATAWIDTH_G+2) downto 0) := (others => '0'); --! (vc_s + vbusl_s) - (vc_s + vbusl_s)**2/(vbush_s + vbusl_s) 
signal y4_s : std_logic_vector(2*(DATAWIDTH_G+2)+MANT_SCALE_C downto 0) := (others => '0'); --! x40_s* (2**MANT_SCALE_C/SCALE_DIV_C)  

signal result_s, result_next_s : signed(36 downto 0) := (others => '0');
signal Tresult_s, Tresult_next_s : signed(35 downto 0) := (others => '0');
signal Tresult_fall_s, Tresult_fall_next_s : signed(35 downto 0) := (others => '0');   
   
signal Tresult2_s, Tresult2_next_s : signed(35 downto 0) := (others => '0');
signal Tresult2_fall_s, Tresult2_fall_next_s : signed(35 downto 0) := (others => '0');      
   
signal Tss_bound_s, Tss_bound_next_s: signed(DATAWIDTH_G-1 downto 0) := (others => '0');
signal Tss_bound_fall_s, Tss_bound_fall_next_s: signed(DATAWIDTH_G-1 downto 0) := (others => '0');

signal Tss2_bound_s, Tss2_bound_next_s: signed(DATAWIDTH_G-1 downto 0) := (others => '0');
signal Tss2_bound_fall_s, Tss2_bound_fall_next_s: signed(DATAWIDTH_G-1 downto 0) := (others => '0');    
    
signal hss_bound_s, hss_bound_next_s: signed(DATAWIDTH_G-1 downto 0) := (others => '0');  

signal phase_shift_en_vec_s : std_logic_vector(1 downto 0) := "00"; 
signal delay_shift_s : std_logic_vector(1 downto 0) := "00"; 
signal hyst_s : std_logic_vector(1 downto 0) := "00"; 

signal delay_shift_i, delay_shift_next_i : std_logic := '0';

signal V1_r_s, V1_r_next_s, V2_r_fall_s, V2_r_fall_next_s, V1_r2_s, V1_r2_next_s, V2_r2_fall_s, V2_r2_fall_next_s, V1_comp_s, V1_comp_next_s, V2_comp_s, V2_comp_next_s   : signed(DATAWIDTH_G-1 downto 0) := (others => '0'); --! sampled V1 signal

signal Vc_r_s, Vc_r_next_s, Vc_r_fall_s, Vc_r_fall_next_s, Vc_r2_s, Vc_r2_next_s, Vc_r2_fall_s, Vc_r2_fall_next_s : signed(DATAWIDTH_G-1 downto 0) := (others => '0'); --! sampled Vc signal 

signal vc_set_s		: std_logic_vector(31 downto 0):= (others => '0'); --! calculated set voltage
signal Vc_comp_s, Vc_comp_next_s : signed(2*DATAWIDTH_G-1 downto 0) := (others => '0');

signal xRise_s, xRise_next_s, xRise_fall_s, xRise_fall_next_s, xRise2_s, xRise2_next_s, xRise2_fall_s, xRise2_fall_next_s   : signed(31 downto 0) := (others => '0'); --! xRise_s = (Vbush - Vc)
signal yRise_s,yRise_fall_s, yRise2_s, yRise2_fall_s 	: signed(DATAWIDTH_G downto 0) := (others => '0');
signal yRise2_Div2_s,yRise2_Div2_fall_s  	: std_logic_vector(73 downto 0) := (others => '0');

signal Tss_state_s, Tss_state_next_s : Tss_calcstate := IDLE_T; -- Tss states for supervision of calculation steps
signal Tss_state_fall_s, Tss_state_fall_next_s : Tss_calcstate := IDLE_T; -- Tss states for supervision of calculation steps  
  
signal Tss2_state_s, Tss2_state_next_s : Tss2_calcstate := IDLE_T2; -- Tss2 states for supervision of calculation steps
signal Tss2_state_fall_s, Tss2_state_fall_next_s : Tss2_fall_calcstate := IDLE_T2; -- Tss2 states for supervision of calculation steps  
 
constant vtd_s : signed(DATAWIDTH_G+1 downto 0) := to_signed(850*(2**5)*6*NINTERLOCK_G/(10000),DATAWIDTH_G+2);  

constant X21_INIT_C : signed(DATAWIDTH_G downto 0) := to_signed(24800+2400,DATAWIDTH_G+1); --! INIT value (for Divider) vbush_s + vbusl_s

constant COMP_THRESH_C : signed(DATAWIDTH_G+1 downto 0) := to_signed(20*(2**5),DATAWIDTH_G+2); 

--- Signals for the compensation of the initial rise
signal Hcomp_state_s, Hcomp_state_next_s : Hcomp_calcstate := IDLE; -- Tss states for supervision of calculation steps  
signal Tcomp_cnt_s, Tcomp_cnt_next_s : integer := 0;  --! counter for hss state machine supervising timing of calculations

signal xComp_r_s, xComp_r_next_s, xComp_f_s, xComp_f_next_s: signed(DATAWIDTH_G-1 downto 0) := (others => '0'); --! vbush + vcset and vbusl+vcset
signal Hcomp_rise_result_s, Hcomp_rise_result_next_s, Hcomp_fall_result_s, Hcomp_fall_result_next_s: signed(2*DATAWIDTH_G-1 downto 0) := (others => '0'); --! 
signal yComp_mult_r_s,  yComp_mult_f_s : std_logic_vector(2*DATAWIDTH_G-1 downto 0) := (others => '0'); --! multiplication result
signal yComp_r_s,  yComp_f_s : signed(DATAWIDTH_G downto 0) := (others => '0'); --! difference result
signal Hcomp_rise_s,Hcomp_fall_s,Hcomp_rise_next_s,Hcomp_fall_next_s : signed(DATAWIDTH_G-1 downto 0) := (others => '0'); --! 
signal iset_total_s, iset_total_next_s :  signed(DATAWIDTH_G-1 downto 0):= (others => '0'); --! total set current
begin		

	--! @brief Registers for Hss state machine 
	--! @details Asynchronous reset nreset_i, no softreset 
	hss_reg : process(clk_i,nreset_i)
	begin
		if nreset_i = '0' then
			phase_shift_en_vec_s <= "00";
            delay_shift_s  <= "00";
            hyst_s         <= "00";
            delay_shift_i  <= '0';
			hss_state_s <= IDLE;
            Tss_state_s <= IDLE_T;
            Tss_state_fall_s <= IDLE_T;
            Tss2_state_s <= IDLE_T2;
            Tss2_state_fall_s <= IDLE_T2;
            Tss_cnt_s <= 0;
            Tss_cnt_fall_s <= 0;
            Tss2_cnt_s <= 0;
            Tss2_cnt_fall_s <= 0;    
			hss_cnt_s <= 0;
			vbush_s	<= (others => '0'); 
			vbusl_s <= (others => '0'); 
            V1_r_s	<= (others => '0'); 
			Vc_r_s <= (others => '0');
            V2_r_fall_s	<= (others => '0'); 
			Vc_r_fall_s <= (others => '0');
            V1_r2_s	<= (others => '0'); 
			Vc_r2_s <= (others => '0');
            V2_r2_fall_s	<= (others => '0'); 
			Vc_r2_fall_s <= (others => '0');  
			vc_s	<= (others => '0'); 
			-- calculation registers 
			x10_s <= (others => '0'); 
			x21_s <= X21_INIT_C; 
			x20_s <= (others => '0'); 
			x31_s <= (others => '0'); 
			y3_s <= (others => '0'); 
			x40_s <= (others => '0'); 
            xRise_s <= (others => '0');
            xRise_fall_s <= (others => '0');
            xRise2_s <= (others => '0');
            xRise2_fall_s <= (others => '0');    
			result_s <= (others => '0'); 
            Tresult_s <= (others => '0');
            Tresult_fall_s <= (others => '0');
            Tresult2_s <= (others => '0');
            Tresult2_fall_s <= (others => '0');    
			Tss_bound_s <= (others => '0');
			Tss_bound_fall_s <= (others => '0');
			Tss2_bound_s <= (others => '0');
            Tss2_bound_fall_s <= (others => '0');
			hss_bound_s <= (others => '0');
            -- signals for the compensation:
            xComp_r_s   <= (others => '0');
            xComp_f_s   <= (others => '0');
            Hcomp_rise_result_s <= (others => '0');
            Hcomp_fall_result_s <= (others => '0');
            Hcomp_rise_s    <= (others => '0');
            Hcomp_fall_s    <= (others => '0');
            Tcomp_cnt_s <=  0;
            Hcomp_state_s   <= IDLE;
            V1_comp_s   <= (others => '0');
            V2_comp_s   <= (others => '0');
            Vc_comp_s   <= (others => '0');
            iset_total_s   <= (others => '0');
		elsif rising_edge(clk_i) then
			phase_shift_en_vec_s <=phase_shift_en_vec_s(0) & phase_shift_en_i;
            delay_shift_s  <= delay_shift_s(0) & delay_shift_i;
            hyst_s  <= hyst_s(0) & hyst_i; 
			hss_state_s <= hss_state_next_s;
            Tss_state_s <= Tss_state_next_s;
            Tss_state_fall_s <= Tss_state_fall_next_s;
            Tss_cnt_s <= Tss_cnt_next_s;
            Tss_cnt_fall_s <= Tss_cnt_fall_next_s;
            Tss2_state_s <= Tss2_state_next_s;
            Tss2_state_fall_s <= Tss2_state_fall_next_s;
            Tss2_cnt_s <= Tss2_cnt_next_s;
            Tss2_cnt_fall_s <= Tss2_cnt_fall_next_s;             
			hss_cnt_s <= hss_cnt_next_s; 
			vbush_s	<= vbush_next_s; 
			vbusl_s <= vbusl_next_s;
            V1_r_s	<= V1_r_next_s;
			Vc_r_s <= Vc_r_next_s;
            V2_r_fall_s	<= V2_r_fall_next_s;
			Vc_r_fall_s <= Vc_r_fall_next_s;
            V1_r2_s	<= V1_r2_next_s;
			Vc_r2_s <= Vc_r2_next_s;
            V2_r2_fall_s	<= V2_r2_fall_next_s;
			Vc_r2_fall_s <= Vc_r2_fall_next_s;
			vc_s	<= vc_next_s; 
			-- calculation registers 
			x10_s <= x10_next_s;
			x21_s <= x21_next_s; 
			x20_s <= x20_next_s; 
			x31_s <= x31_next_s; 
			y3_s <= y3_next_s;
			x40_s <= x40_next_s; 
            xRise_s <= xRise_next_s;
            xRise_fall_s <= xRise_fall_next_s;
            xRise2_s <= xRise2_next_s;
            xRise2_fall_s <= xRise2_fall_next_s;   
            Tresult_s <= Tresult_next_s;
            Tresult_fall_s <= Tresult_fall_next_s;
            Tresult2_s <= Tresult2_next_s;
            Tresult2_fall_s <= Tresult2_fall_next_s;
			result_s <= result_next_s;
            Tss_bound_s <= Tss_bound_next_s;
            Tss_bound_fall_s <= Tss_bound_fall_next_s;
            Tss2_bound_s <= Tss2_bound_next_s;
            Tss2_bound_fall_s <= Tss2_bound_fall_next_s;
            t0_max_s <= t0_max_next_s;
            t0_max_fall_s <= t0_max_fall_next_s;
            t0_max2_s <= t0_max2_next_s;
            t0_max2_fall_s <= t0_max2_fall_next_s;
            t0_comp_s <= t0_comp_next_s;
            t0_comp_fall_s <= t0_comp_fall_next_s;
            delay_shift_i <= delay_shift_next_i;
			hss_bound_s <= hss_bound_next_s; 
            ------ Signals for compensation
            xComp_r_s   <= xComp_r_next_s;
            xComp_f_s   <= xComp_f_next_s;
            Hcomp_rise_result_s <= Hcomp_rise_result_next_s;
            Hcomp_fall_result_s <= Hcomp_fall_result_next_s;
            Hcomp_rise_s    <= Hcomp_rise_next_s;
            Hcomp_fall_s    <= Hcomp_fall_next_s;
            Tcomp_cnt_s <= Tcomp_cnt_next_s;
            Hcomp_state_s   <= Hcomp_state_next_s;
            V1_comp_s   <= V1_comp_next_s;
            V2_comp_s   <= V2_comp_next_s;
            iset_total_s <= iset_total_next_s;
            Vc_comp_s   <= Vc_comp_next_s;
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
        delay_shift_next_i <= delay_shift_i;
		
		case hss_state_s is 
			when IDLE => 
				if phase_shift_en_vec_s = "01" then 
					hss_state_next_s <= CALC_SQUARE; 
					vbush_next_s <= resize(vbush_i,DATAWIDTH_G+1); 
					vbusl_next_s <= resize(vbusl_i,DATAWIDTH_G+2);
                    if Rset_i = 0 then
                        vc_next_s <= resize(vc_i,DATAWIDTH_G+2);
                    else
                        vc_next_s <= resize(signed(vc_set_s)/2**12,DATAWIDTH_G+2);
                    end if;
					hss_cnt_next_s <= 0;
                    delay_shift_next_i <= '0'; 	 
				end if; 
			when CALC_SQUARE => 
				if hss_cnt_s < CNT_SQUARE_C then 
					hss_cnt_next_s <= hss_cnt_s +1; 
				else -- calculation done 
					hss_cnt_next_s <= 0; 
					hss_state_next_s <= DIVIDING ; 
					x20_next_s <= y1_s; 
                    delay_shift_next_i <= '0'; 	 
				end if; 				
			when DIVIDING => 
				if hss_cnt_s < CNT_DIV_C then 
					hss_cnt_next_s <= hss_cnt_s +1; 
				else 
					hss_cnt_next_s <= 0; 
					hss_state_next_s <= DIFFERENCE;  
					x31_next_s <= resize(signed(y2_s),2*(DATAWIDTH_G+2)+1);
                    delay_shift_next_i <= '0'; 	  
				end if; 				
			when DIFFERENCE => 
				if hss_cnt_s < CNT_DIFF_C then 
					hss_cnt_next_s <= hss_cnt_s +1; 
				else 
					hss_state_next_s <= SCALING; 
					x40_next_s <= y3_s; 
					hss_cnt_next_s <= 0;
                    delay_shift_next_i <= '0'; 	 
				end if; 
				
			when SCALING => 
				if hss_cnt_s < CNT_SCL_C then 
					hss_cnt_next_s <= hss_cnt_s + 1; 
				else -- Finally done 
					hss_cnt_next_s <= 0; 
					hss_state_next_s <= IDLE;
                    delay_shift_next_i <= '1'; 		
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

	--! @brief Implemented by G. Tsolaridis
	--! @brief Tss state machine and counter logic 
	--! @details Statemachine leaves IDLE when phase_shift_en_i goes high 
	--! @details The inputs of the operators (x_) are updated with the outputs of the operators (y_) as soon
	--! @details as the time for operation is over. 
	Tss_proc_logic: process(phase_shift_en_vec_s,Tss_state_s, Tss_cnt_s, xRise_s, Tresult_s, Vc_r_s, V1_r_s, yRise_s, yRise_Div_s, t0_max_s, vbush_i, vc_i, Vc_r_next_s, V1_r_next_s, vc_set_s)
	begin
		-- default assignments for avoiding latches 
		Vc_r_next_s 	<= Vc_r_s;
		V1_r_next_s 	<= V1_r_s;  
		Tss_state_next_s <= Tss_state_s; 
		Tss_cnt_next_s <= Tss_cnt_s; 
		xRise_next_s <= xRise_s; 
		Tresult_next_s <= Tresult_s;
        t0_max_next_s <= t0_max_s; 
		
		case Tss_state_s is 
			when IDLE_T => 
				if phase_shift_en_vec_s = "01" then 
					Tss_state_next_s <= CALC_DIFF;
					V1_r_next_s <= vbush_i; 
                    if Rset_i = 0 then
                        Vc_r_next_s <= resize(vc_i,16);
                    else
                        Vc_r_next_s <= resize(signed(vc_set_s)/2**12,16);
                    end if;
					Tss_cnt_next_s <= 0; 
				end if; 
			when CALC_DIFF => 
				if Tss_cnt_s < CNT_DIFF_C then 
					Tss_cnt_next_s <= Tss_cnt_s +1;
				else -- calculation done 
					Tss_cnt_next_s <= 0; 
                    xRise_next_s <= resize(yRise_s,32);
					Tss_state_next_s <= CALC_DIV; 
				end if; 				
			when CALC_DIV => 
				if Tss_cnt_s < CNT_DIV_C then 
					Tss_cnt_next_s <= Tss_cnt_s +1;
				else 
					Tss_cnt_next_s <= 0; 
                    t0_max_next_s <=  signed(yRise_Div_s); 
					Tss_state_next_s <= RES;
                end if; 

            --- This stage passes the result to Tresult_next_s and resizes to a signed 36 bits.
            when RES => 
				if Tss_cnt_s < 1 then 
					Tss_cnt_next_s <= Tss_cnt_s +1;
				else 
					Tss_cnt_next_s <= 0; 
					Tss_state_next_s <= IDLE_T;
                    Tresult_next_s <= resize(t0_max_s,36); 				
                end if; 
            
			when others =>
			end case;  			

		-- Clipping of output signal 
		if Tresult_s > TRISE_MAX then -- overflow 
			Tss_bound_next_s <= TRISE_MAX; 
		elsif Tresult_s < TRISE_MIN then -- underflow  
			Tss_bound_next_s <= TRISE_MIN; 
		else -- everything ok 
			Tss_bound_next_s <= resize(signed(Tresult_s),DATAWIDTH_G); 
		end if; 	
		
	end process; 

	--! @brief Implemented by G. Tsolaridis
	--! @brief Tss_fall state machine and counter logic 
	--! @details Statemachine leaves IDLE when phase_shift_en_i goes high 
	--! @details The inputs of the operators (x_) are updated with the outputs of the operators (y_) as soon
	--! @details as the time for operation is over. 
	Tss_fall_proc_logic: process(phase_shift_en_vec_s,Tss_state_fall_s, Tss_cnt_fall_s, xRise_fall_s, Tresult_fall_s, Vc_r_fall_s, V2_r_fall_s, yRise_fall_s, yRise_Div_fall_s, t0_max_fall_s, vbush_i, vc_i, Vc_r_fall_next_s, V2_r_fall_next_s, vc_set_s)
	begin
		-- default assignments for avoiding latches 
		Vc_r_fall_next_s 	<= Vc_r_fall_s; 
		V2_r_fall_next_s 	<= V2_r_fall_s;  
		Tss_state_fall_next_s <= Tss_state_fall_s; 
		Tss_cnt_fall_next_s <= Tss_cnt_fall_s; 
		xRise_fall_next_s <= xRise_fall_s; 
		Tresult_fall_next_s <= Tresult_fall_s;
        t0_max_fall_next_s <= t0_max_fall_s; 
		
		case Tss_state_fall_s is 
			when IDLE_T => 
				--if phase_shift_en_vec_s = "01" then 
					Tss_state_fall_next_s <= CALC_DIFF;
					V2_r_fall_next_s <= vbusl_i; 
					if Rset_i = 0 then
                        Vc_r_fall_next_s <= resize(vc_i,16);
                    else
                        Vc_r_fall_next_s <= resize(signed(vc_set_s)/2**12,16);
                    end if;
					Tss_cnt_fall_next_s <= 0; 
				--end if; 
			when CALC_DIFF => 
				if Tss_cnt_fall_s < CNT_DIFF_C then 
                    yRise_fall_s <= resize(V2_r_fall_next_s,DATAWIDTH_G+1) + resize(Vc_r_fall_next_s,DATAWIDTH_G+1);  
					Tss_cnt_fall_next_s <= Tss_cnt_fall_s +1;
				else -- calculation done 
					Tss_cnt_fall_next_s <= 0; 
                    xRise_fall_next_s <= resize(yRise_fall_s,32);
					Tss_state_fall_next_s <= CALC_DIV; 
				end if; 				
			when CALC_DIV => 
				if Tss_cnt_fall_s < CNT_DIV_C then 
					Tss_cnt_fall_next_s <= Tss_cnt_fall_s +1;
				else 
					Tss_cnt_fall_next_s <= 0; 
                    t0_max_fall_next_s <=  signed(yRise_Div_fall_s); 
					Tss_state_fall_next_s <= RES;
                end if; 
            --- This stage passes the result to Tresult_next_s and resizes to a signed 36 bits.
            when RES => 
				if Tss_cnt_fall_s < 1 then 
					Tss_cnt_fall_next_s <= Tss_cnt_fall_s +1;
				else 
					Tss_cnt_fall_next_s <= 0; 
					Tss_state_fall_next_s <= IDLE_T;
                    Tresult_fall_next_s <= resize(t0_max_fall_s,36); 				
                end if; 
            
			when others =>
			end case;  			

		-- Clipping of output signal 
		if Tresult_fall_s > TFALL_MAX then -- overflow 
			Tss_bound_fall_next_s <= TFALL_MAX; 
		elsif Tresult_fall_s < TFALL_MIN then -- underflow  
			Tss_bound_fall_next_s <= TFALL_MIN; 
		else -- everything ok 
			Tss_bound_fall_next_s <= resize(signed(Tresult_fall_s),DATAWIDTH_G); 
		end if; 	
		
	end process; 

--! @brief Implemented by G. Tsolaridis
	--! @brief Tss state machine and counter logic 
	--! @details Statemachine leaves IDLE when phase_shift_en_i goes high 
	--! @details The inputs of the operators (x_) are updated with the outputs of the operators (y_) as soon
	--! @details as the time for operation is over. 
	Tss2_proc_logic: process(delay_shift_s,Tss2_state_s, Tss2_cnt_s,Tresult2_s, xRise2_s, Vc_r2_s, V1_r2_s, vbush_i, vc_i, yRise2_s, yRise2_Div_s, yRise2_Div2_s, t0_comp_s, t0_max2_s, Vc_r2_next_s, V1_r2_next_s, vc_set_s)
	begin
		-- default assignments for avoiding latches 
		Vc_r2_next_s 	<= Vc_r2_s; 
		V1_r2_next_s 	<= V1_r2_s;  
		Tss2_state_next_s <= Tss2_state_s; 
		Tss2_cnt_next_s <= Tss2_cnt_s; 
		xRise2_next_s <= xRise2_s; 
		Tresult2_next_s <= Tresult2_s;
        t0_max2_next_s <= t0_max2_s;
        t0_comp_next_s <= t0_comp_s;    

		case Tss2_state_s is 
			when IDLE_T2 => 
				if delay_shift_s = "01" then 
					Tss2_state_next_s <= CALC_DIFF2;
					V1_r2_next_s <= vbush_i; 
					if Rset_i = 0  then
                        Vc_r2_next_s <= resize(vc_i,16);
                    else
                        Vc_r2_next_s <= resize(signed(vc_set_s)/2**12,16);
                    end if;
					Tss2_cnt_next_s <= 0;
				end if; 
			when CALC_DIFF2 => 
				if Tss2_cnt_s < CNT_DIFF_C then 
					Tss2_cnt_next_s <= Tss2_cnt_s +1;
				else -- calculation done 
					Tss2_cnt_next_s <= 0; 
                    xRise2_next_s <= resize(yRise2_s,32);
					Tss2_state_next_s <= CALC_DIV2; 
				end if; 				
			when CALC_DIV2 => 
				if Tss2_cnt_s < CNT_DIV_C then 
					Tss2_cnt_next_s <= Tss2_cnt_s +1;
				else 
					Tss2_cnt_next_s <= 0; 
                    t0_max2_next_s <=  resize(signed(yRise2_Div_s),37); --DELAY_COMP_CONSTANT_SS/to_integer(xRise2_s); 
					Tss2_state_next_s <= MULT;
                end if; 
	 				
			when MULT => 
				if Tss2_cnt_s < CNT_SQUARE_C then 
					Tss2_cnt_next_s <= Tss2_cnt_s +1;
				else 
					Tss2_cnt_next_s <= 0; 
                    t0_comp_next_s <=  signed(yRise2_Div2_s); --hss *  DELAY_COMP_CONSTANT_SS/to_integer(xRise2_s);
					Tss2_state_next_s <= RES2;
                end if; 

            --- This stage passes the result to Tresult_next_s and resizes to a signed 36 bits.
            when RES2 => 
				if Tss2_cnt_s < 1 then 
					Tss2_cnt_next_s <= Tss2_cnt_s +1;
				else 
					Tss2_cnt_next_s <= 0; 
					Tss2_state_next_s <= IDLE_T2;
                    Tresult2_next_s <= resize(t0_comp_s/16,36);
                end if; 
            
			when others =>
			end case;  			

		-- Clipping of output signal 
		if Tresult2_s > TRISE_MAX then -- overflow 
			Tss2_bound_next_s <= TRISE_MAX; 
		elsif Tresult2_s < TRISE_MIN then -- underflow  
			Tss2_bound_next_s <= TRISE_MIN; 
		else -- everything ok 
			Tss2_bound_next_s <= resize(signed(Tresult2_s),DATAWIDTH_G); 
		end if; 	
		
	end process; 


--! @brief Implemented by G. Tsolaridis
	--! @brief Tss state machine and counter logic 
	--! @details Statemachine leaves IDLE when phase_shift_en_i goes high 
	--! @details The inputs of the operators (x_) are updated with the outputs of the operators (y_) as soon
	--! @details as the time for operation is over. 
	Tss2_fall_proc_logic: process(delay_shift_s,Tss2_state_fall_s, Tss2_cnt_fall_s,Tresult2_fall_s, xRise2_fall_s, Vc_r2_fall_s, V2_r2_fall_s, vbusl_i, vc_i, yRise2_fall_s, yRise2_Div_fall_s, yRise2_Div2_fall_s, t0_comp_fall_s, t0_max2_fall_s, vc_set_s)
	begin
		-- default assignments for avoiding latches 
		Vc_r2_fall_next_s 	<= Vc_r2_fall_s; 
		V2_r2_fall_next_s 	<= V2_r2_fall_s;  
		Tss2_state_fall_next_s <= Tss2_state_fall_s; 
		Tss2_cnt_fall_next_s <= Tss2_cnt_fall_s; 
		xRise2_fall_next_s <= xRise2_fall_s; 
		Tresult2_fall_next_s <= Tresult2_fall_s;
        t0_max2_fall_next_s <= t0_max2_fall_s;
        t0_comp_fall_next_s <= t0_comp_fall_s;    

		case Tss2_state_fall_s is 
			when IDLE_T2 => 
				if delay_shift_s = "01" then 
					Tss2_state_fall_next_s <= CALC_DIFF2;
					V2_r2_fall_next_s <= vbusl_i; 
					if Rset_i = 0  then
                        Vc_r2_fall_next_s <= resize(vc_i,16);
                    else
                        Vc_r2_fall_next_s <= resize(signed(vc_set_s)/2**12,16);
                    end if;
					Tss2_cnt_fall_next_s <= 0;
				end if; 
			when CALC_DIFF2 => 
				if Tss2_cnt_fall_s < CNT_DIFF_C then 
					Tss2_cnt_fall_next_s <= Tss2_cnt_fall_s +1;
				else -- calculation done 
					Tss2_cnt_fall_next_s <= 0; 
                    xRise2_fall_next_s <= resize(yRise2_fall_s,32);
					Tss2_state_fall_next_s <= CALC_DIV2; 
				end if; 				
			when CALC_DIV2 => 
				if Tss2_cnt_fall_s < CNT_DIV_C then 
					Tss2_cnt_fall_next_s <= Tss2_cnt_fall_s +1;
				else 
					Tss2_cnt_fall_next_s <= 0; 
                    t0_max2_fall_next_s <=  resize(signed(yRise2_Div_fall_s),37); --DELAY_COMP_CONSTANT_SS/to_integer(xRise2_s); 
					Tss2_state_fall_next_s <= MULT;
                end if; 
	 				
			when MULT => 
				if Tss2_cnt_fall_s < CNT_SQUARE_C then 
					Tss2_cnt_fall_next_s <= Tss2_cnt_fall_s +1;
				else 
					Tss2_cnt_fall_next_s <= 0; 
                    t0_comp_fall_next_s <=  signed(yRise2_Div2_fall_s); --hss *  DELAY_COMP_CONSTANT_SS/to_integer(xRise2_s);
					Tss2_state_fall_next_s <= RES2;
                end if; 

            --- This stage passes the result to Tresult_next_s and resizes to a signed 36 bits.
            when RES2 => 
				if Tss2_cnt_fall_s < 1 then 
					Tss2_cnt_fall_next_s <= Tss2_cnt_fall_s +1;
				else 
					Tss2_cnt_fall_next_s <= 0; 
					Tss2_state_fall_next_s <= IDLE_T2;
                    Tresult2_fall_next_s <= resize(t0_comp_fall_s/16,36);
                end if; 
            
			when others =>
			end case;  			

		-- Clipping of output signal 
		if Tresult2_fall_s > TFALL_MAX then -- overflow 
			Tss2_bound_fall_next_s <= TFALL_MAX ; 
		elsif Tresult2_fall_s < TFALL_MIN then -- underflow  
			Tss2_bound_fall_next_s <= TFALL_MIN; 
		else -- everything ok 
			Tss2_bound_fall_next_s <= resize(signed(Tresult2_fall_s),DATAWIDTH_G); 
		end if; 	
		
	end process; 

-- Initial compensation adjustment for rise and for fall.

	H_comp_proc_logic: process(hyst_s, Rset_i, Hcomp_state_s, Tcomp_cnt_s, xComp_r_s, xComp_f_s, Hcomp_rise_s, Vc_comp_s, V1_comp_s, V2_comp_s, vbush_i, vbusl_i, vc_set_s, Hcomp_fall_s, yComp_r_s, yComp_f_s, Hcomp_rise_result_s, Hcomp_fall_result_s)
	begin
		-- default assignments for avoiding latches 
		Vc_comp_next_s 	<= Vc_comp_s; 
		V2_comp_next_s 	<= V2_comp_s;
        V1_comp_next_s 	<= V1_comp_s;  
        Hcomp_state_next_s <= Hcomp_state_s;
        xComp_r_next_s     <= xComp_r_s;
        xComp_f_next_s     <= xComp_f_s;
        Tcomp_cnt_next_s   <= Tcomp_cnt_s;
        Hcomp_rise_result_next_s <= Hcomp_rise_result_s;
        Hcomp_fall_result_next_s <= Hcomp_fall_result_s;
        Hcomp_rise_next_s <= Hcomp_rise_s; 
        Hcomp_fall_next_s <= Hcomp_fall_s;

		case Hcomp_state_s is 
			when IDLE => 
				if hyst_s = "01" then 
					Hcomp_state_next_s <= VOLT_REG;
					Tcomp_cnt_next_s <= 0;
				end if;

            when VOLT_REG => 
                if Tcomp_cnt_s < 10 then 
					Tcomp_cnt_next_s <= Tcomp_cnt_s +1;
				else -- calculation done 
					V2_comp_next_s <= vbusl_i;
                    V1_comp_next_s <= vbush_i;  
					if to_integer(Rset_i) = 0  then
						Vc_comp_next_s <= to_signed(VC_GUESS*2**5,32);--! CAREFUL!! Since it is not available we have to guess the output voltage at the first rise
                    else
						Vc_comp_next_s <= signed(vc_set_s)/2**12;
                    end if;
                    Hcomp_state_next_s <= CALC_DIFF;
                    Tcomp_cnt_next_s <= 0;
                end if;

			when CALC_DIFF => 
				if Tcomp_cnt_s < CNT_DIFF_C then 
					Tcomp_cnt_next_s <= Tcomp_cnt_s +1;
				else -- calculation done 
					Tcomp_cnt_next_s <= 0; 
                    xComp_r_next_s  <= resize(yComp_r_s,16);
                    xComp_f_next_s <= resize(yComp_f_s,16);
					Hcomp_state_next_s <= MULT;
				end if;
			when MULT => 
				if Tcomp_cnt_s < CNT_SQUARE_C then 
					Tcomp_cnt_next_s <= Tcomp_cnt_s + 1;
				else 
					Tcomp_cnt_next_s <= 0; 
                    Hcomp_rise_result_next_s <= signed(yComp_mult_r_s)/2**12;
                    Hcomp_fall_result_next_s <= signed(yComp_mult_f_s)/2**12;
					Hcomp_state_next_s <= IDLE;
                end if; 
			when others =>
			end case;
  			
		-- Clipping of output signal 
		if Hcomp_rise_result_s > SIGNED_16_MAX then -- overflow 
			Hcomp_rise_next_s <= SIGNED_16_MAX; 
		elsif Hcomp_rise_result_s < SIGNED_16_MIN then -- underflow  
			Hcomp_rise_next_s <= SIGNED_16_MIN; 
		else -- everything ok 
			Hcomp_rise_next_s <= resize(Hcomp_rise_result_s,DATAWIDTH_G); 
		end if; 
	
		-- Clipping of output signal 
		if Hcomp_fall_result_s > SIGNED_16_MAX then -- overflow 
			Hcomp_fall_next_s <= SIGNED_16_MAX; 
		elsif Hcomp_fall_result_s < SIGNED_16_MIN then -- underflow  
			Hcomp_fall_next_s <=  SIGNED_16_MIN;  
		else -- everything ok 
			Hcomp_fall_next_s <= resize(Hcomp_fall_result_s,DATAWIDTH_G); 
		end if; 

  end process;	
	
	--! @brief Hss arithmetic logic  
	hss_arithmetic: process(iset_i,vc_s,vbusl_s,vbush_s,x10_s,x30_s,x31_s,Vc_r2_s,V1_r2_s, hyst_i,Vc_comp_s, V1_comp_s, V2_comp_s)
	begin 	
	
		if iset_i >= COMP_THRESH_C then 
			x10_next_s <= vc_s + vbusl_s + vtd_s; 
		else 
			x10_next_s <= vc_s + vbusl_s;
		end if; 
		
		x21_next_s <= vbush_s + resize(vbusl_s,DATAWIDTH_G+1);

        yRise_s <= resize(V1_r_next_s,DATAWIDTH_G+1) - resize(Vc_r_next_s,DATAWIDTH_G+1);
        yRise2_s <= resize(V1_r2_next_s,DATAWIDTH_G+1) - resize(Vc_r2_next_s,DATAWIDTH_G+1);
        yRise2_fall_s <= resize(V2_r2_fall_next_s,DATAWIDTH_G+1) + resize(Vc_r2_next_s,DATAWIDTH_G+1);

        yComp_r_s <= resize(V1_comp_s,DATAWIDTH_G+1) - resize(Vc_comp_s,DATAWIDTH_G+1);
        yComp_f_s <= resize(V2_comp_s,DATAWIDTH_G+1) + resize(Vc_comp_s,DATAWIDTH_G+1);
  
		-- third stage 
		x30_s <= resize(x10_s,2*(DATAWIDTH_G+2)+1);
		y3_next_s <= x30_s - x31_s; 

        iset_total_next_s <= resize(iset_i*to_signed(NO_CONTROLER_G,16),16);

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
	
	RiseDiv_inst: my_integer_divider
	port map(
		clock		=> clk_i,
		denom		=> std_logic_vector(xRise_s), 
		numer		=> std_logic_vector(to_signed(DELAY_COMP_CONSTANT, 32)), 
		quotient	=> yRise_Div_s,
		remain		=> open
	);

	FallDiv_inst: my_integer_divider
	port map(
		clock		=> clk_i,
		denom		=> std_logic_vector(xRise_fall_s), 
		numer		=> std_logic_vector(to_signed(DELAY_COMP_CONSTANT, 32)), 
		quotient	=> yRise_Div_fall_s,
		remain		=> open
	);

	RiseDiv2_inst: my_integer_divider
	port map(
		clock		=> clk_i,
		denom		=> std_logic_vector(xRise2_s), 
		numer		=> std_logic_vector(to_signed(DELAY_COMP_CONSTANT_SS, 32)), 
		quotient	=> yRise2_Div_s,
		remain		=> open
	);

	FallDiv2_inst: my_integer_divider
	port map(
		clock		=> clk_i,
		denom		=> std_logic_vector(xRise2_fall_s), 
		numer		=> std_logic_vector(to_signed(DELAY_COMP_CONSTANT_SS, 32)), 
		quotient	=> yRise2_Div_fall_s,
		remain		=> open
	);
        
	scale_inst : my_37_mult
	port map(
		clock		=> clk_i, 
		dataa		=> std_logic_vector(x40_s), 
		datab		=> std_logic_vector(H_bount_fac_i),
		result		=> y4_s
	);

	RiseMult2_inst : my_37_37_mult
	port map(
		clock		=> clk_i, 
		dataa		=> std_logic_vector(t0_max2_s), 
		datab		=> std_logic_vector(result_s),
		result		=> yRise2_Div2_s
	);

	FallMult2_inst : my_37_37_mult
	port map(
		clock		=> clk_i, 
		dataa		=> std_logic_vector(t0_max2_fall_s), 
		datab		=> std_logic_vector(result_s),
		result		=> yRise2_Div2_fall_s
	);

	SetVolt_Mult_inst : MY_16_MULTIPLIER
	port map(
		clock		=> clk_i, 
		dataa		=> std_logic_vector(iset_total_s), 
		datab		=> std_logic_vector(Rset_i),
		result		=> vc_set_s
	);

	CompRise_Mult_inst : MY_16_MULTIPLIER
	port map(
		clock		=> clk_i, 
		dataa		=> std_logic_vector(to_unsigned(TIME_DELAY_CONSTANT,16)), 
		datab		=> std_logic_vector(xComp_r_s),
		result		=> yComp_mult_r_s
	);

	CompFall_Mult_inst : MY_16_MULTIPLIER
	port map(
		clock		=> clk_i, 
		dataa		=> std_logic_vector(to_unsigned(TIME_DELAY_CONSTANT,16)), 
		datab		=> std_logic_vector(xComp_f_s),
		result		=> yComp_mult_f_s
	);

	-- OUTPUT ANOTAITON
	hss_bound_o <= hss_bound_s;
    Tss_bound_o <= Tss_bound_s;
    Tss_bound_fall_o <= Tss_bound_fall_s;
    Tss2_bound_o <= Tss2_bound_s;
    Tss2_bound_fall_o <= Tss2_bound_fall_s;
    Hcomp_bound_rise_o <= Hcomp_rise_s;
    Hcomp_bound_fall_o <= Hcomp_fall_s;
			
end structural; 