LIBRARY IEEE;
USE IEEE.std_logic_1164.ALL;
USE IEEE.numeric_std.ALL;

ENTITY tempControl IS

	PORT(
		isl_clk 			: IN std_logic;
		isl_nreset		: IN std_logic;
		isl_data_redy	: IN std_logic;
		islv_temp		: IN std_logic_vector(7 DOWNTO 0);
		
		osl_temperature: OUT std_logic_vector(7 DOWNTO 0);	--Added 8. April 2016
		osl_dataselect	: OUT std_logic

	);
END ENTITY tempControl;


ARCHITECTURE rtl OF tempControl IS
	
	CONSTANT	usig_countlength 	: unsigned(23 DOWNTO 0) := to_unsigned(3375000,24);
	
	TYPE t_register IS RECORD
		std_temp			: std_logic_vector(7 DOWNTO 0);		--Added 8. April 2016
		sl_data_redy 	: std_logic;
		sl_dataselect 	: std_logic;
		usig_count 		: unsigned(23 DOWNTO 0);
		std_temperature: std_logic_vector(7 DOWNTO 0);		--Added 8. April 2016
	END RECORD;
	
	SIGNAL r, r_next	: t_register;
	
BEGIN
	
	comb_proc : PROCESS (isl_nreset, islv_temp, r, isl_data_redy)
		
		VARIABLE v : t_register;
		
	BEGIN
		
		v						:= r;
		v.std_temp			:=	islv_temp;							--Added 8. April 2016
		v.sl_data_redy		:= isl_data_redy;
		v.usig_count		:= r.usig_count-1;
		v.sl_dataselect	:= '0';
		
		IF r.usig_count = 0 THEN	
			v.usig_count		:= usig_countlength;
			v.sl_dataselect	:= '1';
		END IF;
		
		IF r.sl_data_redy = '1' THEN
			v.std_temperature := r.std_temp;						--Added 8. April 2016
		END IF;
		
		IF isl_nreset = '0' THEN
			v.usig_count		:= usig_countlength;
			v.sl_dataselect	:= '0';
			v.std_temp			:= (OTHERS => '0');				--Added 8. April 2016
		END IF;
		
		r_next <= v;
		
	END PROCESS comb_proc;
	
	
	reg_proc : PROCESS (isl_clk,r_next)
	BEGIN
		IF rising_edge(isl_clk) THEN
			r <= r_next;
		END IF;
	END PROCESS reg_proc;
	
	osl_dataselect		<= r.sl_dataselect;
	osl_temperature	<= r.std_temperature;					--Added 8. April 2016
	
END ARCHITECTURE rtl;