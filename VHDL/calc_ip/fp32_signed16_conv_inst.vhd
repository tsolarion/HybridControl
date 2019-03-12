fp32_signed16_conv_inst : fp32_signed16_conv PORT MAP (
		clock	 => clock_sig,
		dataa	 => dataa_sig,
		nan	 => nan_sig,
		overflow	 => overflow_sig,
		result	 => result_sig,
		underflow	 => underflow_sig
	);
