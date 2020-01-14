--==========================================================
-- Unit		:	checkReady(rtl)
-- File		:	checkReady.vhd
-- Purpose	:	
-- Author	:	Pascal Zähner - HPE - ETH Zuerich
-- Device	:	Altera FPGA - MAX10
-- EDA syn	:	Altera Quartus Prime
-- EDA sim	:	Modelsim SE 10.1c
-- misc		:	--
-- depdcy	:	
--==========================================================

--! @file checkReady.vhd
--! @author Pascal Zähner 
--! @date  05.12.2018

-- use standard library
library ieee;
library work;
--! Use logic elements
use ieee.std_logic_1164.all;
--! Use numeric elements
use ieee.numeric_std.all;


entity checkReady is
	generic(
		n_cycles		: integer := 999; -- maximum cycles to check (window)
		n_faults		: integer := 20; -- how many faults are needed per window
		n_faults_reset	: integer := 15 -- reset boundary for new window
	);
	
	port(
		nreset 			: IN STD_LOGIC; -- Asynchronous reset
		clk 			: IN STD_LOGIC; -- main clock
		inReady			: IN STD_LOGIC; -- ready signal received from gate driver IC
		inResetFault	: IN STD_LOGIC; -- reset input from control, after fault needed

		outReady	 	: OUT STD_LOGIC -- filtered ready signal for controller
	);
end checkReady ;

architecture rtl of checkReady  is
-- ================== CONSTANTS ==================================================
-- ================== COMPONENTS =================================================
-- =================== STATES ===================================================
-- =================== SIGNALS ===================================================
SIGNAL outReady_nx		: STD_LOGIC := '1'; -- register for output
SIGNAL counter			: integer := 0; -- cycles counter
SIGNAL counter_faults	: integer := 0; -- faults counter

begin

sava_input : process(nreset, clk)
begin
	IF nreset = '0' then
		counter <= 0;
	ELSIF rising_edge(clk) THEN	-- count cycles 
		counter <= counter + 1;
		IF (counter = n_cycles) THEN
			counter <= 0;
		END IF;
	END IF;
end process;

sensing : process(nreset, clk)
begin
	IF nreset = '0' then
		counter_faults <= 0;
	ELSIF rising_edge(clk) THEN	-- check reset option for fault counter 
		IF (counter = 0) THEN
			IF (counter_faults < n_faults_reset) THEN
				counter_faults <= 0;
			END IF;
		END IF;
		-- check reday input
		IF (inReady = '0' AND outReady_nx = '1') THEN
			counter_faults <= counter_faults + 1;
		END IF;
		-- set ready output if detected
		IF (counter_faults > n_faults) THEN
			outReady_nx <= '0';
		ELSE
			outReady_nx <= '1';
		END IF;
		IF (inResetFault = '0') THEN
			outReady_nx <= '1';
			counter_faults <= 0;
		END IF;
	END IF;
end process;

update_output : process(nreset, clk)
begin
	IF nreset = '0' then
		outReady 	<= '0';
	ELSIF rising_edge(clk) THEN
		outReady	<= outReady_nx;
	END IF;
end process;

end rtl;
