-- megafunction wizard: %LPM_CONSTANT%
-- GENERATION: STANDARD
-- VERSION: WM1.0
-- MODULE: LPM_CONSTANT 

-- ============================================================
-- File Name: kixts_const.vhd
-- Megafunction Name(s):
-- 			LPM_CONSTANT
--
-- Simulation Library Files(s):
-- 			
-- ============================================================
-- ************************************************************
-- THIS IS A WIZARD-GENERATED FILE. DO NOT EDIT THIS FILE!
--
-- 16.1.0 Build 196 10/24/2016 SJ Standard Edition
-- ************************************************************


--Copyright (C) 2016  Intel Corporation. All rights reserved.
--Your use of Intel Corporation's design tools, logic functions 
--and other software and tools, and its AMPP partner logic 
--functions, and any output files from any of the foregoing 
--(including device programming or simulation files), and any 
--associated documentation or information are expressly subject 
--to the terms and conditions of the Intel Program License 
--Subscription Agreement, the Intel Quartus Prime License Agreement,
--the Intel MegaCore Function License Agreement, or other 
--applicable license agreement, including, without limitation, 
--that your use is for the sole purpose of programming logic 
--devices manufactured by Intel and sold by Intel or its 
--authorized distributors.  Please refer to the applicable 
--agreement for further details.


--lpm_constant CBX_AUTO_BLACKBOX="ALL" ENABLE_RUNTIME_MOD="YES" INSTANCE_NAME="KIxT" LPM_CVALUE=3F9C28F6 LPM_WIDTH=32 result
--VERSION_BEGIN 16.1 cbx_lpm_constant 2016:10:24:15:04:16:SJ cbx_mgl 2016:10:24:15:05:03:SJ  VERSION_END

--synthesis_resources = sld_mod_ram_rom 1 
 LIBRARY ieee;
 USE ieee.std_logic_1164.all;

 ENTITY  kixts_const_lpm_constant_08b IS 
	 PORT 
	 ( 
		 result	:	OUT  STD_LOGIC_VECTOR (31 DOWNTO 0)
	 ); 
 END kixts_const_lpm_constant_08b;

 ARCHITECTURE RTL OF kixts_const_lpm_constant_08b IS

	 SIGNAL  wire_mgl_prim1_data_write	:	STD_LOGIC_VECTOR (31 DOWNTO 0);
	 COMPONENT  sld_mod_ram_rom
	 GENERIC 
	 (
		CVALUE	:	STD_LOGIC_VECTOR(31 DOWNTO 0) := "00000000000000000000000000000000";
		IS_DATA_IN_RAM	:	NATURAL;
		IS_READABLE	:	NATURAL;
		NODE_NAME	:	NATURAL;
		NUMWORDS	:	NATURAL;
		SHIFT_COUNT_BITS	:	NATURAL;
		WIDTH_WORD	:	NATURAL;
		WIDTHAD	:	NATURAL
	 );
	 PORT
	 ( 
		data_write	:	OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
	 ); 
	 END COMPONENT;
 BEGIN

	result <= wire_mgl_prim1_data_write;
	mgl_prim1 :  sld_mod_ram_rom
	  GENERIC MAP (
		CVALUE => "00111111100111000010100011110110",
		IS_DATA_IN_RAM => 0,
		IS_READABLE => 0,
		NODE_NAME => 1263106132,
		NUMWORDS => 1,
		SHIFT_COUNT_BITS => 6,
		WIDTH_WORD => 32,
		WIDTHAD => 1
	  )
	  PORT MAP ( 
		data_write => wire_mgl_prim1_data_write
	  );

 END RTL; --kixts_const_lpm_constant_08b
--VALID FILE


LIBRARY ieee;
USE ieee.std_logic_1164.all;

ENTITY kixts_const IS
	PORT
	(
		result		: OUT STD_LOGIC_VECTOR (31 DOWNTO 0)
	);
END kixts_const;


ARCHITECTURE RTL OF kixts_const IS

	SIGNAL sub_wire0	: STD_LOGIC_VECTOR (31 DOWNTO 0);



	COMPONENT kixts_const_lpm_constant_08b
	PORT (
			result	: OUT STD_LOGIC_VECTOR (31 DOWNTO 0)
	);
	END COMPONENT;

BEGIN
	result    <= sub_wire0(31 DOWNTO 0);

	kixts_const_lpm_constant_08b_component : kixts_const_lpm_constant_08b
	PORT MAP (
		result => sub_wire0
	);



END RTL;

-- ============================================================
-- CNX file retrieval info
-- ============================================================
-- Retrieval info: PRIVATE: INTENDED_DEVICE_FAMILY STRING "Cyclone V"
-- Retrieval info: PRIVATE: JTAG_ENABLED NUMERIC "1"
-- Retrieval info: PRIVATE: JTAG_ID STRING "KIxT"
-- Retrieval info: PRIVATE: Radix NUMERIC "16"
-- Retrieval info: PRIVATE: SYNTH_WRAPPER_GEN_POSTFIX STRING "0"
-- Retrieval info: PRIVATE: Value NUMERIC "1067198710"
-- Retrieval info: PRIVATE: nBit NUMERIC "32"
-- Retrieval info: PRIVATE: new_diagram STRING "1"
-- Retrieval info: LIBRARY: lpm lpm.lpm_components.all
-- Retrieval info: CONSTANT: LPM_CVALUE NUMERIC "1067198710"
-- Retrieval info: CONSTANT: LPM_HINT STRING "ENABLE_RUNTIME_MOD=YES, INSTANCE_NAME=KIxT"
-- Retrieval info: CONSTANT: LPM_TYPE STRING "LPM_CONSTANT"
-- Retrieval info: CONSTANT: LPM_WIDTH NUMERIC "32"
-- Retrieval info: USED_PORT: result 0 0 32 0 OUTPUT NODEFVAL "result[31..0]"
-- Retrieval info: CONNECT: result 0 0 32 0 @result 0 0 32 0
-- Retrieval info: GEN_FILE: TYPE_NORMAL kixts_const.vhd TRUE
-- Retrieval info: GEN_FILE: TYPE_NORMAL kixts_const.inc FALSE
-- Retrieval info: GEN_FILE: TYPE_NORMAL kixts_const.cmp TRUE
-- Retrieval info: GEN_FILE: TYPE_NORMAL kixts_const.bsf TRUE
-- Retrieval info: GEN_FILE: TYPE_NORMAL kixts_const_inst.vhd FALSE
