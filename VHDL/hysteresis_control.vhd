--==========================================================
-- Unit		:	hysteresis_control(rtl)
-- File		:	hysteresis_control.vhd
-- Purpose	:	
-- Author	:	Michael Hersche - HPE - ETH Zuerich
-- Device	:	Altera FPGA - Cyclone V
-- EDA syn	:	Altera Quartus II
-- EDA sim	:	Modelsim SE 10.1c
-- misc		:	--
-- depdcy	:	--
--==========================================================

--! @file hysteresis_control.vhd
--! @author Michael Hersche
--! @date  24.10.2017

-- use standard library
library ieee;
--! Use logic elements
use ieee.std_logic_1164.all;
--! Use numeric elements
use ieee.numeric_std.all;

--! @brief Hysteresis controller with adaptive bands 
--! @details This block includes the following functionalities: 
--! @details - Decides wether in average (PI) or hysteresis mode 
--! @details - Detects conditions for entering hysteresis mode
--! @details - Hysteresis control 
--! @details - Adaptive hysteresis bands 

entity hysteresis_control is 
	generic( 	DATAWIDTH_G 	: integer range 8 to 16 := 16; --! Data width of measurements
                DELAY_COMP_CONSTANT : integer := 250000*(2**5); -- Constant for delay compensation in the 2nd rise. (2*H0*L*10**8)  
				CMAX_G			: integer := 1666; --! Maximum counter value of PWM (determines PWM frequency)
				NINTERLOCK_G	: integer := 50; 
				NINTER_MARGIN_G	: integer := 25; --! NINTERLOCK_G + NINTER_MARGIN_G is the minimum switching frequency 
				NMIN_PER_G		: integer := 51; -- minimum length of PWM pulse 
				NO_CONTROLER_G 	: integer := 2;--! Total number of controler used
				MY_NUMBER_G 	: integer := 1; --! Slave number
				DELTA_I_REF_G 	: integer := 25*(2**5); --! minimum set current change (25 A) for entering hysteresis mode 
				DELTA_I_THR_G 	: integer := 25*(2**5); --! minimum current difference (25 A) between measured and set current for entering hysteresis mode 
				DELTA_VC_G		: integer := 100*(2**5); --! minimum VC change change (100 V) for entering hysteresis mode 
				D_IOUT_MAX_G	: integer := 5*(2**5); --! Maximum current ripple after first rise (here 10A)
                TIME_DELAY_CONSTANT : integer := 115; --! Delay/L * 2**12. By default this is 7/250 * 4096. This is used for the initial compensation for the hysteresis bounds.  
				N_CYCLE_REST_G	: integer := 0 --! Number of cycles controller stays in Hysterssis after phaseshift 
			);		
	port( 	clk_i			: in std_logic; --! Main clock 
			nreset_i 		: in std_logic; --! Asynchronous reset
			nsoftreset_i	: in std_logic; --! synchronous softreset 
			hyst_enable_i	: in std_logic; --! enables hysteresis mode			
			iset_i			: in signed(DATAWIDTH_G-1 downto 0); --! set current 
			imeas_i			: in signed(DATAWIDTH_G-1 downto 0); --! measured effective current 
			imeas_tot_i		: in signed(DATAWIDTH_G-1+(NO_CONTROLER_G-1) downto 0); --! Total measurement current 
			iset_tot_i		: in signed(DATAWIDTH_G-1+(NO_CONTROLER_G-1) downto 0); --! Total set current 
			vc_i			: in signed(DATAWIDTH_G-1 downto 0); --! Vc measured voltage
			Rset_i			: in unsigned(DATAWIDTH_G-1 downto 0); --! Vc measured voltage
			hyst_cond_sel_i	: in std_logic_vector(2 downto 0); --! Enable conditions for entering hysteresis: 2: vc, 1: ierr, 0: iset 
			pwm_switch1_i	: in std_logic; --! PWM high switch signal 
			pwm_switch2_i	: in std_logic; --! PWM low switch signal 
			hyst_t1_vec_i	: in std_logic_vector(NO_CONTROLER_G-1 downto 0); --! Start of point t1 during hysteresis control of all modules (0: master) 
			hyst_o			: out std_logic; 
			hyst_t1_o 		: out std_logic;--! Start of point t1 during hysteresis control of this module
			hyst_t2_o		: out std_logic; --! Start of SECOND_UP of this module
			hyst_vec_i		: in std_logic_vector(NO_CONTROLER_G-1 downto 0);  --! hystersis mode of all modules  		
			hyst_t2_ma_i	: in std_logic; --! Start of SECOND_UP of master module
			Tss_bound_i 	: in signed(15 downto 0); --! signed output value
			Tss_bound_fall_i: in signed(15 downto 0); --! signed output value
            Tss2_bound_i 	: in signed(15 downto 0); --! signed output value
            Tss2_bound_fall_i 	: in signed(15 downto 0); --! signed output value 
			hss_bound_i		: in signed(15 downto 0); --! hss_bound
			deltaH_ready_i	: in std_logic; --! calculation of deltaH finished
            Hcomp_bound_rise_i    : in signed(DATAWIDTH_G-1 downto 0); --! signed output value of the initial compensation for the overshoot (V1-Vc_set)*TIME_DELAY_CONSTANT
            Hcomp_bound_fall_i    : in signed(DATAWIDTH_G-1 downto 0); --! signed output value of the initial compensation for the overshoot (V2+Vc_set)*TIME_DELAY_CONSTANT
			deltaT_i 		: in signed(15 downto 0); --! signed output value dH 
			deltaT_fall_i 	: in signed(15 downto 0); --! signed output value dH  
			deltaH_i 		: in signed(15 downto 0); --! signed output value dH 
			switch1_o		: out std_logic; --! Output high switch 
			switch2_o		: out std_logic; --! Output low switch 
			nreset_pwm_o	: out std_logic; --! low active softreset of pwm 
			i_upper_o		: out signed(DATAWIDTH_G-1 downto 0); --! Hysteresis upper current bound (just for testing)
			i_lower_o		: out signed(DATAWIDTH_G-1 downto 0) --! Hysteresis lower current bound (just for testing)
			);
end hysteresis_control;

architecture structural of hysteresis_control is

-- ================== CONSTANTS ==================================================				
constant H0_C : integer := D_IOUT_MAX_G /NO_CONTROLER_G ; --! Initial band for first rise (derived from maximum current ripple)
-- Tsol:
constant CNT_MIN : integer := 70; -- MIN WAITING TIME IN THE WAITING STATES

-- ================== COMPONENTS =================================================
function OR_REDUCE(ARG: STD_LOGIC_VECTOR) return std_logic is
	variable result: STD_LOGIC;
    begin
	result := '0';
	for i in ARG'range loop
	    result := result or ARG(i);
	end loop;
        return result;
    end;

component and_reduce_edge is 
	generic( 	NO_CONTROLER_G 	: integer := 2 --! Total number of controler used
			);		
	port( 	clk_i			: in std_logic; --! Main clock 
			nreset_i 		: in std_logic; --! Asynchronous reset 
			nsoftreset_i	: in std_logic; --! Synchronous nreset 
			data_i			: in std_logic_vector(NO_CONTROLER_G-1 downto 0); --! Input vector 
			result_o		: out std_logic --! 
			);
end component;

--! @brief Generates interlocked high side and low side signal out of one high side signal 
component interlocking is 
	generic( 	NINTERLOCK_G 	: natural := 50 --! Number of Bits counter 
			);		
	port( 	clk_i			: in std_logic; --! main system clock
			nreset_i 		: in std_logic; --! asynchronous nreset 
			nsoftreset_i	: in std_logic; --! synchronous reset 
			sw1_i			: in std_logic; --! high switch 
			sw2_i			: in std_logic; --! low switch (only used for start up)
			int_sw1_o		: out std_logic; --! high side output switch  
			int_sw2_o		: out std_logic; --! low side output switch 			
			interl_o		: out std_logic --! interlocking state 
			);
end component;

-- =================== STATES ====================================================
--Tsol edit: Added the Delay states
type hysteresis_state is (IDLE,PWM_CONTROL,WAIT_STEP_UP, NEW_STEP_UP, DELAY_U1, NEW_STEP_DOWN, DELAY_D1, WAIT_STEP_DOWN, FIRST_DOWN, DELAY_2, SECOND_UP, DELAY_3, PHASE_SHIFT, DELAY_4, THIRD_UP, DELAY_5, THIRD_DOWN, DELAY_6); --! State machine for hysteresis control 
-- =================== SIGNALS ===================================================
-- State machine 
signal hyst_state_s, hyst_state_next_s : hysteresis_state := PWM_CONTROL; --! states hysteresis control: default in PWM_CONTROL mode 

-- INPUT currents 
signal iset_s: integer := 0; --! set current measured 
signal iset_tot_s,iset_tot_delayed_s : integer := 0; --! total set current measured and delayed by 1 clock cycle after sync 
signal imeas_s : integer := 0; --! measured current after sync 
signal ierr_s, ierr_next_s : integer := 0; --! measured error current after sync 

signal delay_rise_2nd_s, delay_rise_next_2nd_s : integer := CNT_MIN; --! set current measured
signal delay_fall_2nd_s, delay_fall_next_2nd_s : integer := CNT_MIN; --! set current measured 
 
signal delay_rise_3rd_s, delay_rise_next_3rd_s : integer := CNT_MIN; --! set current measured
signal delay_fall_3rd_s, delay_fall_next_3rd_s : integer := CNT_MIN; --! set current measured

signal delay_Delta_rise_s, delay_Delta_rise_next_s : integer := CNT_MIN; --! set current measured 
signal delay_Delta_fall_s, delay_Delta_fall_next_s : integer := CNT_MIN; --! set current measured 

-- voltage 
signal vc_s, vc_delayed_s : integer := 0; --! Vc measurement and delayed by 1 clock cycle after sync 

-- Combinatoric signals 
-- STEP UP 
signal up_iset_s ,	up_iset_next_s	: std_logic := '0'; 
signal up_ierr_s ,	up_ierr_next_s	: std_logic := '0'; 
signal up_vc_s ,	up_vc_next_s   	: std_logic := '0'; 

-- STEP DOWN 
signal down_iset_next_s, down_iset_s: std_logic := '0'; 
signal down_ierr_next_s, down_ierr_s: std_logic := '0'; 
signal down_vc_next_s, 	 down_vc_s  : std_logic := '0'; 

-- current bounds 
signal i_upper_s, i_upper_next_s : integer := 0; --! hysteresis control upper current bound 
signal i_lower_s, i_lower_next_s : integer := 0; --! hysteresis control lower current bound 
signal hyst_s, hyst_next_s : std_logic := '0'; --! start of hysteresis mode 
signal t1_start_s,t1_start_next_s : std_logic := '0'; --! Start of point t1 during hysteresis control
signal t2_start_s, t2_start_next_s  : std_logic := '0'; --! Start of SECOND_UP

-- switch signals & interlocking 
signal sw1_s: std_logic := '0'; --! local high switch signal(either PWM or hysteresis)
signal interl_s: std_logic:= '0'; --! interlocking signal (when '1' then in interlocking)
signal int_sw1_s,int_sw2_s: std_logic := '0'; --! interlocked output switch signals 


signal nreset_pwm_s, nreset_pwm_next_s: std_logic:= '0'; --! low active softreset signal for PWM counter 

-- signal for shift_mode enable 
signal test_vec_s : std_logic_vector(NO_CONTROLER_G-1 downto 0) := (others => '1'); 
signal nreset_phase_shift_s : std_logic := '0'; 
signal hyst_t1_vec_latch_s : std_logic_vector(NO_CONTROLER_G-1 downto 0) := (others => '0'); 
signal phase_shift_en : std_logic := '0'; 

-- counter 
signal cnt_cycle_s, cnt_cycle_next_s : integer range 0 to N_CYCLE_REST_G +1 := 0; -- counter for cycles in last two phases of hysteresis 
-- Edit Tsol: Added the counters for the delay states:
signal dly_cnt_s, dly_cnt_next_s : integer := 0;  --! counter for dly states

-- hyst enable 
signal hyst_enable_s : std_logic := '0'; -- hysteresis enable: not(or_reduce(hyst_vec_i)) and hyst_enable_i 

begin	

	 hyst_enable_s <= not(OR_REDUCE(hyst_vec_i)) and hyst_enable_i; 
		
	--! @brief Detects t1 events of all modules 
	phase_shift_en_inst: and_reduce_edge
	generic map ( 	NO_CONTROLER_G =>	NO_CONTROLER_G
			)		
	port map( 	clk_i		 	=> clk_i, 
			nreset_i 		=> nreset_i, 
			nsoftreset_i	=> nreset_phase_shift_s, 
			data_i			=> hyst_t1_vec_i, 
			result_o		=> phase_shift_en
			);

	--! @brief INPUT registers 
	input_reg : process(clk_i,nreset_i)
	begin
		if nreset_i = '0' then
			iset_s 			<= 0; 
			imeas_s			<= 0; 
			ierr_s			<= 0; 
			cnt_cycle_s 	<= 0; 
			iset_tot_s		<= 0; 
			iset_tot_delayed_s<= 0;
--Tsol:
            dly_cnt_s <= 0;
			vc_s			<= 0; 
			vc_delayed_s 	<= 0; 
		elsif rising_edge(clk_i) then
			iset_s 			<= to_integer(iset_i); 
			iset_tot_s		<= to_integer(iset_tot_i); 
			iset_tot_delayed_s 	<= iset_tot_s;  
			imeas_s			<= to_integer(imeas_i); 
			ierr_s			<= ierr_next_s; 
			cnt_cycle_s		<= cnt_cycle_next_s;
--Tsol:
            dly_cnt_s       <= dly_cnt_next_s;
			vc_s			<= to_integer(vc_i); 
			vc_delayed_s	<= vc_s; 
		end if; 
	end process; 



	--! @brief Registers for state machine and counter 
	statemachine_reg : process(clk_i,nreset_i)
	begin
		if nreset_i = '0' then
			hyst_state_s <= IDLE; 
			i_upper_s 	 <= 0; 
			i_lower_s    <= 0; 
			t1_start_s	 <= '0';
			t2_start_s	 <= '0'; 
			up_iset_s	 <= '0';
			up_ierr_s    <= '0';
			up_vc_s 	 <= '0';
			down_iset_s  <= '0';
			down_ierr_s	 <= '0';
			down_vc_s    <= '0';
            delay_rise_2nd_s <= 0;
            delay_rise_3rd_s <= 0;
            delay_fall_3rd_s <= 0;  
			nreset_pwm_s <= '1'; 
		elsif rising_edge(clk_i) then
			if nsoftreset_i = '0' then 
				hyst_state_s <= IDLE; 
				i_upper_s 	 <= 0; 
				i_lower_s    <= 0; 
				t1_start_s	 <= '0';
				t2_start_s	 <= '0'; 
				up_iset_s	 <= '0';
				up_ierr_s    <= '0';
				up_vc_s 	 <= '0';
				down_iset_s  <= '0';
				down_ierr_s	 <= '0';
				down_vc_s    <= '0';
                delay_rise_2nd_s <= 0;
                delay_rise_3rd_s <= 0;
                delay_fall_3rd_s <= 0;    
				nreset_pwm_s <= '1'; 
			else 
				hyst_state_s 	<= hyst_state_next_s; 
				i_upper_s		<= i_upper_next_s; 
				i_lower_s		<= i_lower_next_s;
                delay_rise_2nd_s <= delay_rise_next_2nd_s;
                delay_fall_2nd_s <= delay_fall_next_2nd_s;
                delay_rise_3rd_s <= delay_rise_next_3rd_s;
                delay_fall_3rd_s <= delay_fall_next_3rd_s;
                delay_Delta_rise_s <= delay_Delta_rise_next_s;
                delay_Delta_fall_s <= delay_Delta_fall_next_s;    
				hyst_s	<= hyst_next_s; 
				t1_start_s	 	<= t1_start_next_s; 
				t2_start_s		<= t2_start_next_s; 
				up_iset_s	 	<= up_iset_next_s; 
				up_ierr_s    	<= up_ierr_next_s;
				up_vc_s 	 	<= up_vc_next_s;  
				down_iset_s  	<= down_iset_next_s; 
				down_ierr_s	 	<= down_ierr_next_s;
				down_vc_s    	<= down_vc_next_s; 
				nreset_pwm_s	<= nreset_pwm_next_s; 
			end if; 
		end if; 
	end process; 
	
	
	-- combinatoric for entering hysteresis 
	-- STEP UP 
	up_iset_next_s <= '1' when (hyst_cond_sel_i(0)='1') and (iset_tot_s - iset_tot_delayed_s >=  DELTA_I_REF_G) else '0'; 
	up_ierr_next_s <= '1' when (hyst_cond_sel_i(1)='1') and (ierr_s >=  DELTA_I_THR_G) else '0'; 
	up_vc_next_s   <= '1' when (hyst_cond_sel_i(2)='1') and (vc_s - vc_delayed_s >= DELTA_VC_G) else '0'; 
	
	-- STEP DOWN 
	down_iset_next_s <=  '1' when (hyst_cond_sel_i(0)='1') and (iset_tot_s - iset_tot_delayed_s <=  -DELTA_I_REF_G) else '0'; 
	down_ierr_next_s <=  '1' when (hyst_cond_sel_i(1)='1') and (ierr_s <=  -DELTA_I_THR_G) else '0'; 
	down_vc_next_s   <= '1' when  (hyst_cond_sel_i(2)='1') and (vc_s - vc_delayed_s < -DELTA_VC_G) else '0'; 
	
	

	--! @brief State machine logic 
	statemachine_logic: process(hyst_state_s,iset_s,iset_tot_s,iset_tot_delayed_s,ierr_s, i_upper_s, i_lower_s,
								imeas_s,t1_start_s,hss_bound_i,Tss_bound_i,Tss_bound_fall_i, Tss2_bound_i,Tss2_bound_fall_i, deltaH_i, deltaT_i, deltaT_fall_i, hyst_s,deltaH_ready_i,phase_shift_en,
								t2_start_s,cnt_cycle_s,nreset_pwm_s,iset_tot_i,imeas_tot_i,vc_s,vc_delayed_s,
								up_iset_s,up_ierr_s,up_vc_s,down_iset_s,down_ierr_s,down_vc_s,hyst_enable_s, dly_cnt_s,
								interl_s,pwm_switch1_i, delay_rise_2nd_s, delay_rise_3rd_s, delay_Delta_rise_s, delay_Delta_fall_s ) 
	begin
		-- Default assignments for avoiding Latches 
		hyst_state_next_s <= hyst_state_s; 
		i_upper_next_s <= i_upper_s; 
		i_lower_next_s <= i_lower_s;
        delay_rise_next_2nd_s <= delay_rise_2nd_s;
        delay_fall_next_2nd_s <= delay_fall_2nd_s;    
        delay_rise_next_3rd_s <= delay_rise_3rd_s;
        delay_fall_next_3rd_s <= delay_fall_3rd_s;
        delay_Delta_rise_next_s <= delay_Delta_rise_s;
        delay_Delta_fall_next_s <= delay_Delta_fall_s;    
		nreset_pwm_next_s <= nreset_pwm_s; 
		t1_start_next_s <= t1_start_s;  
		t2_start_next_s <= t2_start_s;  
		hyst_next_s <= hyst_s; 
		nreset_phase_shift_s <= '1'; 
		cnt_cycle_next_s <= cnt_cycle_s; 
		--Tsol:
        dly_cnt_next_s <= dly_cnt_s; 

		-- arithmetic 
		ierr_next_s <= to_integer(iset_tot_i)  -  to_integer(imeas_tot_i); 
		
		case hyst_state_s is 
			when IDLE => 
				hyst_state_next_s <= PWM_CONTROL; 
			when PWM_CONTROL => 
				hyst_next_s <= '0';
				nreset_pwm_next_s <= '1'; 
				-- Conditions for entering hysteresis mode STEP_UP 
				if hyst_enable_s = '1' and (up_iset_s='1' or up_ierr_s='1' or up_vc_s='1') then 
					hyst_state_next_s <= NEW_STEP_UP;
					dly_cnt_next_s <= 0; 	
					-- if interl_s = '0' then --or pwm_switch1_i = '1' 
						-- hyst_state_next_s <= NEW_STEP_UP; 
					-- else 
						-- hyst_state_next_s <= WAIT_STEP_UP; 
					-- end if; 	
                    if up_iset_s='1' then
                        i_upper_next_s <= iset_s + (H0_C - to_integer(Hcomp_bound_rise_i)); 
                        i_lower_next_s <= iset_s - (H0_C - to_integer(Hcomp_bound_fall_i)); 
                        delay_rise_next_2nd_s	<= CNT_MIN;		
                        hyst_next_s <= '1'; 
                    elsif up_ierr_s='1' or up_vc_s='1' then
                        i_upper_next_s <= iset_s + (H0_C- to_integer(Hcomp_bound_rise_i)); 
                        i_lower_next_s <= iset_s - (H0_C- to_integer(Hcomp_bound_fall_i)); 
                        delay_rise_next_2nd_s	<= CNT_MIN;		
                        hyst_next_s <= '1'; 
                    end if;
				
				-- Conditions for entering hysteresis mode STEP_DOWN
				elsif hyst_enable_s = '1' and (down_iset_s='1' or down_ierr_s='1' or down_vc_s='1') then 
					hyst_state_next_s <= NEW_STEP_DOWN;
					-- if interl_s = '0' then --  or pwm_switch1_i = '0'
						-- hyst_state_next_s <= NEW_STEP_DOWN; 
					-- else 
						-- hyst_state_next_s <= WAIT_STEP_DOWN; 
					-- end if; 	
                    i_upper_next_s <= iset_s + (H0_C - to_integer(Hcomp_bound_rise_i)); 
                    i_lower_next_s <= iset_s - (H0_C - to_integer(Hcomp_bound_fall_i)); 	
                    hyst_next_s <= '1'; 
				end if; 
				
			when NEW_STEP_UP => 
                --TSOL: Compensation-- Still update the limits here.
                i_upper_next_s <= iset_s + (H0_C - to_integer(Hcomp_bound_rise_i)); 
                i_lower_next_s <= iset_s - (H0_C - to_integer(Hcomp_bound_fall_i)); 
				-- upper current bound reached 
				if imeas_s  >= i_upper_s then 
					--hyst_state_next_s <= FIRST_DOWN; -- EDIT TSOL4
                    hyst_state_next_s <= DELAY_U1;
					t1_start_next_s <= '1';
                    delay_fall_next_2nd_s <= to_integer(Tss_bound_fall_i);
						  dly_cnt_next_s <= 0;
				end if;
			
			when NEW_STEP_DOWN => 
                --TSOL: Compensation-- Still update the limits here.
                i_upper_next_s <= iset_s + (H0_C - to_integer(Hcomp_bound_rise_i)); 
                i_lower_next_s <= iset_s - (H0_C - to_integer(Hcomp_bound_fall_i)); 
				-- lower current bound reached 
				if imeas_s  < i_lower_s then 
					--hyst_state_next_s <= NEW_STEP_UP; -- EDIT TSOL
                    hyst_state_next_s <= DELAY_D1;
                    delay_rise_next_2nd_s	<= to_integer(Tss_bound_i);
                    delay_fall_next_2nd_s <= to_integer(Tss_bound_fall_i);
				end if;
			--Tsol: Added State
            when DELAY_U1 => 
				-- waiting for the time delay of the current
                if dly_cnt_s  < CNT_MIN OR dly_cnt_s < delay_fall_2nd_s - NINTERLOCK_G then 
					--if dly_cnt_s = CNT_MIN_FALL-2 then
                 --       dly_cnt_next_s <= dly_cnt_s +1; 
                   --     delay_fall_next_2nd_s <= to_integer(Tss_bound_fall_i);
                    --else
                        dly_cnt_next_s <= dly_cnt_s +1;
                -- end if;
				else 
					dly_cnt_next_s <= 0; 
					hyst_state_next_s <= FIRST_DOWN; 
            end if;

			--Tsol: Added State
            when DELAY_D1 => 
				-- waiting for the time delay of the current
                if dly_cnt_s  < CNT_MIN  OR dly_cnt_s  < (delay_rise_next_2nd_s + NINTERLOCK_G)  then 
					dly_cnt_next_s <= dly_cnt_s +1; 
				else 
					dly_cnt_next_s <= 0;
					t1_start_next_s <= '1';  
					hyst_state_next_s <= DELAY_U1; 
                end if;

			when FIRST_DOWN => 
				t1_start_next_s <= '0';
				-- lower current bound reached, 
				--if imeas_s < i_lower_s then 
					if phase_shift_en = '1' then
						hyst_state_next_s <= DELAY_2;
						t2_start_next_s <= '1';
                        delay_rise_next_2nd_s	<= to_integer(Tss_bound_i);
					else 
						hyst_state_next_s <= DELAY_D1;
					end if; 
				--end if; 

			--Tsol: Added State
            when DELAY_2 => 
				-- waiting for the time delay of the current
                if dly_cnt_s  < CNT_MIN OR dly_cnt_s  < delay_rise_2nd_s + NINTERLOCK_G then 
					dly_cnt_next_s <= dly_cnt_s +1; 
				else 
					dly_cnt_next_s <= 0; 
					hyst_state_next_s <= SECOND_UP; 
                end if; 	

			when SECOND_UP => 
				t2_start_next_s <= '0'; 
				--if imeas_s  >= i_upper_s then 
					--if phase_shift_en = '1' then -- all modules first NEW_STEP mode passed 			TSOL: WAS THIS ALREADY COMMENTED OUT??
						hyst_state_next_s <= DELAY_3;
                        dly_cnt_next_s <= 0; 
						i_upper_next_s <= iset_s + (to_integer(hss_bound_i));
						i_lower_next_s <= iset_s - (to_integer(hss_bound_i)); 
				--else 
					--	hyst_state_next_s <= FIRST_DOWN; TSOL: WAS THIS ALREADY COMMENTED OUT??
					--	t1_start_next_s <= '1';TSOL: WAS THIS ALREADY COMMENTED OUT??
					--end if; TSOL: WAS THIS ALREADY COMMENTED OUT??
				--end if;

			--Tsol: Added State: Edit... This is waiting the minimum time, then we are passing the next time instantd! Everything should happen inside the PHASE SHIFT! I think I already 
            when DELAY_3 => 
				-- waiting for the time delay of the current
                if dly_cnt_s  < CNT_MIN then 
					dly_cnt_next_s <= dly_cnt_s +1; 
				else 
					dly_cnt_next_s <= 0; 
					hyst_state_next_s <= PHASE_SHIFT;
                    delay_rise_next_3rd_s	<= to_integer(Tss2_bound_i);
                    delay_Delta_rise_next_s	<= to_integer(Tss2_bound_i) +  to_integer(deltaT_i);
                    delay_fall_next_3rd_s	<= to_integer(Tss2_bound_fall_i);
                    delay_Delta_fall_next_s	<=  delay_fall_2nd_s/2 + to_integer(Tss2_bound_fall_i)/2 + to_integer(deltaT_fall_i) - CNT_MIN;
                end if;
	
			when PHASE_SHIFT =>
				-- adjust lower current bound still if calculation took longer 
				if MY_NUMBER_G /= 0 and deltaH_ready_i = '1' then -- 
					i_lower_next_s <= iset_s - to_integer(hss_bound_i) - to_integer(deltaH_i) ;--; --iset_s - H0_C - to_integer(signed(deltaH_s)); --
                    delay_Delta_fall_next_s <= delay_fall_2nd_s/2 + to_integer(Tss2_bound_fall_i)/2 + to_integer(deltaT_fall_i) - CNT_MIN;
                    delay_Delta_rise_next_s	<= to_integer(Tss2_bound_i) +  to_integer(deltaT_i);
				end if; 
				
				--if (imeas_s < i_lower_s) and (interl_s = '0') then
                if (dly_cnt_s  < delay_Delta_fall_s - NINTERLOCK_G) OR (interl_s = '1') then
                    dly_cnt_next_s <= dly_cnt_s +1; 
                else
					hyst_state_next_s <= DELAY_4;
                    dly_cnt_next_s <= 0; 
					i_lower_next_s <= iset_s - to_integer(hss_bound_i) ;
                    delay_Delta_rise_next_s	<= to_integer(Tss2_bound_i) +  to_integer(deltaT_i);

				end if;

			--Tsol: Added State
            when DELAY_4 => 
				-- waiting for the time delay of the current
                if dly_cnt_s  < CNT_MIN OR dly_cnt_s  < delay_Delta_rise_s + NINTERLOCK_G  then 
					dly_cnt_next_s <= dly_cnt_s +1; 
				else 
					dly_cnt_next_s <= 0; 
					hyst_state_next_s <= THIRD_UP; 
                end if;  	
-------------------------------------------------------------------------------------------------------
			when THIRD_UP => 
				--if imeas_s  >= i_upper_s then 
					hyst_state_next_s <= DELAY_5; 
				--end if;
			--Tsol: Added State
            when DELAY_5 => 
				-- waiting for the time delay of the current
                if dly_cnt_s  < CNT_MIN OR dly_cnt_s  < delay_fall_3rd_s - NINTERLOCK_G then 
					dly_cnt_next_s <= dly_cnt_s +1; 
				else 
					dly_cnt_next_s <= 0; 
					hyst_state_next_s <= THIRD_DOWN; 
                end if;   				
			
			when THIRD_DOWN => 
				--if imeas_s  < i_lower_s then
					-- see if done enough cylces in hysteresis 
					if cnt_cycle_s = N_CYCLE_REST_G then -- went through all cycles 
						hyst_state_next_s <= PWM_CONTROL; -- going back to PWM control 
						cnt_cycle_next_s <= 0; 
						nreset_pwm_next_s <= '0'; 
					else 
						hyst_state_next_s <= DELAY_6; -- do one more cycle
						cnt_cycle_next_s <= cnt_cycle_s + 1; 
					end if; 
				--end if; 	
				nreset_phase_shift_s <= '0'; 

			--Tsol: Added State
            when DELAY_6 => 
				-- waiting for the time delay of the current
                if dly_cnt_s  < CNT_MIN OR dly_cnt_s  < delay_rise_3rd_s + NINTERLOCK_G then 
					dly_cnt_next_s <= dly_cnt_s +1; 
				else 
					dly_cnt_next_s <= 0; 
					hyst_state_next_s <= THIRD_UP; 
                end if;   

			when others => 
				hyst_state_next_s <= PWM_CONTROL; 
			end case; 	
	end process; 

	--! @brief Output Logic 
	--! @details: Logic for Hysteresis OUTPUT 
	--! @details: Intentionally no register to reduce delay 
	switch_logic: process(hyst_state_s, pwm_switch1_i) 
	begin 
					
		case hyst_state_s is 
			when IDLE => 
				sw1_s <= '0'; 
			when PWM_CONTROL => 
				sw1_s <= pwm_switch1_i;  				
			when NEW_STEP_UP => 
				sw1_s <= '1';
            when DELAY_U1=> 
				sw1_s <= '0'; 
			when NEW_STEP_DOWN => 
				sw1_s <= '0';
            when DELAY_D1=> 
				sw1_s <= '1';  	
			when FIRST_DOWN => 
				sw1_s <= '0';
            when DELAY_2=> 
				sw1_s <= '1';  			
			when SECOND_UP => 
				sw1_s <= '1';
            when DELAY_3=> 
				sw1_s <= '0';   		
			when PHASE_SHIFT => 
				sw1_s <= '0';
            when DELAY_4=> 
				sw1_s <= '1';   					
			when THIRD_UP => 
				sw1_s <= '1';
            when DELAY_5=> 
				sw1_s <= '0';   						
			when THIRD_DOWN => 
				sw1_s <= '0'; 
            when DELAY_6=> 
				sw1_s <= '1';  		
			when others => 
				sw1_s <= '0'; 		
			end case;
	end process; 
	
	-- interlocking block 
	interlock_inst:  interlocking 
	generic map( NINTERLOCK_G 	=> NINTERLOCK_G
			)		
	port map(clk_i		=> clk_i,
			nreset_i 	=> nreset_i, 
			nsoftreset_i=> nsoftreset_i, 
			sw1_i		=> sw1_s,
			sw2_i		=> pwm_switch2_i, 
			int_sw1_o	=> int_sw1_s,
			int_sw2_o	=> int_sw2_s,		
			interl_o	=> interl_s
			);
	
-- Output assignments 
switch1_o <=int_sw1_s;
switch2_o <=int_sw2_s;
hyst_t1_o <= t1_start_s; 
hyst_t2_o <= t2_start_s; 
hyst_o <= hyst_s; 
nreset_pwm_o <= nreset_pwm_s;
i_upper_o <= to_signed(i_upper_s,DATAWIDTH_G); 	
i_lower_o <= to_signed(i_lower_s,DATAWIDTH_G); 			 		

end structural; 