--==========================================================
-- Unit		:	M3TC_Master(rtl)
-- File		:	M3TC_Master.vhd
-- Purpose	:	
-- Author	:	Pascal Zähner - HPE - ETH Zuerich
-- Device	:	Altera FPGA - Cyclone V
-- EDA syn	:	Altera Quartus II
-- EDA sim	:	Modelsim SE 10.1c
-- misc		:	--
-- depdcy	:	
-- testbench: .vhd 
--==========================================================

-- use standard library
library ieee;
library work;
--! Use logic elements
use ieee.std_logic_1164.all;
--! Use numeric elements
use ieee.numeric_std.all;

entity M3TC_Master is
	generic(
		T_INT_1200_G			: integer := 4;	-- Interlock delay for the 1200V module, master
		T_INT_1700_G			: integer := 8;	-- Interlock delay for the 1700V module, master
		T_DELAY_G				: integer := 1000;	-- delay time after switching: don't sense the voltage during this time 
		T_VOLT_G				: integer := 1000;	-- delay time due to the voltage measurement delay! don't sense the voltage during this time 
		N_NUMBERMODULES_G 		: integer := 10;	-- number of connected M3TC modules
		N_MODULES_STEP_G 		: integer := 10; -- number modules inserted in a step
		N_VOLTHIGH_G			: integer := 550;	-- upper voltage boundary for turning on a M3TC stage
		N_VOLTLOW_G				: integer := 1;	-- lower voltage boundary for turning on a M3TC stage
		N_CURRENTHIGH_G			: integer := 90; -- how many % of the reference current have to be reached
		N_CURRENTLOW_G			: integer := 10; -- unused
		N_HIGHVOLT_S1_G			: integer := 550; -- Voltage of the first stage
		N_HIGHVOLT_SX_G			: integer := 1100; -- Voltage of all other stages
		MODE_IDLE_G	 			: std_logic_vector(3 downto 0) := "0000";  -- 0
		MODE_CHARGE_G	 		: std_logic_vector(3 downto 0) := "0001";  -- 1
		MODE_DISCHARGE_G		: std_logic_vector(3 downto 0) := "0010"; -- 2
		MODE_RESET_G	 		: std_logic_vector(3 downto 0) := "0100"; -- 4
		MODE_OP_G		 		: std_logic_vector(3 downto 0) := "0011"; -- 3
		MODE_BYPASS_G		 	: std_logic_vector(3 downto 0) := "0101" -- 5
	);
	port(
		nreset_i 		: in std_logic;                     -- Asynchronous reset
		clk_i 			: in std_logic;                     -- main clock
		mode_i 			: in std_logic_vector(2 downto 0);  -- mode receive from top control
		fault_i			: in std_logic;                     -- binary fault report from stages
		voltage_i		: in std_logic_vector(11 downto 0); -- voltage measurement, 12 bit
		current_ref_i	: in std_logic_vector(11 downto 0); -- refernce current, 12 bit
		current_con_i	: in std_logic_vector(11 downto 0); -- measured current, 12 bit
		volt_S1_i		: in std_logic_vector(11 downto 0); -- unused
		volt_S2_i		: in std_logic_vector(11 downto 0); -- unused
		sw_Vprecontrol_o: out std_logic_vector(1 downto 0); -- signalize switching to hybrid controller
		modules_o		: out std_logic_vector(3+N_NUMBERMODULES_G*2 downto 0) -- mode and gates for M3TC stages
	);
end M3TC_Master ;

architecture rtl of M3TC_Master  is
-- ================== CONSTANTS ==================================================
		-- constant for feed forward V precontrol
	constant ADD_SWITCH_C : std_logic_vector(1 downto 0) := "01"; --! Add voltage 
	constant SUB_SWITCH_C : std_logic_vector(1 downto 0) := "10"; --! Subtract voltage
	constant IDL_SWITCH_C : std_logic_vector(1 downto 0) := "00"; --! Idle

	constant T_PULSE_G : integer := 1000; --! Extra Wait and STOP SENSING after the pulse

-- ================== COMPONENTS =================================================
-- =================== STATES ====================================================
	-- definitions for FMS
	TYPE my_states is (IDLE, CHARGE, DISCHARGE, OP, BYPASS, RESET_ALL, INTERLOCKING_NEG_1,INTERLOCKING_NEG_2, INTERLOCKING_POS_1, INTERLOCKING_POS_2, WAIT_SENSE, WAIT_SENSE_550, STOP_SENSE_550, PULSE, STOP_SENSE, WAIT_PULSE);

	-- =================== SIGNALS ===================================================
	signal state_s, state_next_s : my_states := IDLE;
	
	-- definition of output signals
	signal gates_s, gates_next_s	: std_logic_vector(N_NUMBERMODULES_G*2-1 downto 0) := (others => '0');
	signal mode_s,mode_next_s	: std_logic_vector(3 downto 0) := (others => '0');
		
	-- voltage and current surveilance signals 
	signal voltInsert_s, voltInsert_next_s : 		integer range 0 to 3 := 0; 
	signal currentInsert_s, currentInsert_next_s:	integer range 0 to 5 := 0;
	signal current_ref_s, current_ref_del_s: 		std_logic_vector(11 downto 0); -- current and delayed version of current_ref_i
	
	--signal counter: integer range 0 to 1000;	-- define equaly to the biggest delay
	signal cnt_550: integer range 0 to 2 := 0;	-- just needed to simulate error, think how to handle this case
	-- cnt_550 can be deleted if the fault is later send to the top level control.
	
	-- State counter 
	signal cnt_state_s, cnt_state_next_s: integer range -(N_NUMBERMODULES_G*2+2) to (N_NUMBERMODULES_G*2+2) := 0; -- register, logic output and delayed register 
	signal tester: integer range 0 to 1000;	-- define equaly to the biggest delay
	signal stop_sensing_s, stop_sensing_next_s: std_logic := '0'; 
	constant c_ones : std_logic_vector(gates_next_s'range) := (others => '1');
	
	-- signal feed forward V precontrol 
	signal sw_Vprecontrol_s, sw_Vprecontrol_next_s : std_logic_vector(1 downto 0) := IDL_SWITCH_C; 

	-- timer 
	constant CNT_TOP_C                          : integer := 4000; 
	signal timer_start_s						: std_logic := '0'; 
	signal timer_top_s, timer_top_next_s		: integer range 0 to CNT_TOP_C := 0; 
	signal timer_end_s, timer_end_next_s		: std_logic := '0'; 
	signal timer_val_s, timer_val_next_s		: integer range 0 to CNT_TOP_C := 0; 
	
begin

----------------- Timer -------------------------- 
CNT_LOG: process( timer_val_s, timer_start_s,timer_top_s)
	begin 
		if timer_start_s = '1' then 
			timer_val_next_s <= 0; 
			timer_end_next_s 	   <= '0'; 
		elsif timer_val_s < timer_top_s then 
			timer_val_next_s <= timer_val_s + 1; 
			timer_end_next_s 	   <= '0'; 
		else 
			timer_val_next_s <= timer_val_s; 
			timer_end_next_s 	   <= '1'; 
		end if; 
	end process; 
	
CNT_REG: process(clk_i,nreset_i)
begin 
	if nreset_i = '0' then 
		timer_end_s <= '0';
		timer_val_s <= CNT_TOP_C;
	elsif rising_edge(clk_i) then 
		timer_end_s   <= timer_end_next_s;
		timer_val_s	<= timer_val_next_s;	
	end if; 
end process; 
----------------------------------------------------

REG: process(clk_i, nreset_i)
	--VARIABLE counter: integer range 0 to 40;
	begin 
		if nreset_i= '0' then 
			state_s 		<= IDLE;
			sw_Vprecontrol_s<= IDL_SWITCH_C; 
			cnt_state_s 	<= 0; 
			voltInsert_s	<= 0; 
			currentInsert_s <= 0; 
			current_ref_s 	<= (others => '0'); 
			current_ref_del_s<=(others => '0');  
			timer_top_s		<= CNT_TOP_C; 
			mode_s			<= (others => '0'); 
			gates_s			<= (others => '0'); 
			stop_sensing_s	<= '0'; 
		elsif rising_edge(clk_i) then 
			sw_Vprecontrol_s<= sw_Vprecontrol_next_s; 
			cnt_state_s 	<= cnt_state_next_s;  
			voltInsert_s	<= voltInsert_next_s;
			currentInsert_s <= currentInsert_next_s; 
			current_ref_s 	<= current_ref_i; 
			current_ref_del_s<=current_ref_s; 
			timer_top_s 	<= timer_top_next_s; 
			mode_s			<= mode_next_s; 
			gates_s			<= gates_next_s; 
			state_s 		<= state_next_s;
			stop_sensing_s 	<= stop_sensing_next_s;
		end if; 
	end process; 


	
IN_LOG: process(state_s, mode_i, fault_i, voltInsert_s, currentInsert_s,timer_top_s,mode_s,cnt_state_s,stop_sensing_s,gates_s,timer_end_s, current_con_i)--TSOL: Added timer_val_s in the sensitivity list
	begin
	
	-- default assignments to avoid latches 
	state_next_s		<= state_s; 
	cnt_state_next_s	<= cnt_state_s; 
	timer_top_next_s	<= timer_top_s; 
	mode_next_s			<= mode_s; 
	stop_sensing_next_s	<= stop_sensing_s; 		
	gates_next_s		<= gates_s; 
	timer_start_s		<= '0'; 
	sw_Vprecontrol_next_s<= IDL_SWITCH_C; 
	
	if (fault_i = '0') then -- any fault is present (fault or not ready) turn off, inverted logic (to prevent losing connection)
		-- set all off and next state is idle
		mode_next_s <= (others => '0');
		gates_next_s <= (others => '0');	-- here gate is activ high, invert in output stage.		
		-- inform master about the fault, To Do
		cnt_state_next_s <= 0;
	else
		case state_s is
			when IDLE =>
				-- possible states: IDLE, CHHARGE, DISCHARGE, RESET_ALL, OP
				if (unsigned(mode_i) = 1 ) then -- go to charge, independent of gate signals
					-- set modes accoring 
					mode_next_s <= MODE_CHARGE_G;
					-- maybe check which to charge and set them here (00 not, 11 charge)
					gates_next_s <= (others => '0');
					state_next_s <= CHARGE;
				elsif (unsigned(mode_i) = 2) then -- go to disarge, independent of gate signals
					-- set modes accoring 
					mode_next_s <= MODE_DISCHARGE_G;
					-- maybe check which to discharge and set them here (00 not, 11 discharge)
					gates_next_s <= (others => '0');
					state_next_s <= DISCHARGE;
				elsif (unsigned(mode_i) = 3) then -- go into OP
					-- set modes accoring 
					mode_next_s <= MODE_OP_G;
					-- maybe check which to reset and set them here (00 not, 11 reser stage)
					gates_next_s <= (others => '1');
					state_next_s <= OP;
					cnt_state_next_s <= 0;
				elsif (unsigned(mode_i) = 4 ) then -- go to op
					-- set modes accoring 
					mode_next_s <= MODE_RESET_G;
					-- from here go to loop operation, all on (loop).
					gates_next_s <= (others => '0');
					state_next_s <= RESET_ALL;
				elsif (unsigned(mode_i) = 5) then -- go into BYPASS
					-- set modes accoring 
					mode_next_s <= MODE_BYPASS_G;	-- in local control needed to go to bypass.
					gates_next_s <= (others => '1');
					state_next_s <= BYPASS;
				else	-- in any other case go to IDLE
					-- set mode to IDLE 
					mode_next_s <= MODE_IDLE_G;
					-- set all gates to low)
					gates_next_s <= (others => '0');
					state_next_s <= IDLE;
			end if;
			
			when CHARGE =>
				if (unsigned(mode_i) /= 1 ) then -- go back to idle
					-- set mode to IDLE 
					mode_next_s <= MODE_IDLE_G;
					-- set all gates to low)
					gates_next_s <= (others => '0');
					state_next_s <= IDLE;
				end if;
				
			when DISCHARGE =>
				if (unsigned(mode_i) /= 2) then -- go back to idle
					-- set mode to IDLE 
					mode_next_s <= MODE_IDLE_G;
					-- set all gates to low)
					gates_next_s <= (others => '0');
					state_next_s <= IDLE;
				end if;
				
			when OP =>
				stop_sensing_next_s <= '0'; 
				
				if (unsigned(mode_i) /= 3) then -- go back to idle
					-- set mode to IDLE 
					mode_next_s <= MODE_IDLE_G;
					-- set all gates to low)
					gates_next_s <= (others => '0');
					state_next_s <= IDLE;
				else
					mode_next_s <= MODE_OP_G;
					if ( currentInsert_s > 0 ) then -- check current step if all is bypassed. TSOL: WHY DOES THIS CHECK ONLY WHEN ALL OF THEM ARE BYPASSED? UP: I REMOVED IT (gates_s = c_ones  AND ...)
						if(currentInsert_s = 1) then
							-- step up pulse
							if(N_MODULES_STEP_G > N_NUMBERMODULES_G) then
								for i in 0 to N_NUMBERMODULES_G-1 loop
									gates_next_s(1+2*i downto 2*i) <= "10";
								end loop;
								state_next_s <= PULSE;
							else
								for i in 0 to N_MODULES_STEP_G-1 loop
									gates_next_s(1+2*i downto 2*i) <= "10";
								end loop;
								state_next_s <= PULSE;
							end if; 
					elsif ( currentInsert_s = 2 ) then -- CHANGED BY TSOL
							-- step down pulse
                            if ( gates_s = c_ones) then
                                if(N_MODULES_STEP_G > N_NUMBERMODULES_G) then
                                    for i in 0 to N_NUMBERMODULES_G-1 loop
                                        gates_next_s(1+2*i downto 2*i) <= "01";
                                    end loop;
                                    state_next_s <= PULSE;
                                else
                                    for i in 0 to N_MODULES_STEP_G-1 loop
                                        gates_next_s(1+2*i downto 2*i) <= "01";
                                    end loop;
                                    state_next_s <= PULSE;
                                end if;
                            elsif (gates_s(1 downto 0) = "10")then  -- NOT BYPASSED (Stage 1 is assumed here to be on) -- TSOL
                                    for i in 0 to N_MODULES_STEP_G-1 loop
                                        gates_next_s(1 downto 0) <= "11"; -- BYPASS the first
                                    end loop;
                                    state_next_s <= PULSE;
                                    timer_start_s <= '1'; --TSOL: ADDED NOW
                            end if;
                        end if;
					elsif(stop_sensing_s = '0') then -- check voltage and check what to do
						if(voltInsert_s = 2 and signed(current_ref_s) > 100 ) then-- TSOL: ADDED THE CURRENT_REF_I PART (for start up problems)
						-- insert in positive direction
							if(cnt_state_s >= 0) then
								if (cnt_state_s < 2*N_NUMBERMODULES_G-1) then -- maximum cnt_state not reached yet 	
									-- insert positive voltage
									if (cnt_state_s mod 2 = 0) then  
										-- insert 550V stage
										gates_next_s(1 downto 0) <= "10";
										-- start counter to stop voltage measurement during switching
										state_next_s <= WAIT_SENSE_550; 
										timer_start_s<= '1'; 
										cnt_state_next_s <= cnt_state_s + 1; 
									else
										-- insert 1100V stage after delay
										state_next_s <= INTERLOCKING_POS_1;
										timer_start_s<= '1'; 
									end if;
									
								else
									-- send error to PLC
									cnt_550 <= 1;
								end if;	
							else
								-- remove one negative stage 
								if ((-cnt_state_s) mod 2 = 0) then --550V not active
									-- turn off 1100V stage after delay
									state_next_s <= INTERLOCKING_POS_1;
									timer_start_s<= '1'; 
								else
									-- turn off 550V stage
									gates_next_s(1 downto 0) <= "11";
									state_next_s <= WAIT_SENSE; 
									timer_start_s<= '1'; 
									cnt_state_next_s <= cnt_state_s + 1; 		
								end if;
							end if;
						elsif(voltInsert_s = 1 and signed(current_ref_s) > 100) then-- TSOL: ADDED THE CURRENT_REF_I PART
							if(cnt_state_s > 0) then
								-- insert positive voltage
									if (cnt_state_s mod 2 = 0) then
										state_next_s <= INTERLOCKING_NEG_1;
										timer_start_s<= '1'; 
									else
										-- turn off 550V stage
										sw_Vprecontrol_next_s <= ADD_SWITCH_C;
										gates_next_s(1 downto 0) <= "11";
										state_next_s <= WAIT_SENSE; 
										timer_start_s<= '1'; 
										cnt_state_next_s <= cnt_state_s - 1;
									end if;
							else
								-- insert negative voltage
								if ((-cnt_state_s) < 2*N_NUMBERMODULES_G-1) then
									if ((-cnt_state_s) mod 2 = 0) then
										-- insert -550V stage
										gates_next_s(1 downto 0) <= "01";
										state_next_s <= WAIT_SENSE; 
										timer_start_s<= '1'; 
										cnt_state_next_s <= cnt_state_s - 1; 
									else
										state_next_s <= INTERLOCKING_NEG_1;
										timer_start_s<= '1'; 
									end if;
								else
									-- send error to PLC, ToDo
									cnt_550 <= 1;
								end if;
							end if;
						else
							-- stay
						state_next_s <= OP;
						end if;
					end if;

				end if;
				
			when RESET_ALL =>
				if (unsigned(mode_i) /= 4) then
					-- set mode to IDLE 
					mode_next_s <= MODE_IDLE_G;
					-- set all gates to low)
					gates_next_s <= (others => '0');
					state_next_s <= IDLE;
				end if;
				
			when INTERLOCKING_POS_1 =>
				stop_sensing_next_s <= '1'; 
				timer_top_next_s <= T_INT_1700_G; 
				
				if	(cnt_state_s >= 0) then 
					-- new: turn on 1100V stage
					gates_next_s(abs(cnt_state_s)+2 downto abs(cnt_state_s) +1) <= "10";
					
				else 
					-- insert -550V stage
					gates_next_s(1 downto 0) <= "01";
				end if; 
				
				if timer_end_s = '1' then 
					timer_start_s<= '1';
					state_next_s <= INTERLOCKING_POS_2; 
					sw_Vprecontrol_next_s <= SUB_SWITCH_C; 					
				end if; 
				
			when INTERLOCKING_POS_2 =>
				stop_sensing_next_s <= '1';
 
				
				if(cnt_state_s > 0) then
					-- turn off 550V stage
					gates_next_s(1 downto 0) <= "11";
					timer_top_next_s <= T_INT_1200_G;
				else
					-- turn off 1100V
					gates_next_s((-cnt_state_s)+1 downto (-cnt_state_s)) <= "11";
					timer_top_next_s <= T_INT_1700_G;
				end if;
				
				if timer_end_s = '1' then 
					state_next_s <= WAIT_SENSE; 
					timer_start_s<= '1'; 
					cnt_state_next_s <= cnt_state_s + 1;  
				end if;
				
				
			when INTERLOCKING_NEG_1 =>
				stop_sensing_next_s <= '1'; 
				timer_top_next_s <= T_INT_1200_G; 
				
				if	(cnt_state_s > 0) then 
					-- turn on 550V stage
					gates_next_s(1 downto 0) <= "10";		
				else 
					-- turn off 550V stage
					gates_next_s(1 downto 0) <= "11";
				end if; 
				
				if timer_end_s = '1' then 
					state_next_s <= INTERLOCKING_NEG_2; 
					timer_start_s <= '1'; 
					sw_Vprecontrol_next_s <= ADD_SWITCH_C; 
				end if; 
				
				
			when INTERLOCKING_NEG_2 =>
				stop_sensing_next_s <= '1'; 			
				if(cnt_state_s > 0) then
					-- turn off 1100V stage
					gates_next_s(cnt_state_s+1 downto cnt_state_s) <= "11";
					timer_top_next_s <= T_INT_1700_G;
				else
					-- insert -1100V 
					gates_next_s(-(cnt_state_s)+2 downto -(cnt_state_s)+1) <= "01";	
					timer_top_next_s <= T_INT_1700_G;
				end if;
				
				if timer_end_s = '1' then 
					state_next_s <= WAIT_SENSE; 
					timer_start_s<= '1'; 
					cnt_state_next_s <= cnt_state_s - 1;  
				end if;
			
			when WAIT_SENSE_550 => 	
				stop_sensing_next_s <= '1'; 
				timer_top_next_s <= T_DELAY_G; 
				
				if timer_end_s = '1' then 
					state_next_s <= STOP_SENSE_550;
					sw_Vprecontrol_next_s <= SUB_SWITCH_C;
                    timer_start_s <= '1';
				end if; 

---------------------------------------------------------------------------
-- Implemented by TSOL:
			when STOP_SENSE_550 => 	
				stop_sensing_next_s <= '1';     
				timer_top_next_s <= T_VOLT_G;   --wait the delay time 
				if timer_end_s = '1' then       
					state_next_s <= OP;         
				end if;                         
-- End implementation by TSOL	
---------------------------------------------------------------------------

			when WAIT_SENSE => 	
				stop_sensing_next_s <= '1';
				timer_top_next_s <= T_DELAY_G;   --TSOL: I think this should be at least the voltage delay time, because the transition happens immediately without the interlocking playing a role! (It was T_DELAY_G before. Then made it T_VOLT_G)
				if timer_end_s = '1' then       
					state_next_s <= STOP_SENSE; --TSOL : Maybe I need to inform the controller for the pre-control too???  
                    timer_start_s <= '1';    
				end if; 

-- Implemented by TSOL:
			when STOP_SENSE => 	
				stop_sensing_next_s <= '1';     
				timer_top_next_s <= T_VOLT_G;   --wait the delay time 
				if timer_end_s = '1' then       
					state_next_s <= OP;         
				end if;                         
-- End implementation by TSOL

-- Implemented by TSOL:
			when WAIT_PULSE => 	
				stop_sensing_next_s <= '1';     
				timer_top_next_s <= T_PULSE_G;   --wait the delay time 
				if timer_end_s = '1' then       
					state_next_s <= WAIT_SENSE; 
					timer_start_s		<= '1';         
				end if;                         
-- End implementation by TSOL		
			
			when BYPASS => -- wait until mode changes again, then turn off all.
				if (unsigned(mode_i) /= 5) then
					-- set mode to IDLE 
					mode_next_s <= MODE_IDLE_G;
					-- set all gates to low)
					gates_next_s <= (others => '0');
					state_next_s <= IDLE;
				end if;
			
			when PULSE =>
				if (currentInsert_s = 0) then
					-- return in state all bypassed
					gates_next_s <= (others => '1');
					state_next_s <= WAIT_PULSE;
					timer_start_s		<= '1'; 

-------------------TSOLA

                elsif (currentInsert_s = 2 and gates_s(1 downto 0) = "11" and signed(voltage_i) < 400 and signed(current_con_i) > signed(current_ref_s) + 300) and (timer_val_s > 399) then
					-- TSOL: special case --- when in negative pulse insert in negative direction if it is bypassed and the voltage is not enough
					for i in 0 to N_MODULES_STEP_G-1 loop
                        gates_next_s(1 downto 0) <= "01";
                    end loop;
					--state_next_s <= PULSE; Don't change the state
                    cnt_state_next_s <= cnt_state_s - 1;
					timer_start_s		<= '1'; 

                elsif (currentInsert_s = 4) then
					-- TSOL: special case --- One stage is left on because the steady state voltage is higher thamn 550V
					for i in 0 to N_MODULES_STEP_G-1 loop
                        gates_next_s(1 downto 0) <= "10";
                    end loop;
					state_next_s <= WAIT_PULSE;
                    cnt_state_next_s <= cnt_state_s + 1;
					timer_start_s		<= '1'; 


                elsif (currentInsert_s = 5) then
					-- TSOL: special case --- During pulse the stage was bypassed but it got a signal to get back to 10 state because the voltage was still too high!
					for i in 0 to N_MODULES_STEP_G-1 loop
                        gates_next_s(1 downto 0) <= "10";
                    end loop;
					state_next_s <= WAIT_PULSE;
                    --cnt_state_next_s <= cnt_state_s + 1;
					timer_start_s		<= '1'; 

                elsif (currentInsert_s = 3) then
					-- TSOL: special case --- 1stage left bypassed because the voltage was is higher than 650V
					for i in 0 to N_MODULES_STEP_G-1 loop
                        gates_next_s(1 downto 0) <= "11";
                    end loop;
					state_next_s <= WAIT_PULSE;
                    cnt_state_next_s <= cnt_state_s - 1; ---- REDUCE THE STATE? It has to be zero afterwards!
					timer_start_s		<= '1'; 


				elsif (unsigned(mode_i) /= 3) then
					-- set mode to IDLE 
					mode_next_s <= MODE_IDLE_G;
					-- set all gates to low)
					gates_next_s <= (others => '0');
					state_next_s <= IDLE;
				end if;
			when others =>
		end case;
	end if;
end process;

MeasurementV: process (voltInsert_s, stop_sensing_s, voltage_i)
	begin 	
		-- default assignment 
		voltInsert_next_s <= 0; 
		-- start logic here 
		if (stop_sensing_s = '0') then 
			voltInsert_next_s <= 0;
			-- check voltage
			if(signed(voltage_i) < N_VOLTLOW_G) then
				voltInsert_next_s <= 1;	-- insert negative  
			elsif (signed(voltage_i) > N_VOLTHIGH_G) then
				voltInsert_next_s <= 2;  -- insert positive 
			end if;	
		end if;
	end process;
	
MeasurementI: process (current_con_i, current_ref_s,current_ref_del_s, currentInsert_s)
begin 
	-- default assignment 
	currentInsert_next_s <= currentInsert_s; 
	
	-- check current
	if (currentInsert_s = 0) then		
		if(signed(current_ref_s) - signed(current_ref_del_s) > N_CURRENTHIGH_G) then
			currentInsert_next_s <= 1; -- positive step
		elsif (signed(current_ref_del_s) - signed(current_ref_s) > N_CURRENTHIGH_G) then
			currentInsert_next_s <= 2; -- negative step
		end if;
	elsif (currentInsert_s = 1) then 
		if(signed(current_con_i) > signed(current_ref_s) - 200) then -- TSOL: This is the percentage of the current that needs to be reached to take the stage off!!! HERE! NOT IN THE CONSTANT
			if(signed(current_ref_del_s) - signed(current_ref_s) > N_CURRENTHIGH_G) then
				currentInsert_next_s <= 2; -- negative step --TSOL: ?? I do not get this!
            else
                if (signed(voltage_i)>-50) then --- TSOL: CAREFUL HERE! THIS WILL KEEP THE STAGE ON IF THE VOLTAGE IS HIGHER THAN -50V
                    currentInsert_next_s <= 4;
                else
                    currentInsert_next_s <= 0;
                end if;
			end if;
		end if;

	elsif (currentInsert_s = 2) then
		if ((signed(current_con_i) < signed(current_ref_s) + 200)) then -- TSOL: This is the percentage of the current that needs to be reached to take the stage off!!! This will only stop if the current get negative!. 
			if(signed(current_ref_s) - signed(current_ref_del_s) > N_CURRENTHIGH_G) then
				currentInsert_next_s <= 1; -- positive step ?????
			else
                if (signed(voltage_i) < 650 and gates_s(1 downto 0) /= "01") then --- TSOL: CAREFUL HERE! When less than 650V and not already -1st negative... THIS IS ONLY FOR INTEGRATION OF 1 STAGE. KEEPS FIRST STAGE ON
                    currentInsert_next_s <= 3;
                elsif(signed(voltage_i) > 650 and gates_s(1 downto 0) = "11") then
                    currentInsert_next_s <= 5;
                else
                    currentInsert_next_s <= 0;
                end if;
			end if;
		end if;
	
   elsif (currentInsert_s = 4) then
        currentInsert_next_s <= 0; --set it back to zero.

   elsif (currentInsert_s = 5) then
        currentInsert_next_s <= 0; --set it back to zero.

   elsif (currentInsert_s = 3) then
        currentInsert_next_s <= 0; --set it back to zero.
   end if;

end process;


modules_o <= mode_s & gates_s;
sw_Vprecontrol_o <= sw_Vprecontrol_s ; 

end rtl;
