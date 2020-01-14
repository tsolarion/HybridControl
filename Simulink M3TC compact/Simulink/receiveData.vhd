--==========================================================
-- Unit		:	receiveData(rtl)
-- File		:	receiveData.vhd
-- Purpose	:	
-- Author	:	Pascal Zähner - HPE - ETH Zuerich
-- Device	:	Altera FPGA - MAX10
-- EDA syn	:	Altera Quartus Prime
-- EDA sim	:	Modelsim SE 10.1c
-- misc		:	--
-- depdcy	:	
-- testbench: tb_SendingReceive.vhd 
--==========================================================

--! @file receiveData.vhd
--! @author Pascal Zähner 
--! @date  05.12.2018

-- use standard library
library ieee;
library work;
--! Use logic elements
use ieee.std_logic_1164.all;
--! Use numeric elements
use ieee.numeric_std.all;

entity receiveData is
	generic(
		START_SYMBOL_ERROR_G	: std_logic_vector(7 downto 0) := "10011001"; -- start symbol error message
		START_SYMBOL_VOLTAGE_G	: std_logic_vector(7 downto 0) := "11100111"; -- start symbol voltage 
		START_SYMBOL_TEMPHS_G	: std_logic_vector(7 downto 0) := "11000011"; -- start symbol heat sink temperature
		START_SYMBOL_TEMPIGBT_G	: std_logic_vector(7 downto 0) := "10000001"; -- start symbol junction temperature IGBT
		START_SYMBOL_MODE_G		: std_logic_vector(7 downto 0) := "11011011"; -- start symbol for mode and gates transmittion
		ERROR_VOLT_G	 		: std_logic_vector(2 downto 0) := "001"; -- start symbol error message, voltage
		ERROR_TEMPHS_G 			: std_logic_vector(2 downto 0) := "010"; -- start symbol error message, heat sink temperature
		ERROR_TEMP_G 			: std_logic_vector(2 downto 0) := "011"; -- start symbol error message, IGBT junction temperature
		ERROR_FAULT_G			: std_logic_vector(2 downto 0) := "100"; -- start symbol error message, fault at the gate driver
		ERROR_READY_G			: std_logic_vector(2 downto 0) := "101" -- start symbol error message, ready fault at the gate driver
	);
	
	port(
		nreset_i 			: in std_logic; -- Asynchronous reset
		clk_i 				: in std_logic; -- main clock
		fault_i				: in std_logic; -- overall fault
		data_i				: in std_logic; -- serialized data input
		fault_o	 			: out std_logic_vector(11 downto 0); -- fault report
		voltage_o	 		: out std_logic_vector(11 downto 0); -- measured voltage 
		tempIGBT_o	 		: out std_logic_vector(11 downto 0); -- measured junction temperature 
		tempHS_o	 		: out std_logic_vector(11 downto 0); -- measured heat sink temperature
		optical_signals_o 	: out std_logic_vector(4 downto 0) -- received input signals
	);
end receiveData ;

architecture rtl of receiveData  is
-- ================== CONSTANTS ==================================================
-- ================== COMPONENTS =================================================
-- =================== STATES ====================================================
-- =================== SIGNALS ===================================================
SIGNAL outFault_s, outFault_next_s 		: std_logic_vector(11 downto 0):= (others => '0'); -- saved data at fault
SIGNAL outVoltage_s, outVoltage_next_s 	: std_logic_vector(11 downto 0):= (others => '0'); --  voltage measuremend
SIGNAL outTempIGBT_s, outTempIGBT_next_s: std_logic_vector(11 downto 0):= (others => '0'); -- heat sink temperature
SIGNAL outTempHS_s, outTempHS_next_s	: std_logic_vector(11 downto 0):= (others => '0'); -- junction temperature
SIGNAL outOPTICAL_s, outOPTICAL_next_s	: std_logic_vector(4 downto 0):= (others => '0'); -- received oiptical signals
SIGNAL data_reg_s						: std_logic_vector(19 downto 0):= (others => '0'); -- buffer for received data
SIGNAL counter_s, counter_next_s		: integer := 0; -- counter to ensure no erroreous data
SIGNAL measMode_s, measMode_next_s		: integer range 0 to 5 := 0; -- defines the order of data collection

begin

	--! @brief Register update 
	reg_proc : process(nreset_i, clk_i)
	begin
		if nreset_i = '0' then
			data_reg_s 		<= (others => '0');
			outFault_s		<= (others => '0');
			outVoltage_s	<= (others => '0');
			outTempIGBT_s	<= (others => '0');
			outTempHS_s 	<= (others => '0');
			outOPTICAL_s 	<= (others => '0');
			counter_s		<= 0; 
			measMode_s 		<= 0; 
		elsif rising_edge(clk_i) then
			data_reg_s 		<= data_reg_s(19-1 downto 0) & data_i;
			outFault_s		<= outFault_next_s;		
			outVoltage_s	<= outVoltage_next_s; 	
			outTempIGBT_s	<= outTempIGBT_next_s; 	
			outTempHS_s 	<= outTempHS_next_s;  	
			counter_s 		<= counter_next_s; 
			measMode_s		<= measMode_next_s; 
			outOPTICAL_s    <= outOPTICAL_next_s;
		end if;
	end process;

	sensing_proc : process(counter_s, fault_i, measMode_s,outFault_s, outVoltage_s, outTempHS_s, outTempIGBT_s,data_reg_s)
	variable data_case	: integer range 0 to 2**(9)-1;
	begin
		-- default value (to avoid latches) 
		counter_next_s 		<= counter_s + 1; 
		outFault_next_s		<= outFault_s; 		
		outVoltage_next_s   <= outVoltage_s;  
		outTempIGBT_next_s  <= outTempIGBT_s; 
		outTempHS_next_s    <= outTempHS_s;
		outOPTICAL_next_s    <= outOPTICAL_s;
		measMode_next_s     <= measMode_s;    

		-- receive error, if start word is correct
		if data_reg_s(19 downto 12) = START_SYMBOL_ERROR_G then
			if(fault_i = '1') then
				outFault_next_s <= data_reg_s(11 downto 0);
				measMode_next_s <= 0;
			else
				outFault_next_s <= (others => '0');
			end if;
		-- receive voltage value, if start word is correct
		elsif data_reg_s(19 downto 12) = START_SYMBOL_VOLTAGE_G then
			if (measMode_s = 0 AND fault_i = '0' AND counter_s > 18) then
				outVoltage_next_s <= data_reg_s(11 downto 0);
				outFault_next_s <= (others => '0');
				measMode_next_s <= 1;
				counter_next_s <= 0;
			end if;
		-- receive heat sink temperature value, if start word is correct
		elsif data_reg_s(19 downto 12) = START_SYMBOL_TEMPHS_G then
			iF (measMode_s = 1 AND fault_i = '0' AND counter_s > 18) then
				outTempHS_next_s<= data_reg_s(11 downto 0);
				outFault_next_s <= (others => '0');
				measMode_next_s <= 2;
				counter_next_s	<= 0;
			end if;
		-- receive IGBT junction temperature value, if start word is correct
		elsif data_reg_s(19 downto 12) = START_SYMBOL_TEMPIGBT_G then
			if (measMode_s = 2 AND fault_i = '0' AND counter_s > 18) then
				outTempIGBT_next_s <= data_reg_s(11 downto 0);
				outFault_next_s <= (others => '0');
				measMode_next_s <= 3;
				counter_next_s <= 0;
			end if;
		-- receive mode from M3TC stage, if start word is correct
		elsif data_reg_s(19 downto 12) = START_SYMBOL_MODE_G then
			iF (measMode_s = 3 AND fault_i = '0' AND counter_s > 18) then
				outOPTICAL_next_s <= data_reg_s(8 downto 6) & data_reg_s(1 downto 0);				
				outFault_next_s <= (others => '0');
				measMode_next_s <= 0;
				counter_next_s	<= 0;
			end if;
		end if;
	end process;

-- output assignment
fault_o	 		<= outFault_s;
voltage_o	 	<= outVoltage_s;
tempIGBT_o	 	<= outTempIGBT_s;
tempHS_o	 	<= outTempHS_s;
optical_signals_o <= outOPTICAL_s;



end rtl;
