--==========================================================
-- Unit		:	SendingData(rtl)
-- File		:	SendingData.vhd
-- Purpose	:	
-- Author	:	Pascal Zähner - HPE - ETH Zuerich
-- Device	:	Altera FPGA - MAX10
-- EDA syn	:	Altera Quartus Prime
-- EDA sim	:	Modelsim SE 10.1c
-- misc		:	--
-- depdcy	:	
-- testbench: tb_SendingReceive.vhd 
--==========================================================

--! @file SendingData.vhd
--! @author Pascal Zähner 
--! @date  05.12.2018

-- use standard library
library ieee;
library work;
--! Use logic elements
use ieee.std_logic_1164.all;
--! Use numeric elements
use ieee.numeric_std.all;

entity SendingData is	
	generic(
		N_BITS_G 					: integer :=  12;
		N_BITS_TOTAL_G				: integer :=  20;
		START_SYMBOL_ERROR_G		: std_logic_vector(7 downto 0) := "10011001"; -- start symbol error 
		START_SYMBOL_VOLTAGE_G		: std_logic_vector(7 downto 0) := "11100111"; -- start symbol for voltage transmittion
		START_SYMBOL_TEMPHS_G	 	: std_logic_vector(7 downto 0) := "11000011"; -- start symbol for heat sink temperature transmittion
		START_SYMBOL_TEMPIGBT_G		: std_logic_vector(7 downto 0) := "10000001"; -- start symbol for junction temperature transmittion
		START_SYMBOL_MODE_G			: std_logic_vector(7 downto 0) := "11011011" -- start symbol for mode and gates transmittion
	);
	
   port (
      nreset_i			: in std_logic; -- Asynchronous reset
	  clk_i         	: in std_logic; -- main clock
	  volt_i     		: in std_logic_vector(11 downto 0); -- 12 bit voltage value
	  tempIGBT_i    	: in std_logic_vector(11 downto 0); -- 12 bit junction temperature 
	  tempHeatsink_i	: in std_logic_vector(7 downto 0); -- 8 bit value, measured heat sink temperature
	  faultReport_i		: in std_logic_vector(11 downto 0); -- 12 bit value, fault report
	  mode_i			: in std_logic_vector(2 downto 0); -- 3 bit, mode
	  gate1_i			: in std_logic; -- gate1 signal
	  gate2_i			: in std_logic; -- gate2 signal
	  optical_o		: OUT std_logic -- optical output, serialized data
   );
end entity;

architecture rt1 of SendingData is
-- ================== CONSTANTS =================================================
constant CNT_TOP_C						: integer := 19; -- timer value in cycles
-- ================== COMPONENTS =================================================
-- =================== STATES ====================================================
type my_states is (IDLE,VOLTAGE, TEMP_IGBT, TEMP_HS, SAVE_ERROR, SEND_ERROR, OPT_INPUTS); -- state machine to send data

-- =================== SIGNALS ===================================================
signal state_s, state_next_s : my_states := VOLTAGE; -- current state
signal data_send_s, data_send_next_s: std_logic_vector(19 DOWNTO 0) := (others => '0') ; -- prepared data to send

-- timer
signal cnt_start_s, cnt_start_next_s	: std_logic := '0'; -- start timer
signal cnt_end_s, cnt_end_next_s		: std_logic := '0'; -- signalize counter ends
signal cnt_val_s, cnt_val_next_s		: integer range 0 to CNT_TOP_C := 0; -- stop value of the counter
	
begin

	------------ Counter ---------------------
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
			cnt_val_s <= 0;
			cnt_start_s<= '0'; 
		elsif rising_edge(clk_i) then 
			cnt_end_s   <= cnt_end_next_s;
			cnt_val_s	<= cnt_val_next_s;
			cnt_start_s	<= cnt_start_next_s; 			
		end if; 
	end process; 
	----------------------------------------

--! @brief Register update	
REG: process(clk_i, nreset_i)
	begin 
		if nreset_i= '0' then 
			state_s 	<= IDLE;
			data_send_s <= (others => '0'); 
		elsif rising_edge(clk_i) then 
			state_s 	<= state_next_s; 
			data_send_s <= data_send_next_s; 
		end if; 
end process;

	
	
IN_LOG: process(state_s, faultReport_i,data_send_s,cnt_end_s,volt_i,tempIGBT_i,tempHeatsink_i)
begin
-- default assignments for avoiding Latches 
cnt_start_next_s	<= '0';  
state_next_s		<= state_s; 
data_send_next_s	<= data_send_s; 

	-- state machine changes state after complete sending (20 bits)
	case state_s is
		when IDLE => 		-- start with sending voltage if no error
			if (unsigned(faultReport_i) = 0) then
				state_next_s <= VOLTAGE;
				cnt_start_next_s <= '1'; 
			else
				state_next_s <= SEND_ERROR;
				cnt_start_next_s <= '1'; 
			end if;
		
		when VOLTAGE =>
			if (unsigned(faultReport_i) = 0) then -- sending measured voltage
				data_send_next_s <= START_SYMBOL_VOLTAGE_G & volt_i;
				if cnt_end_s = '1' AND cnt_start_s = '0' then 
					state_next_s <= TEMP_HS;
					cnt_start_next_s <= '1'; 
				end if; 
			else
				state_next_s <= SEND_ERROR;
				cnt_start_next_s <= '1'; 
			end if;
			
		when TEMP_HS =>
			if (unsigned(faultReport_i) = 0) then -- sending hs temperature
				data_send_next_s <= START_SYMBOL_TEMPHS_G & "0000" & tempHeatsink_i;
				if cnt_end_s = '1' AND cnt_start_s = '0' then 
					state_next_s <= TEMP_IGBT;
					cnt_start_next_s <= '1'; 
				end if; 
			else
				state_next_s <= SEND_ERROR;
				cnt_start_next_s <= '1'; 
			end if;
			
		when TEMP_IGBT => -- sending IGBT junction temperature
			if (unsigned(faultReport_i) = 0) then
				data_send_next_s <= START_SYMBOL_TEMPIGBT_G & tempIGBT_i;
				if cnt_end_s = '1' AND cnt_start_s = '0' then 
					state_next_s <= OPT_INPUTS;
					cnt_start_next_s <= '1'; 
				end if; 
			else
				state_next_s <= SEND_ERROR;
				cnt_start_next_s <= '1'; 
			end if;
			
		when OPT_INPUTS =>  -- sned the received inputs (mode, gate1 and gate2) back
			if (unsigned(faultReport_i) = 0) then 
				data_send_next_s <= START_SYMBOL_MODE_G & "000" & mode_i & "0000" & gate1_i & gate2_i; 
				if cnt_end_s = '1' AND cnt_start_s = '0' then 
					state_next_s <= VOLTAGE;
					cnt_start_next_s <= '1'; 
				end if; 
			else
				state_next_s <= SEND_ERROR;
				cnt_start_next_s <= '1'; 
			end if;
			
		when SAVE_ERROR =>	-- ToDo: Use this case to save errors that arraive during sending the other
			if (unsigned(faultReport_i) = 0) then
				state_next_s <= VOLTAGE;
				cnt_start_next_s <= '1'; 
			else	-- 
				state_next_s <= SEND_ERROR;
				cnt_start_next_s <= '1'; 
			end if;

		when SEND_ERROR => -- send error
			if(unsigned(faultReport_i) /= 0) then	-- error at output, send this. If sending allready than save it
				
				data_send_next_s <= START_SYMBOL_ERROR_G & faultReport_i;
				if cnt_end_s = '1' then 
					state_next_s <= SAVE_ERROR;
				end if; 	
			end if; 
		when OTHERS =>
	end case;
end process;

OUT_LOG : process(clk_i, nreset_i)
begin
	if nreset_i = '0' then
		optical_o <= '0';
	elsif rising_edge(clk_i) then
		optical_o <= data_send_s(19-cnt_val_s);
	end if;
end process;

end architecture;