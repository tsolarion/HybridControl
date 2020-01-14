--==========================================================
-- Unit		:	m3tc_hybrid(rtl)
-- File		:	m3tc_hybrid.vhd
-- Purpose	:	
-- Author	:	Michael Hersche - HPE - ETH Zuerich
-- Device	:	Altera FPGA - Cyclone V
-- EDA syn	:	Altera Quartus II
-- EDA sim	:	Modelsim SE 10.1c
-- misc		:	--
-- depdcy	:	--
--==========================================================

--! @file m3tc_hybrid.vhd 
--! @author Michael Hersche, Pascal Zaehner
--! @date  22.11.2018

-- library ieee;
-- --! package for arrays 
-- use ieee.std_logic_1164.all;


library work; 
use work.stdvar_arr_pkg.all;
-- use standard library
library ieee;
--! Use logic elements
use ieee.std_logic_1164.all;
--! Use numeric elements
use ieee.numeric_std.all;


--! @brief Top level of m3tc and hybrid control with 5 slaves 
--! @details 
entity m3tc_hybrid is
	generic( 	CMAX_G 				: integer := 1666; --! Maximum counter value of PWM (determines PWM frequency) =>  ~60 KHz with 100 MHz clock 
				FS_G 				: real 	  := 60096.0; --! PWM frequency 
				F_CLK_G				: real 	  := 100.0*(10**6); --! Clock frequency  
				NINTERLOCK_G		: integer := 50; --50
				MEAS_I_DATAWIDTH_G 	: integer range 8 to 16 := 13;  --! Data width of current measurements  
				MEAS_V_DATAWIDTH_G	: integer range 8 to 16 := 12; --! Data width of voltage measurements 
				DATAWIDTH_G			: integer := 16; --! General internal datawidth: THIS HAS TO BE KEPT CONSTANT
				-- MAF settings 
				MAX_DELTA_G: natural := 200*(2**5); 				--! MAF: limitation of current change for storing in buffer   
				CORR_DELTA_G: natural := 1*(2**5); 				--! MAF: If change was too high, last buffer value goes into "direction" with CORR_DELTA_G
				-- PI settings 
				ANTI_WINDUP_G		: integer 				:= 50*(2**5); --! maximum error for integration active 
				GAINBM_G			: natural range 0 to 16 := 12; 			--! fractional fixed points bit
				GAINBP_G			: natural range 1 to 16 := 4; 			--! integer bits
				--Kprop_G				: integer				:= 16384;		--! Proportional gain:  Kp*(2**GAINBM)
				--KixTs_G				: integer				:= 5000; 	--! Integral gain:  (Ki/fs)*(2**GAINBM)	
				-- Hysteresis settings 
				NO_CONTROLER_G 		: integer := 6 ; --!  Total number of controler used (slaves + master)
				DELTA_I_REF_G 		: integer := 10*(2**5)*6; --! minimum set current change (60 A) for entering hysteresis mode 
				DELTA_I_THR_G 		: integer := 10*(2**5)*6; --! minimum current difference (60 A) between measured and set current for entering hysteresis mode 
				DELTA_VC_G			: integer := 100*(2**5); --! minimum VC change change (100 V) for entering hysteresis mode 
				D_IOUT_MAX_G		: integer := 30*(2**5); --! Maximum current ripple after first rise (here 20A) 
				HYST_COND_SEL_G		: std_logic_vector(2 downto 0):= "001"; --! Enable conditions for entering hysteresis: 2: vc, 1: ierr, 0: iset
                TIME_DELAY_CONSTANT : integer := 50; --! Delay/L * 2**12. By default this is 7/250 * 4096. This is used for the initial compensation for the hysteresis bounds.
                DELAY_COMP_CONSTANT : integer := 250000*(2**5); -- Constant for delay compensation in the 2nd rise. (2*H0*L*10**8)  		 
				N_CYCLE_REST_G		: integer := 0; --! Number of cycles controller stays in Hysterssis after phaseshift 
				-- Variable L points
				L1_G				: real 	  := 0.00025;--0.00013; --! Inductance [H] at point 1 
				L2_G 				: real 	  := 0.00025;--0.000115; --! Inductance [H] at point 2 
				L3_G 				: real 	  := 0.00025;--0.00003; --! Inductance [H] at point 3 
				A1_G				: real	  := 160.0; --! Current [A] corner 1 
				A2_G 				: real	  := 250.0; --! Current [A] corner 2 
				A3_G 				: real	  := 300.0  --! Current [A] corner 3 
		);
	port(
		clk_i			: in  std_logic;                            --! Main system clock 
		nreset_i    	: in  std_logic;                               --! asynchronous lowactive reset 
		nsoftreset_i	: in std_logic; 							--! softreset for whole PI chain including MAF 		
		data_clk_i 		: in std_logic; 								--! ~60 KHz clock PWM  
		sample_clk_i	: in std_logic; 								--! ~2 MHz sample clk
		hyst_enable_i	: in std_logic; --! enables hysteresis mode			
		vbush_i    		: in unsigned(MEAS_V_DATAWIDTH_G-1 downto 0); --! V1 measured voltage                                    			
		vbusl_i     	: in unsigned(MEAS_V_DATAWIDTH_G-1 downto 0); --! V2 measured voltage 
		vc_i 			: in signed(MEAS_I_DATAWIDTH_G-1 downto 0); --! Vc measured voltage
		imeas_i			: in array_signed_in(NO_CONTROLER_G-1 downto 0); --! Measured current  
		iset_i			: in array_signed_in(NO_CONTROLER_G-1 downto 0); --! Set current No.1 
		kprop_i			: in signed(GAINBM_G + GAINBP_G -1 downto 0);  --! PI control proportional gain:  kprop_i = Kp*(2**GAINBM)
		kixts_i			: in signed(GAINBM_G + GAINBP_G -1 downto 0);  --! PI control integral gain:  kixts = (Ki/fs)*(2**GAINBM)	
		pwm_o			: out std_logic_vector(2*NO_CONTROLER_G-1 downto 0); --! High switch output
		count_o			: out array_signed16(NO_CONTROLER_G-1 downto 0); --! PWM counter No.1 (testing)
		Rset_i 			: in unsigned(DATAWIDTH_G-1 downto 0);        --! Rset measured voltage		
		i_upper_o		: out array_signed16(NO_CONTROLER_G-1 downto 0); --! Hysteresis upper current bound No.1 (testing)
		i_lower_o		: out array_signed16(NO_CONTROLER_G-1 downto 0);  --! Hysteresis lower current bound No.2 (testing)
		d_o				: out array_signed16(NO_CONTROLER_G-1 downto 0);
		ierr_o			: out array_signed16(NO_CONTROLER_G-1 downto 0);
		pi_o			: out array_signed16(NO_CONTROLER_G-1 downto 0);
		vc_switch_i 	: in signed(MEAS_I_DATAWIDTH_G-1 downto 0); --! switchable input signal vc (00: no operation, 01: +, 10: -)
		switch_i		: in std_logic; -- Pascal: Added because at the moment it is still needed. Tsol: He means probably only for the model to run...
		hyst_vec_o		: out std_logic_vector(NO_CONTROLER_G-1 downto 0);  --! hystersis mode of all modules  		  		
		---------------------M3TC---------------------------------------------------
		MODE_put_to_3_i :  in  std_logic_vector(2 downto 0);
        Number_12_bit3_i:  in  std_logic_vector(11 downto 0);
		Number_8_bit_i 	:  in  std_logic_vector(7 downto 0);
		optical_fault_1_o:  out  std_logic;
		gate_c_1_o 		:  out  std_logic;
		gate_d_1_o 		:  out  std_logic;
		gate_1_1_o 		:  out  std_logic;
		gate_2_1_o 		:  out  std_logic;
		gate_3_1_o 		:  out  std_logic;
		gate_4_1_o 		:  out  std_logic;
		rst_c_1_o 		:  out  std_logic;
		rst_d_1_o 		:  out  std_logic;
		rst_overall_1_o	:  out  std_logic;
		optical_fault_2_o:  out  std_logic;
		gate_c_2_o 		:  out  std_logic;
		gate_d_2_o 		:  out  std_logic;
		gate_1_2_o 		:  out  std_logic;
		gate_2_2_o 		:  out  std_logic;
		gate_3_2_o 		:  out  std_logic;
		gate_4_2_o 		:  out  std_logic;
		rst_c_2_o 		:  out  std_logic;
		rst_d_2_o 		:  out  std_logic;
		rst_overall_2_o	:  out  std_logic;
		outFAULT_1_o	:  out  std_logic_vector(11 downto 0);
		outFAULT_2_o	:  out  std_logic_vector(11 downto 0);
		outTempHS_1_o 	:  out  std_logic_vector(11 downto 0);
		outTempHS_2_o 	:  out  std_logic_vector(11 downto 0);
		outTempIGBT_1_o	:  out  std_logic_vector(11 downto 0);
		outTempIGBT_2_o	:  out  std_logic_vector(11 downto 0);
		outVOLT_1_o		:  out  std_logic_vector(11 downto 0);
		outVOLT_2_o		:  out  std_logic_vector(11 downto 0)
		);			            							
end m3tc_hybrid;

architecture rtl of m3tc_hybrid is 

-- ================== COMPONENTS =================================================
	component hybrid_top is
	generic( 	CMAX_G 				: integer := 1666; --! Maximum counter value of PWM (determines PWM frequency) =>  ~60 KHz with 100 MHz clock 
				FS_G 				: real 	  := 60096.0; --! PWM frequency 
				F_CLK_G				: real 	  := 100.0*(10**6); --! Clock frequency  
				NINTERLOCK_G		: integer := 50; --50
				MEAS_I_DATAWIDTH_G 	: integer range 8 to 16 := 13;  --! Data width of current measurements  
				MEAS_V_DATAWIDTH_G	: integer range 8 to 16 := 12; --! Data width of voltage measurements 
				DATAWIDTH_G			: integer := 16; --! General internal datawidth: THIS HAS TO BE KEPT CONSTANT
				-- MAF settings 
				MAX_DELTA_G: natural := 200*(2**5); 				--! MAF: limitation of current change for storing in buffer   
				CORR_DELTA_G: natural := 1*(2**5); 				--! MAF: If change was too high, last buffer value goes into "direction" with CORR_DELTA_G
				-- PI settings 
				ANTI_WINDUP_G		: integer 				:= 50*(2**5); --! maximum error for integration active 
				GAINBM_G			: natural range 0 to 16 := 12; 			--! fractional fixed points bit
				GAINBP_G			: natural range 1 to 16 := 4; 			--! integer bits
				--Kprop_G				: integer				:= 16384;		--! Proportional gain:  Kp*(2**GAINBM)
				--KixTs_G				: integer				:= 5000; 	--! Integral gain:  (Ki/fs)*(2**GAINBM)	
				-- Hysteresis settings 
				NO_CONTROLER_G 		: integer := 6 ; --!  Total number of controler used (slaves + master)
				DELTA_I_REF_G 		: integer := 10*(2**5)*6; --! minimum set current change (25 A) for entering hysteresis mode 
				DELTA_I_THR_G 		: integer := 40*(2**5)*6; --! minimum current difference (25 A) between measured and set current for entering hysteresis mode 
				DELTA_VC_G			: integer := 100*(2**5); --! minimum VC change change (100 V) for entering hysteresis mode 
				D_IOUT_MAX_G		: integer := 10*(2**5); --! Maximum current ripple after first rise (here 20A)
                TIME_DELAY_CONSTANT : integer := 115; --! Delay/L * 2**12. By default this is 7/250 * 4096. This is used for the initial compensation for the hysteresis bounds.
                DELAY_COMP_CONSTANT : integer := 250000*(2**5); -- Constant for delay compensation in the 2nd rise. (2*H0*L*10**8)  		 
				HYST_COND_SEL_G		: std_logic_vector(2 downto 0):= "111"; --! Enable conditions for entering hysteresis: 2: vc, 1: ierr, 0: iset 
				N_CYCLE_REST_G		: integer := 0; --! Number of cycles controller stays in Hysterssis after phaseshift 
				-- Variable L points
				L1_G				: real 	  := 0.00025;--0.00013; --! Inductance [H] at point 1 
				L2_G 				: real 	  := 0.00025;--0.000115; --! Inductance [H] at point 2 
				L3_G 				: real 	  := 0.00025;--0.00003; --! Inductance [H] at point 3 
				A1_G				: real	  := 160.0; --! Current [A] corner 1 
				A2_G 				: real	  := 250.0; --! Current [A] corner 2 
				A3_G 				: real	  := 300.0  --! Current [A] corner 3 
		);
	port(
		clk_i			: in  std_logic;                               --! Main system clock 
		nreset_i    	: in  std_logic;                               --! asynchronous lowactive reset 
		nsoftreset_i	: in std_logic; 							--! softreset for whole PI chain including MAF 		
		data_clk_i 		: in std_logic; 								--! ~60 KHz clock PWM  
		sample_clk_i	: in std_logic; 								--! ~2 MHz sample clk
		hyst_enable_i	: in std_logic; --! enables hysteresis mode			
		vbush_i    		: in unsigned(MEAS_V_DATAWIDTH_G-1 downto 0); --! V1 measured voltage                                    			
		vbusl_i     	: in unsigned(MEAS_V_DATAWIDTH_G-1 downto 0); --! V2 measured voltage 
		vc_i 			: in signed(MEAS_I_DATAWIDTH_G-1 downto 0); --! Vc measured voltage
		Rset_i 			: in unsigned(DATAWIDTH_G-1 downto 0);        --! Rset measured voltage
		vc_switch_i 	: in signed(MEAS_I_DATAWIDTH_G-1 downto 0); --! switchable input signal vc (00: no operation, 01: +, 10: -)
		switch_i		: in std_logic_vector(1 downto 0); -- switch signal 		
		imeas_i			: in array_signed_in(NO_CONTROLER_G-1 downto 0); --! Measured current  
		iset_i			: in array_signed_in(NO_CONTROLER_G-1 downto 0); --! Set current No.1 
		kprop_i			: in signed(GAINBM_G + GAINBP_G -1 downto 0);  --! PI control proportional gain:  kprop_i = Kp*(2**GAINBM)
		kixts_i			: in signed(GAINBM_G + GAINBP_G -1 downto 0);  --! PI control integral gain:  kixts = (Ki/fs)*(2**GAINBM)	
		pwm_o			: out std_logic_vector(2*NO_CONTROLER_G-1 downto 0); --! High switch output
		count_o			: out array_signed16(NO_CONTROLER_G-1 downto 0); --! PWM counter No.1 (testing)
		i_upper_o		: out array_signed16(NO_CONTROLER_G-1 downto 0); --! Hysteresis upper current bound No.1 (testing)
		i_lower_o		: out array_signed16(NO_CONTROLER_G-1 downto 0);  --! Hysteresis lower current bound No.2 (testing)
		d_o				: out array_signed16(NO_CONTROLER_G-1 downto 0);
		ierr_o			: out array_signed16(NO_CONTROLER_G-1 downto 0);
		pi_o			: out array_signed16(NO_CONTROLER_G-1 downto 0);
		hyst_vec_o		: out std_logic_vector(NO_CONTROLER_G-1 downto 0);  --! hystersis mode of all modules  		  		
		iset_tot_o		: out std_logic_vector(11 downto 0); --! total measured current only integer bits
		imeas_tot_o		: out std_logic_vector(11 downto 0)  --! total measured current only integer bits 
		);			            							
end component;

component Compact_m3tc IS 
	PORT
	(
		CLK_Master :  IN  STD_LOGIC;
		optical_Clk_1 :  IN  STD_LOGIC;
		nreset :  IN  STD_LOGIC;
		HIGH_Input :  IN  STD_LOGIC;
		masterCurrentMeas :  IN  STD_LOGIC_VECTOR(11 DOWNTO 0);
		masterCurrentRef :  IN  STD_LOGIC_VECTOR(11 DOWNTO 0);
		masterVOLT :  IN  STD_LOGIC_VECTOR(11 DOWNTO 0);
		MODE_put_to_3 :  IN  STD_LOGIC_VECTOR(2 DOWNTO 0);
		Number_12_bit3 :  IN  STD_LOGIC_VECTOR(11 DOWNTO 0);
		Number_8_bit :  IN  STD_LOGIC_VECTOR(7 DOWNTO 0);
		optical_fault_1 :  OUT  STD_LOGIC;
		gate_c_1 :  OUT  STD_LOGIC;
		gate_d_1 :  OUT  STD_LOGIC;
		gate_1_1 :  OUT  STD_LOGIC;
		gate_2_1 :  OUT  STD_LOGIC;
		gate_3_1 :  OUT  STD_LOGIC;
		gate_4_1 :  OUT  STD_LOGIC;
		rst_c_1 :  OUT  STD_LOGIC;
		rst_d_1 :  OUT  STD_LOGIC;
		rst_overall_1 :  OUT  STD_LOGIC;
		optical_fault_2 :  OUT  STD_LOGIC;
		gate_c_2 :  OUT  STD_LOGIC;
		gate_d_2 :  OUT  STD_LOGIC;
		gate_1_2 :  OUT  STD_LOGIC;
		gate_2_2 :  OUT  STD_LOGIC;
		gate_3_2 :  OUT  STD_LOGIC;
		gate_4_2 :  OUT  STD_LOGIC;
		rst_c_2 :  OUT  STD_LOGIC;
		rst_d_2 :  OUT  STD_LOGIC;
		rst_overall_2 :  OUT  STD_LOGIC;
		outFAULT_1 :  OUT  STD_LOGIC_VECTOR(11 DOWNTO 0);
		outFAULT_2 :  OUT  STD_LOGIC_VECTOR(11 DOWNTO 0);
		outTempHS_1 :  OUT  STD_LOGIC_VECTOR(11 DOWNTO 0);
		outTempHS_2 :  OUT  STD_LOGIC_VECTOR(11 DOWNTO 0);
		outTempIGBT_1 :  OUT  STD_LOGIC_VECTOR(11 DOWNTO 0);
		outTempIGBT_2 :  OUT  STD_LOGIC_VECTOR(11 DOWNTO 0);
		outVOLT_1 :  OUT  STD_LOGIC_VECTOR(11 DOWNTO 0);
		outVOLT_2 :  OUT  STD_LOGIC_VECTOR(11 DOWNTO 0); 
		sw_Vprecontrol_o :  OUT  STD_LOGIC_VECTOR(1 DOWNTO 0)
	);
END component;

-- ================== CONSTANTS ==================================================				
		
	
-- =================== SIGNALS ===================================================
	signal iset_tot_m3tc_s : std_logic_vector(11 downto 0) := (others => '0'); 
	signal imeas_tot_m3tc_s : std_logic_vector(11 downto 0) := (others => '0'); 
	signal vc_m3tc_s 	: std_logic_vector(11 downto 0) := (others => '0'); 
	signal sw_Vprecontrol_s : std_logic_vector(1 downto 0) := "00"; 
-- =================== STATES ====================================================
	begin
	
		
	inst_hybrid_top_6: hybrid_top
		generic map( CMAX_G 			=> CMAX_G,       		
					FS_G 				=> FS_G, 				
					F_CLK_G				=> F_CLK_G,				
					NINTERLOCK_G		=> NINTERLOCK_G,		    
					MEAS_I_DATAWIDTH_G 	=> MEAS_I_DATAWIDTH_G, 	
					MEAS_V_DATAWIDTH_G	=> MEAS_V_DATAWIDTH_G,	
					DATAWIDTH_G			=> DATAWIDTH_G,			
					-- MAF settings                             
					MAX_DELTA_G			=> MAX_DELTA_G,			
					CORR_DELTA_G		=> CORR_DELTA_G,		    
					-- PI settings                              
					ANTI_WINDUP_G		=> ANTI_WINDUP_G,		
					GAINBM_G			=> GAINBM_G,			    
					GAINBP_G			=> GAINBP_G,			    
				-- Hysteresis settings                          
					NO_CONTROLER_G 		=> NO_CONTROLER_G, 		
					DELTA_I_REF_G 		=> DELTA_I_REF_G, 		
					DELTA_I_THR_G 		=> DELTA_I_THR_G, 		
					DELTA_VC_G			=> DELTA_VC_G,			
					D_IOUT_MAX_G		=> D_IOUT_MAX_G,		    
					HYST_COND_SEL_G		=> HYST_COND_SEL_G,	
                    TIME_DELAY_CONSTANT => TIME_DELAY_CONSTANT,
                    DELAY_COMP_CONSTANT	=> DELAY_COMP_CONSTANT,	
					N_CYCLE_REST_G		=> N_CYCLE_REST_G,		
					-- Variable L points                        
					L1_G				=> L1_G,				    
					L2_G 				=> L2_G, 				
					L3_G 				=> L3_G, 				
					A1_G				=> A1_G,				    
					A2_G 				=> A2_G, 				
					A3_G 				=> A3_G 				
			)
		port map(
			clk_i			=> clk_i,                               --! Main system clock 
			nreset_i    	=> nreset_i,                                --! asynchronous lowactive reset 
			nsoftreset_i	=> nsoftreset_i,						--! softreset for whole PI chain including MAF 		
			data_clk_i 		=> data_clk_i, 		
			sample_clk_i	=> sample_clk_i,	
			hyst_enable_i	=> hyst_enable_i,	
			vbush_i    		=> vbush_i,    			
			vbusl_i     	=> vbusl_i,     	
			vc_i 			=> vc_i, 			
			vc_switch_i 	=> vc_switch_i,
			switch_i		=> sw_Vprecontrol_s,	
			imeas_i			=> imeas_i,		
			iset_i			=> iset_i,
            Rset_i 			=> Rset_i, 			
			kprop_i			=> kprop_i,	
			kixts_i			=> kixts_i,			
			pwm_o			=> pwm_o,
			count_o			=> count_o, --! PWM counter No.1 (testing)
			i_upper_o		=> i_upper_o, --! Hysteresis upper current bound No.1 (testing)
			i_lower_o		=> i_lower_o,  --! Hysteresis lower current bound No.2 (testing)
			d_o				=> d_o,
			ierr_o			=> ierr_o,
			pi_o			=> pi_o,
            hyst_vec_o		=> hyst_vec_o,
			iset_tot_o		=> iset_tot_m3tc_s, 
			imeas_tot_o		=> imeas_tot_m3tc_s
			);			

				
				
		inst_compactM3TC: Compact_m3tc 
	port map
	(
		CLK_Master 			=> clk_i, 
		optical_Clk_1 		=> clk_i, 
		nreset 				=> nreset_i, 
		HIGH_Input 			=> '1', 
		masterCurrentMeas 	=> imeas_tot_m3tc_s,
		masterCurrentRef 	=> iset_tot_m3tc_s, 
		masterVOLT 			=> vc_m3tc_s, 
		MODE_put_to_3		=> MODE_put_to_3_i, 
		Number_12_bit3 		=> Number_12_bit3_i,
		Number_8_bit 		=> Number_8_bit_i, 
		optical_fault_1 	=> optical_fault_1_o, 
		gate_c_1            => gate_c_1_o,         
		gate_d_1            => gate_d_1_o,         
		gate_1_1            => gate_1_1_o,         
		gate_2_1            => gate_2_1_o,          
		gate_3_1            => gate_3_1_o,          
		gate_4_1            => gate_4_1_o,          
		rst_c_1             => rst_c_1_o,           
		rst_d_1             => rst_d_1_o,           
		rst_overall_1       => rst_overall_1_o,     
		optical_fault_2     => optical_fault_2_o,   
		gate_c_2            => gate_c_2_o,          
		gate_d_2            => gate_d_2_o,          
		gate_1_2            => gate_1_2_o,          
		gate_2_2            => gate_2_2_o,          
		gate_3_2            => gate_3_2_o,          
		gate_4_2            => gate_4_2_o,          
		rst_c_2             => rst_c_2_o,           
		rst_d_2             => rst_d_2_o,           
		rst_overall_2       => rst_overall_2_o,     
		outFAULT_1          => outFAULT_1_o,       
		outFAULT_2          => outFAULT_2_o,        
		outTempHS_1         => outTempHS_1_o,       
		outTempHS_2         => outTempHS_2_o,       
		outTempIGBT_1       => outTempIGBT_1_o,     
		outTempIGBT_2       => outTempIGBT_2_o,     
		outVOLT_1           => outVOLT_1_o,         
		outVOLT_2           => outVOLT_2_o ,
		sw_Vprecontrol_o	=> sw_Vprecontrol_s	
	);

	
	vc_m3tc_s <= std_logic_vector(resize(vc_i(vc_i'length -1 downto 2),12)); 
	
	
	

end rtl; 