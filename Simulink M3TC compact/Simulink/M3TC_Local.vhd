--==========================================================
-- Unit		:	M3TC_Local(rtl)
-- File		:	M3TC_Local.vhd
-- Purpose	:	
-- Author	:	Pascal Zähner - HPE - ETH Zuerich
-- Device	:	Altera FPGA - MAX10
-- EDA syn	:	Altera Quartus Prime
-- EDA sim	:	Modelsim SE 10.1c
-- misc		:	--
-- depdcy	:		
-- testbench: tb_M3TC_Local.vhd 
--==========================================================

-- use standard library
library ieee;
library work;
--! Use logic elements
use ieee.std_logic_1164.all;
--! Use numeric elements
use ieee.numeric_std.all;

entity M3TC_Local is
	generic(
		T_INTERLOCKING_G	: integer := 499; -- number of cycles for interlocking, for 100 MHz t = n*10ns 
		T_DELAY_G			: integer := 40; -- number of cycles for delay to not sense, for 100 MHz t = n*10ns
		N_VDC_HIGH_G		: integer := 550; -- high voltage, dc link voltage
		N_VDC_LOW_G			: integer := 0	-- low voltage boundary
	);
	port(
		nreset_i 		: in std_logic; -- Asynchronous reset
		clk_i 			: in std_logic; -- main clock
		opt_gate1_i 	: in std_logic; -- optical signal, gate 1, inverted logic
		opt_gate2_i 	: in std_logic; -- optical signal, gate 2, inverted logic 
		opt_mode_i 		: in std_logic_vector(2 downto 0); -- mode transmitted from the master, decoded
		fault_i			: in std_logic; -- overall fault, OR connection
		fault_gate_i 	: in std_logic; -- fault at the full bridge
		fault_c_i		: in std_logic; -- fault at the charging IGBT
		fault_d_i		: in std_logic; -- fault at the discharging IGBT
		VoltMeas_i		: in std_logic_vector(11 downto 0); -- measured voltage, 12 bit value
		reset_gates_o	: out std_logic; -- reset full bridge gate driver
		reset_c_o		: out std_logic; -- reset charge gate driver
		reset_d_o 		: out std_logic; -- reset discharge gate driver
		reset_Ready_o	: out std_logic; -- reset ready verification blocks
		gate1_o 		: out std_logic; -- generated gate signal gate 1, inverted logic
		gate2_o 		: out std_logic; -- generated gate signal gate 2, inverted logic
		gate3_o 		: out std_logic; -- generated gate signal gate 3, inverted logic
		gate4_o 		: out std_logic; -- generated gate signal gate 4, inverted logic
		gateC_o 		: out std_logic; -- generated gate signal charge, inverted logic
		gateD_o 		: out std_logic -- generated gate signal discharge, inverted logic
	);
end M3TC_Local;

architecture rtl of M3TC_Local is
-- ================== CONSTANTS ==================================================
constant CNT_TOP_C						: integer := T_INTERLOCKING_G; --- used fot timer 

-- ================== COMPONENTS =================================================
-- =================== STATES ====================================================
TYPE my_states is (IDLE, CHARGE, DISCHARGE, OP_INS_POS, OP_INS_NEG, OP_LOOP, RESET_ALL, DELAY_IDLE, INTERLOCKING_LOOP, INTERLOCKING, BYPASS); -- state machine for local control

-- =================== SIGNALS ===================================================
signal state_s, state_next_s : my_states := IDLE; -- state of the state machine
signal gate1_s, gate1_next_s			: std_logic:='1'; -- gate signal 1, inverted logic
signal gate2_s, gate2_next_s 			: std_logic:='1'; -- gate signal 2, inverted logic
signal gate3_s, gate3_next_s 			: std_logic:='1'; -- gate signal 3, inverted logic
signal gate4_s, gate4_next_s 			: std_logic:='1'; -- gate signal 4, inverted logic
signal gateC_s, gateC_next_s 			: std_logic:='1'; -- gate signal charge, inverted logic
signal gateD_s, gateD_next_s 			: std_logic:='1'; -- gate signal discharge, inverted logic
signal resetGates_s, resetGates_next_s 	: std_logic:='1'; -- reset gates full bridge
signal resetC_s, resetC_next_s  		: std_logic:='1'; -- reset gate charge
signal resetD_s, resetD_next_s 			: std_logic:='1'; -- reset gate discharge
signal resetReady_s, resetReady_next_s 	: std_logic:='1'; -- reset ready verification block
signal VoltageMeas_s, VoltageMeas_next_s	: integer range 0 to 2 := 0; -- indicate voltage measurement boundary, 2: high, 0: low, 1 normal operation

-- timer
signal timer_start_s					: std_logic := '0'; -- start the timer
signal timer_top_s, timer_top_next_s	: integer range 0 to CNT_TOP_C := 0; -- stop value of the timer
signal timer_end_s, timer_end_next_s	: std_logic := '0'; -- signalize the end of the timer
signal timer_val_s, timer_val_next_s	: integer range 0 to CNT_TOP_C := 0; -- timer value
	
	
begin

----------------- Timer --------------------------
--! @brief Output Logic 
--! @details: Logic for Hysteresis OUTPUT  
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
	
--! @brief Output Logic 
--! @details: Logic for Hysteresis OUTPUT 	
CNT_REG: process(clk_i,nreset_i)
begin 
	if nreset_i = '0' then 
		timer_end_s <= '0';
		timer_val_s <= 0;
		timer_top_s <= CNT_TOP_C; 
	elsif rising_edge(clk_i) then 
		timer_end_s   <= timer_end_next_s;
		timer_val_s	<= timer_val_next_s;	
		timer_top_s <= timer_top_next_s;
	end if; 
end process; 
----------------------------------------------------

--! @brief Register update	
REG: process (clk_i, nreset_i)
	begin 
		if nreset_i= '0' then 
			gate1_s <= '1';
			gate2_s <= '1';
			gate3_s <= '1';
			gate4_s <= '1';
			gateC_s <= '1';
			gateD_s <= '1';
			resetGates_s <= '1';
			resetC_s <= '1';
			resetD_s <= '1';
			resetReady_s <= '1';
			state_s <= IDLE;
			VoltageMeas_s <= 1;
		elsif rising_edge(clk_i) then 
			state_s <= state_next_s;
			gate1_s <= gate1_next_s;
			gate2_s <= gate2_next_s;
			gate3_s <= gate3_next_s;
			gate4_s <= gate4_next_s;
			gateC_s <= gateC_next_s;
			gateD_s <= gateD_next_s;
			resetGates_s <= resetGates_next_s;
			resetC_s <= resetC_next_s;
			resetD_s <= resetD_next_s;
			resetReady_s <= resetReady_next_s;
			VoltageMeas_s <= VoltageMeas_next_s;
		end if; 
	end process;
	
IN_LOG: process(state_s, opt_gate1_i, opt_gate2_i, opt_mode_i, fault_i, 
				VoltageMeas_s, gate1_s, gate2_s, gate3_s, gate4_s, gateC_s, gateD_s,resetGates_s, 
				resetC_s, resetD_s, resetReady_s, fault_c_i, fault_d_i, fault_gate_i, timer_top_s,
				timer_end_s)
	begin
		-- Default assignments for avoiding Latches
		gate1_next_s <= gate1_s;         
		gate2_next_s <= gate2_s;         
		gate3_next_s <= gate3_s;         
		gate4_next_s <= gate4_s;         
		gateC_next_s <= gateC_s;         
		gateD_next_s <= gateD_s;         
		resetGates_next_s <= resetGates_s;
		resetC_next_s <= resetC_s;       
		resetD_next_s <= resetD_s;       
		resetReady_next_s <= resetReady_s;
		state_next_s <= state_s; 
		timer_start_s 		<= '0'; 
		timer_top_next_s	<= timer_top_s; 

		-- statemachine is changing with received mode.
		case state_s is
			when IDLE =>	-- starting point, depending on mode next state is set
				if (unsigned(opt_mode_i) = 1 AND VoltageMeas_s /= 2 AND fault_c_i = '0') then -- go to charge, independent of gate signals
					gate1_next_s <= '0';
					gate2_next_s <= '0';
					gate3_next_s <= '1';
					gate4_next_s <= '1';
					-- add delay
					state_next_s <= DELAY_IDLE;
					-- set timer value and start
					timer_start_s <= '1'; 
					
				elsif (unsigned(opt_mode_i) = 2 AND VoltageMeas_s /= 0 AND fault_d_i = '0') then -- go to disarge, independent of gate signals
					gate1_next_s <= '1';
					gate2_next_s <= '1';
					gate3_next_s <= '1';
					gate4_next_s <= '1';
					-- add short delay
					state_next_s <= DELAY_IDLE;
					-- set timer value and start
					timer_start_s <= '1'; 
				
				elsif (unsigned(opt_mode_i) = 3 AND fault_gate_i = '0') then -- go into operation
					if (opt_gate1_i = '1' AND opt_gate2_i = '0') then
						gate3_next_s <= NOT opt_gate1_i;
						gate2_next_s <= opt_gate2_i;
						state_next_s <= OP_INS_POS;
					elsif (opt_gate1_i = '0' AND opt_gate2_i = '0') then
						gate1_next_s <= opt_gate1_i;
						gate2_next_s <= opt_gate2_i;
						state_next_s <= OP_LOOP;
					elsif (opt_gate1_i = '0' AND opt_gate2_i = '1') then
						gate1_next_s <= opt_gate1_i;
						gate4_next_s <= NOT opt_gate2_i;
						state_next_s <= OP_INS_NEG;
					else
						gate1_next_s <= '1';
						gate2_next_s <= '1';
						gate3_next_s <= '1';
						gate4_next_s <= '1';
						state_next_s <= IDLE;
					end if;
				elsif (unsigned(opt_mode_i) = 4) then -- go to reset, independent of gate signals
					resetGates_next_s <= '0';
					resetC_next_s <= '0';
					resetD_next_s <= '0';
					resetReady_next_s <= '0';
					state_next_s <= RESET_ALL;
				elsif (unsigned(opt_mode_i) = 5) then -- go to reset, independent of gate signals
					resetGates_next_s <= '0';
					resetC_next_s <= '0';
					resetD_next_s <= '0';
					resetReady_next_s <= '0';
					gate1_next_s <= '0';
					gate2_next_s <= '0';
					gate3_next_s <= '1';
					gate4_next_s <= '1';
					state_next_s <= BYPASS;
				else	-- return from other states set all off
					gate1_next_s <= '1';
					gate2_next_s <= '1';
					gate3_next_s <= '1';
					gate4_next_s <= '1';
					gateC_next_s <= '1';
					gateD_next_s <= '1';
					state_next_s <= IDLE;
			end if;
			
			when CHARGE => -- charge mode, go back to idle if mode changes
				if (unsigned(opt_mode_i) /= 1 OR fault_c_i = '1') then --OR in_Volt = '2' ) then
					gate1_next_s <= '1';
					gate2_next_s <= '1';
					gate3_next_s <= '1';
					gate4_next_s <= '1';
					gateC_next_s <= '1';
					gateD_next_s <= '1';
					state_next_s <= IDLE;
				elsif (VoltageMeas_s = 2) then
					gateC_next_s <= '1';
				end if;
				
			when DISCHARGE => -- discharge mode, go back to idle if mode changes
				if (unsigned(opt_mode_i) /= 2 OR VoltageMeas_s = 0 OR fault_d_i = '1') then -- OR in_Volt = '0') then
					gate1_next_s <= '1';
					gate2_next_s <= '1';
					gate3_next_s <= '1';
					gate4_next_s <= '1';
					gateC_next_s <= '1';
					gateD_next_s <= '1';
					state_next_s <= IDLE;
				elsif (VoltageMeas_s = 0) then
					gateD_next_s <= '1';
				end if;
				
			when OP_INS_POS => -- operation mode, depending on gate signals enter different mode or back to IDLE
				if (unsigned(opt_mode_i) /= 3 OR (opt_gate1_i = '1' AND opt_gate2_i = '1') OR fault_gate_i = '1') then -- go to IDLE
					gate1_next_s <= '1';
					gate2_next_s <= '1';
					gate3_next_s <= '1';
					gate4_next_s <= '1';
					gateC_next_s <= '1';
					gateD_next_s <= '1';
					state_next_s <= IDLE;
				else
					if (opt_gate1_i = '0' AND opt_gate2_i = '0') then
						-- go to loop
						gate3_next_s <= NOT opt_gate1_i;
						-- add interlocking delay
						state_next_s <= INTERLOCKING_LOOP;
						-- set timer value and start 
						timer_start_s <= '1'; 
						
					elsif (opt_gate1_i = '0' AND opt_gate2_i = '1') then -- if switching 2 IGBTs, other delay state is used.
						-- go to negative insert
						gate2_next_s <= opt_gate2_i;
						gate3_next_s <= NOT opt_gate1_i;
						-- add interlocking delay
						state_next_s <= INTERLOCKING;
						-- set timer value and start it
						timer_start_s <= '1'; 
						
					end if;
				end if;
				
			when OP_INS_NEG =>  -- operation mode, depending on gate signals enter different mode or back to IDLE
				if (unsigned(opt_mode_i) /= 3 OR (opt_gate1_i = '1' AND opt_gate2_i = '1') OR fault_gate_i = '1') then
					gate1_next_s <= '1';
					gate2_next_s <= '1';
					gate3_next_s <= '1';
					gate4_next_s <= '1';
					gateC_next_s <= '1';
					gateD_next_s <= '1';
					state_next_s <= IDLE;
				else
					if (opt_gate1_i = '0' AND opt_gate2_i = '0') then
						-- go to loop
						gate4_next_s <= NOT opt_gate2_i;
						--add interlocking delay
						state_next_s <= INTERLOCKING_LOOP;
						-- set timer value and start it TODO
						timer_start_s <= '1'; 
		
					elsif (opt_gate1_i = '1' AND opt_gate2_i = '0') then -- if switching 2 IGBTs, other delay state is used.
						-- go to positive insert
						gate1_next_s <= opt_gate1_i;
						gate4_next_s <= NOT opt_gate2_i;
						-- add interlocking delay
						state_next_s <= INTERLOCKING;
						-- set timer value and start it TODO
						timer_start_s <= '1'; 

					end if;
				end if;

				
			when OP_LOOP => -- operation mode, depending on gate signals enter different mode or back to IDLE
				if (unsigned(opt_mode_i) /= 3 OR (opt_gate1_i = '1' AND opt_gate2_i = '1') OR fault_gate_i = '1') then
					gate1_next_s <= '1';
					gate2_next_s <= '1';
					gate3_next_s <= '1';
					gate4_next_s <= '1';
					gateC_next_s <= '1';
					gateD_next_s <= '1';
					state_next_s <= IDLE;
				else
					if (opt_gate1_i = '0' AND opt_gate2_i = '1') then
						-- go to negative insert
						gate2_next_s <= opt_gate2_i;
						-- add interlocking delay
						state_next_s <= INTERLOCKING_LOOP;
						-- set timer value and start it TODO
						timer_start_s <= '1'; 

					elsif (opt_gate1_i = '1' AND opt_gate2_i = '0') then
						-- go to positive insert
						gate1_next_s <= opt_gate1_i;
						-- add interlocking delay
						state_next_s <= INTERLOCKING_LOOP;
						-- set timer value and start it TODO
						timer_start_s <= '1'; 

					end if;
				end if;
				
			when RESET_ALL => -- state to reset gate drivers, if done go back to idle
				if (unsigned(opt_mode_i) /= 4) then
					resetGates_next_s <= '1';
					resetC_next_s <= '1';
					resetD_next_s <= '1';
					resetReady_next_s <= '1';
					state_next_s <= IDLE;
				end if;
			when DELAY_IDLE =>
				-- wait before turning on charge or discharge switch
				timer_top_next_s <= T_DELAY_G; 
				if timer_end_s = '1' then  
					if(unsigned(opt_mode_i) = 1) then	-- turn on charging
						gateC_next_s <= '0';
						state_next_s <= CHARGE;
					elsif (unsigned(opt_mode_i) = 2) then	-- turn off charging
						gateD_next_s <= '0';
						state_next_s <= DISCHARGE;
					else	-- go back to IDLE
						state_next_s <= IDLE;
					end if;
				end if; 
				
			when INTERLOCKING =>
				-- interlocking between insert positive and insert negative
				timer_top_next_s <= T_INTERLOCKING_G; 
				if timer_end_s = '1' then  
					if(opt_gate1_i = '0' AND opt_gate2_i = '0') then -- pos to loop
						gate1_next_s <= opt_gate1_i;
						state_next_s <= OP_LOOP;
					elsif (opt_gate1_i = '1' AND opt_gate2_i = '0') then -- loop to pos
						gate3_next_s <= NOT opt_gate1_i;
						state_next_s <= OP_INS_POS;
					elsif (opt_gate1_i = '0' AND opt_gate2_i = '1') then -- loop to neg
						gate4_next_s <= NOT opt_gate2_i;
						state_next_s <= OP_INS_NEG;
					elsif (opt_gate1_i = '0' AND opt_gate2_i = '0') then -- neg to loop
						gate2_next_s <= opt_gate1_i;
						state_next_s <= OP_LOOP;
					else	
						state_next_s <= IDLE;
					end if;
				end if; 
				
			when INTERLOCKING_LOOP =>
				-- interlocking entering or leaving loop state
				timer_top_next_s <= T_INTERLOCKING_G; 
				if timer_end_s = '1' then  
					if(opt_gate1_i = '0' AND opt_gate2_i = '1') then -- pos to negative
						gate4_next_s <= NOT opt_gate2_i;
						state_next_s <= OP_INS_NEG;
					elsif (opt_gate1_i = '1' AND opt_gate2_i = '0') then -- neg to pos
						gate3_next_s <= NOT opt_gate1_i;
						state_next_s <= OP_INS_POS;
					else	
						state_next_s <= IDLE;
					end if;
				end if; 
			when BYPASS => -- NEW: bypass mode if only the buck converter is used
				if (unsigned(opt_mode_i) /= 5) then
					resetGates_next_s <= '1';
					resetC_next_s <= '1';
					resetD_next_s <= '1';
					resetReady_next_s <= '1';
					gate1_next_s <= '1';
					gate2_next_s <= '1';
					gate3_next_s <= '1';
					gate4_next_s <= '1';
					state_next_s <= IDLE;
				end if;
			when others =>
		end case;
	end process;
	

Measurement: process (VoltMeas_i)
	begin 
		VoltageMeas_next_s <= 1;
		-- check DC link voltage
		if signed(VoltMeas_i) > N_VDC_HIGH_G then -- high voltage
			VoltageMeas_next_s <= 2;
		elsif signed(VoltMeas_i) < N_VDC_LOW_G then	-- voltage = 0
			VoltageMeas_next_s <= 0;
		else	-- somewhere in between
			VoltageMeas_next_s <= 1;
		end if;

	end process;

-- output assignment
gate1_o <= gate1_s;
gate2_o <= gate2_s;
gate3_o <= gate3_s;
gate4_o <= gate4_s;
gateC_o <= gateC_s;
gateD_o <= gateD_s;
reset_gates_o <= resetGates_s;
reset_c_o <= resetC_s;
reset_d_o <= resetD_s;
reset_Ready_o <= resetReady_s;
end rtl;
