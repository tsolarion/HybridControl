--==========================================================
-- Unit		:	dutycycle_calc(rtl)
-- File		:	dutycycle_calc.vhd
-- Purpose	:	
-- Author	:	Michael Hersche - HPE - ETH Zuerich
-- Device	:	Altera FPGA - Cyclone V
-- EDA syn	:	Altera Quartus II
-- EDA sim	:	Modelsim SE 10.1c
-- misc		:	--
-- depdcy	:	my_31b_divider, my_17_16_mult
--==========================================================

--! @file dutycycle_calc.vhd
--! @author Michael Hersche
--! @date  26.09.2017

-- use standard library
library ieee;
--! Use logic elements
use ieee.std_logic_1164.all;
--! Use numeric elements
use ieee.numeric_std.all;

--! @brief Dutycycle calculation from Voltage to D 
--! @details General formula: d_o =  (pi_i + vc_i + vbusl_s) / (vbush_i+vbusl_i)
--! @details If nsoftreset_i = 0, we set the output to a high value until a new PI value is calculated 
--! @details otherwise artifacts in current signal 
entity dutycycle_calc is 
	generic( 	
			INW_G 		: natural range 1 to 64 := 16; 		--! Controller input data size 
			OUTW_G		: natural range 1 to 63 := 11; 		--! Output data width 
			NINTERLOCK_G: integer := 50 
			
			);		
	port( 	clk_i		: in std_logic; --! Main clock 
			nreset_i	: in std_logic; --! Main asynchronous reset low active
			nsoftreset_i: in std_logic; --! Synchronous reset signal low active 
			pi_i		: in signed(INW_G-1 downto 0) := (others => '0'); --! data originating from PI Controller 
			pi_valid_i	: in std_logic; --! new PI value valid 
			vc_i		: in signed(INW_G-1 downto 0) := (others => '0'); --! measurement data Vc(feed forward)  
			vc_switch_i : in signed(INW_G-1 downto 0) := (others => '0'); --! switchable input signal vc (00: no operation, 01: +, 10: -)
			switch_i	: in std_logic_vector(1 downto 0) := (others => '0'); -- switch signal 
			vbush_i		: in signed(INW_G-1 downto 0) := (others => '0'); --! measurement data Vbush
			vbusl_i		: in signed(INW_G-1 downto 0) := (others => '0'); --! measurement data Vbusl
			iset_i		: in signed(INW_G-1 downto 0) := (others => '0'); --! input set current 
			half_duty_i : in std_logic := '0'; --! use only halft of duty cycle (in startup) 
			d_o 		: out unsigned(OUTW_G-1 downto 0) := (others => '0') --! Dutycycle output 		
			);
			
end dutycycle_calc;

architecture structural of dutycycle_calc is
-- ================== CONSTANTS ==================================================		
constant DIV_LENGTH : natural := 31; --! length of the divider 	
constant DIV_DELAY	: natural := 32; 
constant MAX_OUT : integer := 2**OUTW_G -1 - (2**OUTW_G -1)/10  ; -- 0.9  maximum duty cycle 
constant MIN_OUT : integer := (2**OUTW_G -1)/20; --0.05 minimum duty cycle 

constant ZEROS_11_C : signed(OUTW_G-1 downto 0) := (others => '0'); 

-- Switch constants 
constant NO_SWITCH_C : std_logic_vector(1 downto 0) := "00"; 
constant ADD_SWITCH_C: std_logic_vector(1 downto 0) := "01"; 
constant SUB_SWITCH_C: std_logic_vector(1 downto 0) := "10"; 

-- Timer Top value := 1 PWM cycle 
constant CNT_TOP_C: integer := (10**8/60000); 


-- =================== STATES ====================================================
type overfl_superv is (IDLE,OVERFLOW, UNDERFLOW); 	

-- =================== SIGNALS ===================================================
-- Input Data registers 
signal pi_s, vc_s,vbush_s,vbusl_11_s, vbusl_s, vc_switch_s 	: signed(DIV_LENGTH-1 downto 0) := (others => '0'); -- 
signal  pi_next_s, vc_next_s,vbush_next_s,vbusl_11_next_s, vbusl_next_s,vc_switch_next_s : signed(DIV_LENGTH-1 downto 0) := (others => '0'); -- 

signal switch_s : std_logic_vector(1 downto 0) := (others => '0');  -- switch signal latched 
signal pi_valid_s : std_logic_vector(1 downto 0) := (others => '0');  -- pi_valid signal latched 

-- First stage signal 
signal num_s, num_next_s 			: signed(DIV_LENGTH-1 downto 0) := (others => '0'); -- Numerator 
signal denum_s, denum_next_s 		: signed(DIV_LENGTH-1 downto 0) := (others => '0'); -- Denominator 
-- Counter logic 
signal cnt_s,cnt_next_s : integer := 0; -- counter waiting until calculation done 
signal div_ready_s, div_ready_next_s : std_logic := '0'; -- indicates calculation done (Timer at UP)

-- Duty 
signal d_s, d_next_s : std_logic_vector(DIV_LENGTH-1 downto 0) := (others => '0'); -- output of divider (with register for timing) 
signal d_out_s,d_out_next_s : unsigned(OUTW_G-1 downto 0) := (others => '0'); -- output of this block  

-- Outstate for detecting overflow of output  
signal out_state_s, out_state_next_s : overfl_superv := IDLE; 

-- compensation of interlocking 
signal vh_p_vl_s, vh_p_vl_next_s : signed(INW_G downto 0) := (others => '0'); --vbush_i + vbusl_i 
signal interlock_comp_s : std_logic_vector(32 downto 0) := (others => '0'); -- (vbush_i + vbusl_i)*INTERLOCK_COMP_C 
constant COMP_THRESH_C : signed(INW_G-1 downto 0) := to_signed(20*(2**5),INW_G); 
constant INTERLOCK_COMP_C : signed(INW_G-1 downto 0) := to_signed(NINTERLOCK_G*6*(2**OUTW_G)/(10000), INW_G); --NINTERLOCK_G * fs*(2**11)/fclk = NINTERLOCK_G * 60kHz*(2**11)/100MHz  

-- timer 
signal cnt_start_s						: std_logic := '0'; 
signal cnt_end_s, cnt_end_next_s		: std_logic := '0'; 
signal cnt_val_s, cnt_val_next_s		: integer range 0 to CNT_TOP_C := 0; 


-- ================== COMPONENTS =================================================
component my_31b_divider is 
port(	numer	: in std_logic_vector(30 downto 0); 
		denom	: in std_logic_vector(30 downto 0); 
		clock	: in std_logic; 
		quotient: out std_logic_vector(30 downto 0); 
		remain	: out std_logic_vector(30 downto 0)
	); end component; 
	
component my_17_16_mult is 
	port
	(
		clock		: in std_logic ;
		dataa		: in std_logic_vector (16 downto 0);
		datab		: in std_logic_vector (15 downto 0);
		result		: out std_logic_vector (32 downto 0)
	);
end component;

begin		

	CNT_LOG: process( cnt_val_s, cnt_start_s)
	begin 
		if cnt_start_s = '1' then 
			cnt_val_next_s <= 0; 
			cnt_end_next_s 	   <= '0'; 
		elsif cnt_val_s < CNT_TOP_C then 
			cnt_val_next_s <= cnt_val_s + 1; 
			cnt_end_next_s 	   <= '0'; 
		else 
			cnt_val_next_s <= cnt_val_s; 
			cnt_end_next_s 	   <= '1'; 
		end if; 
	end process; 
	
	CNT_REG: process(clk_i,nreset_i)
	begin 
		if nreset_i = '0' then 
			cnt_end_s <= '0';
			cnt_val_s <= CNT_TOP_C;
		elsif rising_edge(clk_i) then 
			cnt_end_s   <= cnt_end_next_s;
			cnt_val_s	<= cnt_val_next_s;	
		end if; 
	end process; 
	
	
	IN_PROC: process(pi_i,vc_i,vbusl_i,vbush_i,pi_valid_s,switch_s,switch_i,vc_switch_s,vc_switch_i,pi_s,vc_s,vbush_s,vbusl_s,vbusl_11_s,div_ready_s)
		begin 
			-- default assignments to avoid latches  
			pi_next_s		<= 	pi_s; 		
			vc_next_s 		<=  vc_s; 
			vc_switch_next_s<=  vc_switch_s; 
			vbush_next_s 	<=  vbush_s;  	
			vbusl_next_s 	<=  vbusl_s;  	
			vbusl_11_next_s <=  vbusl_11_s;  
			vh_p_vl_next_s	<= resize(vbush_i,INW_G+1) + resize(vbusl_i,INW_G+1); 
			cnt_start_s		<= '0'; 
			
			-- load data if new PI value valid 
			if pi_valid_s = "01" then -- only new calculation if  
				-- shift nominator by 11 bits and resize to DIV_LENGTH
				pi_next_s 	<= resize(pi_i & ZEROS_11_C,DIV_LENGTH); 
				vbusl_11_next_s <= resize(vbusl_i & ZEROS_11_C,DIV_LENGTH);
					-- resize denominator 
				vbush_next_s	<= resize(vbush_i,DIV_LENGTH);
				vbusl_next_s	<= resize(vbusl_i,DIV_LENGTH);
				
				if cnt_end_s = '1' then -- only load new vc value if waiting time expired  
					vc_next_s 	<= resize(vc_i & ZEROS_11_C,DIV_LENGTH);
				
					-- cases for input switch 
					case switch_i is 
						when NO_SWITCH_C => 
							vc_switch_next_s <= (others => '0');  
						when ADD_SWITCH_C => 
							vc_switch_next_s <= resize(vc_switch_i & ZEROS_11_C,DIV_LENGTH);
						when SUB_SWITCH_C => 
							vc_switch_next_s <= -resize((vc_switch_i & ZEROS_11_C),DIV_LENGTH);
						when others => 
							vc_switch_next_s <= (others => '0');  
					end case;       
					
				end if; 
			
			-- if switch state changed from "00" to a high value "01" or "10" (rising edge) 
			elsif switch_s /= switch_i and switch_s = NO_SWITCH_C then 
				cnt_start_s <= '1'; -- start the counter 
				--  only update vc_switch_next_s, the other values are kept from the last period 
				case switch_i is 
					when ADD_SWITCH_C => 
						vc_switch_next_s <= resize(vc_switch_i & ZEROS_11_C,DIV_LENGTH);
					when SUB_SWITCH_C => 
						vc_switch_next_s <= -resize((vc_switch_i & ZEROS_11_C),DIV_LENGTH);
					when others => 
						vc_switch_next_s <= (others => '0');  
				end case;       
				
			end if; 
				
		end process; 	
	
	--! @brief Input register 
	--! @details 
	IN_REG: process(clk_i,nreset_i)
		begin 
			if nreset_i = '0' then 
				pi_s		<= (others => '0');
				vc_s 		<= (others => '0');
				vbush_s 	<= (others => '0');
				vbusl_s 	<= (others => '0');
				vbusl_11_s 	<= (others => '0');
				vc_switch_s <= (others => '0');
				pi_valid_s	<= (others => '0'); 
				switch_s 	<= (others => '0'); 
				vh_p_vl_s 	<= (others => '0'); 
			elsif rising_edge(clk_i) then 
				pi_s 		<= pi_next_s;
				vc_s 		<= vc_next_s;
				vbusl_11_s 	<= vbusl_11_next_s;
				vbush_s		<= vbush_next_s;
				vbusl_s		<= vbusl_next_s;	
				vc_switch_s <= vc_switch_next_s; 
				pi_valid_s	<= pi_valid_s(0) & pi_valid_i; -- shift from the right 
				switch_s	<= switch_i; 
				vh_p_vl_s 	<= vh_p_vl_next_s; 
			end if; 
		end process; 
		
	
		
	comp_mult_inst: my_17_16_mult  
	port map
	(
		clock		=> clk_i,
		dataa		=> std_logic_vector(vh_p_vl_s), 
		datab		=> std_logic_vector(INTERLOCK_COMP_C),
		result		=> interlock_comp_s
	);

	--! @brief Registers for Addition and output signal 
	CALC_REG_PROC: process(clk_i,nreset_i)	
		begin 
			if nreset_i = '0' then 
				num_s 	<= (others => '0'); 
				denum_s <= (others => '0');  
				d_s		<= (others => '0');  
				d_out_s <= (others => '0'); 
				cnt_s	<= 0; 
				out_state_s <= IDLE; 
				div_ready_s <= '0'; 
			elsif rising_edge(clk_i) then 
				num_s 	<= num_next_s; 
				denum_s	<= denum_next_s; 
				d_s		<= d_next_s; 
				d_out_s <= d_out_next_s; 
				cnt_s	<= cnt_next_s; 
				out_state_s <= out_state_next_s; 
				div_ready_s <= div_ready_next_s; 
			end if; 
		end process; 
		
	-- Calculations of numerator and denominator
	-- Process counter 
	CALC_LOGIC_PROC: process(vc_switch_s,iset_i,pi_s,vc_s, vbush_s, vbusl_s,vbusl_11_s,cnt_s,cnt_next_s, pi_valid_s,nsoftreset_i,interlock_comp_s, switch_i,switch_s)
		begin
		
			div_ready_next_s <= '0'; 
			
			-- Artihmetic for nummerator and denominator 
			if iset_i > COMP_THRESH_C then 
				num_next_s 		<= vc_switch_s+pi_s + vc_s + vbusl_11_s + resize(signed(interlock_comp_s), DIV_LENGTH); 
			else 
				num_next_s 		<= vc_switch_s+pi_s + vc_s + vbusl_11_s; 
			end if; 
			denum_next_s 	<= vbush_s + vbusl_s; 
			
			-- Counter logic 
			if nsoftreset_i = '0' then 
				cnt_next_s <= 0; 
			elsif  pi_valid_s = "01" or (switch_s /= switch_i and switch_s = NO_SWITCH_C)  then 
				cnt_next_s <= 0; 
			elsif cnt_s <= DIV_DELAY then 
				cnt_next_s <= cnt_s +1; 
			else 
				cnt_next_s <= cnt_s; 
				div_ready_next_s <= '1'; 
			end if; 
		end process; 
	
	inst_division: my_31b_divider
		port map(
			numer => std_logic_vector(num_s), 
			denom => std_logic_vector(denum_s),
			clock => clk_i,
			quotient => d_next_s, 
			remain => open
		); 	
	
	LIMITER_LOGIC: process(out_state_s,d_s)
		begin
			out_state_next_s <= out_state_s; 
			
			if to_integer(signed(d_s)) < MIN_OUT then 
				out_state_next_s <= UNDERFLOW; 
			elsif to_integer(signed(d_s)) > MAX_OUT then 
				out_state_next_s <= OVERFLOW; 
			else 
				out_state_next_s <= IDLE; 
			end if; 
			
		end process; 
		
	OUTPUT_LOGIC_PROC: process(d_s,d_out_s,div_ready_s,nsoftreset_i,out_state_s, half_duty_i)
		begin 
			d_out_next_s <= d_out_s; 
			
			--if nsoftreset_i = '0' then 
				--d_out_next_s <= to_unsigned(MAX_OUT,OUTW_G); -- assign high value 
			if div_ready_s = '1' then 
				case out_state_s is 
					when IDLE => 
						if half_duty_i = '0' then 
							d_out_next_s <= unsigned(d_s(OUTW_G-1 downto 0)); 
						else 
							d_out_next_s <= SHIFT_RIGHT(unsigned(d_s(OUTW_G-1 downto 0)),1); 
						end if; 
					when UNDERFLOW =>
						d_out_next_s <= to_unsigned(MIN_OUT,OUTW_G);
					when OVERFLOW => 
						d_out_next_s <= to_unsigned(MAX_OUT,OUTW_G);
					when others => 
						d_out_next_s <= to_unsigned(MIN_OUT,OUTW_G);
				end case; 
			end if; 

		end process; 
		
	
		
	-- output annotation 
	d_o <= d_out_s; 
		
end structural; 
















