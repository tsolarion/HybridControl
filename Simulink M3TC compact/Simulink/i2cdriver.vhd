LIBRARY IEEE;
USE IEEE.std_logic_1164.ALL;
USE IEEE.numeric_std.ALL;

PACKAGE i2cdriver_pkg IS
	COMPONENT i2cdriver IS
		PORT(
			isl_clock		: IN std_logic;
			isl_nreset		: IN std_logic;
			
			osl_scl			: OUT std_logic;
			iosl_sda			: INOUT std_logic;
			
			isl_dataselect	: IN std_logic;
			osl_data_rady	: OUT std_logic;
			oslv_dataout	: OUT std_logic_vector(7 DOWNTO 0)
			
			
		);
	END COMPONENT i2cdriver;
END PACKAGE i2cdriver_pkg;


---------------------------------------------------------------------------

LIBRARY IEEE;
USE IEEE.std_logic_1164.ALL;
USE IEEE.numeric_std.ALL;

ENTITY i2cdriver IS
	PORT(
		isl_clock		: IN std_logic; -- must be between 20 and 27 MHz
		isl_nreset		: IN std_logic;
			
		osl_scl			: OUT std_logic;
		iosl_sda			: INOUT std_logic;
			
		isl_dataselect	: IN std_logic;
		osl_data_rady	: OUT std_logic;
		oslv_dataout	: OUT std_logic_vector(7 DOWNTO 0)
		
		
	);
END ENTITY i2cdriver;

--------------------------------------------------------------------------

ARCHITECTURE rtl OF i2cdriver IS

	CONSTANT rx					: std_logic_vector(7 DOWNTO 0) 		:= "10010001";
	CONSTANT tx					: std_logic_vector(7 DOWNTO 0)		:= "10010000";
	CONSTANT conf_reg			: std_logic_vector(7 DOWNTO 0) 		:= x"01";
	CONSTANT data_conf_reg	: std_logic_vector(7 DOWNTO 0)		:= x"00";
	CONSTANT temp_reg			: std_logic_vector(7 DOWNTO 0)		:= x"00";
	CONSTANT counthighlength: unsigned(7 DOWNTO 0)					:= to_unsigned(136,8);
	CONSTANT countlowlength	: unsigned(7 DOWNTO 0)					:= to_unsigned(136,8);
	CONSTANT countlength_i2c: unsigned(4 DOWNTO 0)					:= to_unsigned(9,5);
	
	TYPE t_fsm_state IS (IDLE,READ_i2c,WRITE_i2c,START_READ,STOP);
	
	TYPE t_registers IS RECORD
		fsm_state		: t_fsm_state;
		sl_i2c_scl		: std_logic;
		slv_i2c_scl_buf: std_logic_vector(63 DOWNTO 0);
		usig_buf_ptr	: unsigned(5 DOWNTO 0);
		sl_i2c_sda		: std_logic;
		sl_i2c_sda_in	: std_logic;
		slv_data 		: std_logic_vector(7 DOWNTO 0);
		sl_dataselect	: std_logic;
		sl_dataselect_d1	: std_logic;
		sl_start_clock	: std_logic;
		sl_output_enable : std_logic;
		sl_watchdog		: std_logic;
		slv_dataout		: std_logic_vector(7 DOWNTO 0);
		usig_count		: unsigned(7 DOWNTO 0);
		usig_i2c_count	: unsigned(4 DOWNTO 0);
		slv_x_data		: std_logic_vector(7 DOWNTO 0);
		sl_data_ready	: std_logic;
		sl_data_ok		: std_logic;
	END RECORD t_registers;
	
	SIGNAL r,r_next	: t_registers;
	
BEGIN

	comb_proc : PROCESS (r,isl_nreset,iosl_sda,isl_clock,isl_dataselect)
	
		VARIABLE v		: t_registers;
		
	BEGIN
	
		v							:=r;
		v.sl_dataselect		:= isl_dataselect;
		v.sl_dataselect_d1	:= r.sl_dataselect;
		v.usig_count 			:= r.usig_count-1;
		v.slv_i2c_scl_buf(to_integer(r.usig_buf_ptr)) := r.sl_i2c_scl;
		v.usig_buf_ptr			:= r.usig_buf_ptr+1;
		v.sl_i2c_sda_in		:= iosl_sda;
		
		--Generierung des 100kHz Taktes
		IF r.usig_count <= 0 THEN
			IF r.sl_i2c_scl = '1' THEN
				v.usig_count := countlowlength;
			END IF;
			IF r.sl_i2c_scl = '0' THEN
				v.usig_count := counthighlength;
			END IF; 
			IF r.sl_start_clock ='1' THEN
				v.sl_i2c_scl := NOT r.sl_i2c_scl;
			END IF;
		END IF;
		
		CASE r.fsm_state IS
			
			WHEN IDLE =>
				v.sl_start_clock := '0';
				v.usig_count := countlowlength;
				v.sl_i2c_sda := '1';
				v.sl_i2c_scl := '1';
				v.sl_output_enable := '1';
				v.sl_data_ready := '0';
				IF r.sl_dataselect = '1' AND r.sl_dataselect_d1 = '0' THEN
					v.slv_dataout := (OTHERS => '0');
					v.usig_i2c_count := countlength_i2c;
					v.fsm_state := WRITE_i2c;
					v.sl_i2c_sda := '0';
					v.slv_data := tx;
					v.sl_start_clock := '1';
					v.sl_data_ok := '0';
				END IF;
				
			WHEN WRITE_i2c =>
				IF r.usig_i2c_count = 0 THEN
					v.sl_output_enable := '0';
					IF r.slv_i2c_scl_buf(to_integer(r.usig_buf_ptr-1)) = '0' THEN
						IF r.slv_i2c_scl_buf(to_integer(r.usig_buf_ptr-2)) = '1' THEN
							v.sl_watchdog := '1';
						END IF;
					END IF;
					IF r.sl_i2c_scl = '1' THEN
						IF r.sl_i2c_sda_in = '0' THEN
							v.usig_i2c_count := countlength_i2c;
							IF r.slv_data = tx THEN
								IF r.sl_data_ready = '0' THEN
									v.slv_data := conf_reg;
								ELSE
									v.slv_data := temp_reg;
								END IF;
							END IF;
							IF r.slv_data = conf_reg THEN
								v.slv_data := rx;
								v.sl_i2c_sda := '1';
								v.fsm_state := START_READ;
							END IF;
							IF r.slv_data = temp_reg THEN
								v.slv_data := rx;
								v.sl_i2c_sda := '1';
								v.fsm_state := START_READ;
							END IF;
							IF r.slv_data = rx THEN
								v.fsm_state := READ_i2c;
							END IF;
						END IF;
					END IF;
					
				ELSIF r.slv_i2c_scl_buf(to_integer(r.usig_buf_ptr-40)) = '0' THEN
					IF r.slv_i2c_scl_buf(to_integer(r.usig_buf_ptr-41)) = '1' THEN
						IF r.usig_i2c_count > 1 THEN
							v.sl_output_enable :='1';
							v.sl_i2c_sda := r.slv_data(to_integer(r.usig_i2c_count) - 2);
						END IF;
						v.usig_i2c_count := r.usig_i2c_count-1;
					END IF;
				END IF;
				
			WHEN START_READ =>
				IF r.slv_i2c_scl_buf(to_integer(r.usig_buf_ptr-40)) = '0' THEN
					IF r.slv_i2c_scl_buf(to_integer(r.usig_buf_ptr-41)) = '1' THEN
						v.sl_output_enable := '1';
						v.sl_i2c_sda := '1';
					END IF;
				END IF;
				
				IF r.slv_i2c_scl_buf(to_integer(r.usig_buf_ptr-40)) = '1' THEN
					IF r.slv_i2c_scl_buf(to_integer(r.usig_buf_ptr-41)) = '0' THEN
						IF r.sl_output_enable = '1' THEN
							v.sl_i2c_sda := '0';
							v.usig_count := counthighlength;
							v.fsm_state := WRITE_i2c;
						END IF;
					END IF;
				END IF;
				
			WHEN READ_i2c =>
				IF r.usig_i2c_count = 1 THEN
					v.sl_output_enable := '1';
					v.sl_i2c_sda := '1';
					IF r.slv_i2c_scl_buf(to_integer(r.usig_buf_ptr-40)) = '1' THEN
						IF r.slv_i2c_scl_buf(to_integer(r.usig_buf_ptr-41)) = '0' THEN
							v.usig_i2c_count := r.usig_i2c_count-1;
						END IF;
					END IF;	
				ELSIF r.usig_i2c_count = 0 THEN
					v.sl_output_enable := '1';
					IF r.sl_data_ready = '0' THEN
						v.fsm_state := START_READ;
						v.slv_data := tx;
						v.usig_i2c_count := countlength_i2c;
						v.sl_data_ready := r.slv_dataout(6);
					END IF;
					IF r.slv_i2c_scl_buf(to_integer(r.usig_buf_ptr-1)) = '0' THEN
						IF r.slv_i2c_scl_buf(to_integer(r.usig_buf_ptr-2)) = '1' THEN
							v.usig_i2c_count := countlength_i2c;
							v.sl_i2c_sda := '0';
							v.fsm_state := STOP;
							v.slv_x_data := r.slv_dataout;
						END IF;
					END IF;
				ELSIF r.slv_i2c_scl_buf(to_integer(r.usig_buf_ptr-40)) = '0' THEN
					v.sl_output_enable := '0';
					IF r.slv_i2c_scl_buf(to_integer(r.usig_buf_ptr-41)) = '1' THEN
						v.slv_dataout(to_integer(r.usig_i2c_count)-2) := r.sl_i2c_sda_in;
						v.usig_i2c_count := r.usig_i2c_count-1;
					END IF;
				END IF;
				
			WHEN STOP =>
				IF r.usig_i2c_count = 0 THEN
					IF r.slv_i2c_scl_buf(to_integer(r.usig_buf_ptr-40)) = '1' THEN
						IF r.slv_i2c_scl_buf(to_integer(r.usig_buf_ptr-41)) = '0' THEN
							v.sl_i2c_sda := '1';
							v.usig_count := countlowlength;
							v.sl_start_clock := '0';
						END IF;
					END IF;
				ELSIF r.slv_i2c_scl_buf(to_integer(r.usig_buf_ptr-40)) = '0' THEN
					IF r.slv_i2c_scl_buf(to_integer(r.usig_buf_ptr-41)) = '1' THEN
						v.sl_i2c_sda := '0';
						v.usig_i2c_count := (OTHERS => '0');
						v.sl_output_enable := '1';
						
					END IF;
				END IF;
				IF r.sl_start_clock = '0' THEN
					IF r.usig_count = 0 THEN
						v.fsm_state := IDLE;
						v.sl_data_ok := '1';
					END IF;
				END IF;
							
			END CASE;
			
		IF isl_nreset = '0' OR r.sl_watchdog = '1' THEN
			v.usig_count := (OTHERS => '0');
			v.fsm_state := IDLE;
			v.slv_x_data := (OTHERS => '0');
			v.sl_watchdog := '0';
			v.sl_data_ok := '0';
		END IF;
			
			
		 r_next	<= v;
	END PROCESS comb_proc;
	
	
	reg_proc : PROCESS (isl_clock)
	BEGIN
		IF rising_edge(isl_clock) THEN
			r <= r_next;
		END IF;
	END PROCESS reg_proc;
	
	
	out_proc : PROCESS (r)
	BEGIN
		IF r.sl_output_enable = '0' THEN
			iosl_sda <= 'Z';
		ELSE
			iosl_sda <=r.sl_i2c_sda;
		END IF;
	END PROCESS out_proc;
				
	osl_scl			<= r.sl_i2c_scl;
	oslv_dataout	<= r.slv_x_data;
	osl_data_rady	<= r.sl_data_ok;
					
END ARCHITECTURE rtl;			
		