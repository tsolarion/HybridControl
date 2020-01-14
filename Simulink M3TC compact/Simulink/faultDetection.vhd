--==========================================================
-- Unit		:	faultDetection(rtl)
-- File		:	faultDetection.vhd
-- Purpose	:	
-- Author	:	Pascal Zähner - HPE - ETH Zuerich
-- Device	:	Altera FPGA - MAX10
-- EDA syn	:	Altera Quartus Prime
-- EDA sim	:	Modelsim SE 10.1c
-- misc		:	--
-- depdcy	:	
--==========================================================

--! @file faultDetection.vhd
--! @author Pascal Zähner 
--! @date  05.12.2018

-- use standard library
library ieee;
library work;
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

entity faultDetection is
	generic(
		ERROR_VOLT_G	 	: std_logic_vector(2 downto 0) := "001"; -- error word voltage
		ERROR_TEMPHS_G 		: std_logic_vector(2 downto 0) := "010"; -- error word temperature heat sink
		ERROR_TEMPIGBT_G 	: std_logic_vector(2 downto 0) := "011"; -- -- error word temperature IGBT
		ERROR_FAULT_G		: std_logic_vector(2 downto 0) := "100"; -- error word fault on the IGBTs
		ERROR_READY_G		: std_logic_vector(2 downto 0) := "101" -- error word for ready problem at the IGBTs
	);
	
	port(
		nreset_i 		: in std_logic; -- Asynchronous reset
		clk_i 			: in std_logic; -- main clock
		
		-- inputs
		ready1_i		: in std_logic; -- gate driver 1, ready output 
		ready2_i		: in std_logic; -- gate driver 2, ready output
		ready3_i		: in std_logic; -- gate driver 3, ready output
		ready4_i		: in std_logic; -- gate driver 4, ready output
		readyC_i		: in std_logic; -- gate driver charge, ready output
		readyD_i		: in std_logic; -- gate driver discharge, ready output
		faultGates_i	: in std_logic; -- fault signal, gates of the full bridge
		faultC_i		: in std_logic; -- fault signal, charge gate driver
		faultD_i		: in std_logic; -- fault signal, discharge gate driver
		volt_i			: in std_logic_vector(11 downto 0);	-- measured voltage
		temptIGBT_i		: in std_logic_vector(11 downto 0);	-- measured IGBT junction temperature
		tempHeatsink_i	: in std_logic_vector(7 downto 0);	-- measured heat sink temperature
		
		-- outputs
		faultReport_o 	: out std_logic_vector(11 downto 0); -- generated fault report
		fault_gate_o	: out std_logic; -- fault at the fault bridge
		fault_c_o	 	: out std_logic; -- fault at the charge gate driver
		fault_d_o	 	: out std_logic; -- fault at the discharge gate driver
		fault_o	 		: out std_logic -- single fault ouput, OR connection of all
		
	);
end faultDetection ;

architecture rtl of faultDetection  is
-- ================== CONSTANTS ==================================================
-- ================== COMPONENTS =================================================
-- =================== STATES ===================================================
-- =================== SIGNALS ===================================================
signal fault_s, fault_next_s 				: std_logic := '0'; -- binary fault signal
signal fault_gates_s, fault_gates_next_s	: std_logic := '0'; -- fault at gates of the full bridge 
signal fault_c_s, fault_c_next_s			: std_logic := '0'; -- fault at charge gate driver
signal fault_d_s, fault_d_next_s			: std_logic := '0'; -- fault at discharge gate driver
signal faultReport_s, faultReport_next_s	: std_logic_vector(11 downto 0):= (others => '0'); -- generated fault report 

begin

--! @brief Register update  
output : process(nreset_i, clk_i)
begin
	if nreset_i = '0' then
		fault_s 		<= '0';
		faultReport_s	<= (others => '0'); 
		fault_gates_s	<= '0'; 
		fault_c_s		<= '0'; 
		fault_d_s		<= '0'; 
	elsif rising_edge(clk_i) then
		fault_s 		<= fault_next_s;
		faultReport_s	<= faultReport_next_s; 
		fault_gates_s	<= fault_gates_next_s; 
		fault_c_s		<= fault_c_next_s; 
		fault_d_s       <= fault_d_next_s; 
	END if;
end process;

--! @brief Output Logic 
--! @details: Logic for Hysteresis OUTPUT 
measurement : process(tempHeatsink_i, temptIGBT_i, volt_i, ready1_i,
					  ready2_i, ready3_i, ready4_i, readyC_i, readyD_i, faultC_i, faultD_i, faultGates_i)
Variable convert : std_logic_vector(4 downto 0):= (others => '0');
begin
	
	-- overvoltage
	if (unsigned(volt_i) > 1200) then
		fault_next_s <= '1';
		faultReport_next_s <= ERROR_VOLT_G & volt_i(11 downto 3);	-- take highest bits
	-- high IGBT temperature
	elsif (unsigned(temptIGBT_i) > 160) then
		fault_next_s <= '1';
		faultReport_next_s <= ERROR_TEMPIGBT_G & temptIGBT_i(11 downto 3);	-- take highest bits
	-- high heat sink temperature
	elsif (unsigned(tempHeatsink_i) > 40) then
		fault_next_s <= '1';
		faultReport_next_s <= ERROR_TEMPHS_G & "0" & tempHeatsink_i(7 downto 0);	-- take highest bits
	-- gate driver IC is not ready
	elsif (ready1_i = '0' OR ready2_i = '0' OR ready3_i = '0' OR ready4_i = '0' OR readyC_i = '0' OR readyD_i = '0') then
		fault_next_s <= '1';
		faultReport_next_s <= ERROR_READY_G & "000" & NOT ready4_i & NOT ready3_i & NOT ready2_i & NOT ready1_i & NOT readyC_i & NOT readyD_i;
	-- fault at the gate driver IC
	elsif (faultC_i = '0' OR faultD_i = '0' OR faultGates_i = '0') then
		fault_next_s <= '1';
		faultReport_next_s <= ERROR_FAULT_G & "000000" & NOT faultGates_i & NOT faultC_i & NOT faultD_i;
	-- no error detected
	ELSE
		fault_next_s <= '0';
		faultReport_next_s <= (others => '0');
	END if;
	
	-- convertion for easyer case detection
	convert := ready1_i & ready2_i & ready3_i & ready4_i & faultGates_i;
	if (unsigned(convert) < 31) then
		fault_gates_next_s <= '1';
	ELSE
		fault_gates_next_s <= '0';
	END if;
	
	convert := "000" & readyC_i & faultC_i;
	if (unsigned(convert) < 3) then
		fault_c_next_s <= '1';
	ELSE
		fault_c_next_s <= '0';
	END if;
	
	convert := "000" & readyD_i & faultD_i;
	if (unsigned(convert) < 3) then
		fault_d_next_s <= '1';
	ELSE
		fault_d_next_s <= '0';
	END if;
		
end process;

-- output assignments 
fault_o			<= NOT fault_s; -- inverted logic
fault_c_o      	<= fault_c_s; 
fault_d_o      	<= fault_d_s; 
fault_gate_o   	<= fault_gates_s; 
faultReport_o  	<= faultReport_s; 

end rtl;
