" Vim syntax file
" Language:     Liberty library definition
" Maintainer:   Peter Debacker "pdback@imec.be"
" Last Change:  27/09/2012
"
" This is based on spectre .vim by Ahmed Nabil

" For version 5.x: Clear all syntax items
" For version 6.x: Quit when a syntax file was already loaded
if version < 600
  syntax clear
elseif exists("b:current_syntax")
  finish
endif

" Liberty syntax is case INsensitive
syn case ignore
setlocal iskeyword=@,48-57,_

syn keyword     libertyTodo        contained TODO

" Numbers, all with engineering suffixes and optional units
"==========================================================
"floating point number, with dot, optional exponent
syn match libertyNumber  "\<[0-9]\+\.[0-9]*\(e[-+]\=[0-9]\+\)\=\(meg\=\|[afpnumkg]\)\="
"floating point number, starting with a dot, optional exponent
syn match libertyNumber  "\.[0-9]\+\(e[-+]\=[0-9]\+\)\=\(meg\=\|[afpnumkg]\)\="
"integer number with optional exponent
syn match libertyNumber  "\<[0-9]\+\(e[-+]\=[0-9]\+\)\=\(meg\=\|[afpnumkg]\)\="

" Defined value keywords
syn keyword     libertyValue       true false power ground power_and_ground sa0 sa1 sa01 pull_up pull_down open_drain
syn keyword     libertyValue       open_source bus_hold resistive resistive_0 resistive_1 input output inout internal
syn keyword     libertyValue       data preset clear load scan_in scan_enable clock_enable active_high active_low
syn keyword     libertyValue       active_rising active_falling edge_trigger leading trailing L H R F low medium high
syn keyword     libertyValue       none test_scan_in test_scan_in_inverted test_scan_out test_scan_out_inverted
syn keyword     libertyValue       test_scan_enable test_scan_enable_invertedtest_scan_clock test_scan_clock_a
syn keyword     libertyValue       test_scan_clock_b test_clock rising falling
syn keyword     libertyValue       positive_unate negative_unate combinational combinational_rise combinational_fall
syn keyword     libertyValue       three_state_disable three_state_disable_rise three_state_disable_fall three_state_enable
syn keyword     libertyValue       three_state_enable_rise three_state_enable_fallrising_edge falling_edge preset clear
syn keyword     libertyValue       hold_rising hold_falling setup_rising setup_falling recovery_rising recovery_falling
syn keyword     libertyValue       skew_rising skew_falling removal_rising removal_falling min_pulse_width minimum_period
syn keyword     libertyValue       max_clock_tree_path min_clock_tree_pathnon_seq_setup_rising non_seq_setup_falling
syn keyword     libertyValue       non_seq_hold_rising non_seq_hold_falling nochange_high_high nochange_high_low
syn keyword     libertyValue       nochange_low_high nochange_low_low  positive_unate negative_unate combinational
syn keyword     libertyValue       combinational_rise combinational_fall three_state_disable three_state_disable_rise
syn keyword     libertyValue       three_state_disable_fall three_state_enable three_state_enable_rise three_state_enable_fallrising_edge
syn keyword     libertyValue       falling_edge preset clear hold_rising hold_falling setup_rising setup_falling recovery_rising
syn keyword     libertyValue       recovery_falling skew_rising skew_falling removal_rising removal_falling min_pulse_width minimum_period
syn keyword     libertyValue       max_clock_tree_path min_clock_tree_pathnon_seq_setup_rising non_seq_setup_falling non_seq_hold_rising
syn keyword     libertyValue       non_seq_hold_falling nochange_high_high nochange_high_low nochange_low_high nochange_low_low
syn keyword     libertyValue       positive_unate negative_unate combinational combinational_rise combinational_fall three_state_disable
syn keyword     libertyValue       three_state_disable_rise three_state_disable_fall three_state_enable three_state_enable_rise
syn keyword     libertyValue       three_state_enable_fallrising_edge falling_edge preset clear hold_rising hold_falling setup_rising
syn keyword     libertyValue       setup_falling recovery_rising recovery_falling skew_rising skew_falling removal_rising removal_falling
syn keyword     libertyValue       min_pulse_width minimum_period max_clock_tree_path min_clock_tree_pathnon_seq_setup_rising
syn keyword     libertyValue       non_seq_setup_falling non_seq_hold_rising non_seq_hold_falling nochange_high_high nochange_high_low
syn keyword     libertyValue       nochange_low_high nochange_low_low

" Group names
"============
syn match libertyGroupName "\<[a-z]\+[0-9a-z_]*\>" contained

" Library Group and its attributes and subgroups
"===============================================
syn keyword     libertyGroup       library
syn keyword     libertySimpleAttr  bus_naming_style comment current_unit date default_fpga_isd
syn keyword     libertySimpleAttr  default_threshold_voltage_group delay_model distance_unit dist_conversion_factor
syn keyword     libertySimpleAttr  em_temp_degradation_factor fpga_domain_style fpga_technology in_place_swap_mode
syn keyword     libertySimpleAttr  input_threshold_pct_fall input_threshold_pct_rise leakage_power_unit nom_calc_mode
syn keyword     libertySimpleAttr  nom_process nom_temperature nom_voltage output_threshold_pct_fall output_threshold_pct_rise
syn keyword     libertySimpleAttr  piece_type power_model preferred_output_pad_slew_rate_control preferred_input_pad_voltage
syn keyword     libertySimpleAttr  preferred_output_pad_voltage pulling_resistance_unit revision simulation
syn keyword     libertySimpleAttr  slew_derate_from_library slew_lower_threshold_pct_fall slew_lower_threshold_pct_rise
syn keyword     libertySimpleAttr  slew_upper_threshold_pct_fall slew_upper_threshold_pct_rise time_unit voltage_unit
syn keyword     libertySimpleAttr  base_curves_group variable_1 variable_2 variable_3 default_operating_conditions
syn keyword     libertySimpleAttr  default_wire_load_selection default_wire_load default_wire_load_mode
syn keyword     libertySimpleAttr  in_place_swap_mode default_max_transition default_inout_pin_cap default_input_pin_cap
syn keyword     libertySimpleAttr  default_output_pin_cap default_leakage_power_density default_fanout_load
syn keyword     libertyComplexAttr capacitive_load_unit default_part define define_cell_area define_group
syn keyword     libertyComplexAttr piece_define routing_layers technology voltage_map base_curve_type
syn keyword     libertyComplexAttr curve_x curve_y index_1 index_2 index_3 pin_names vector library_features
syn keyword     libertyGroup       base_curves compact_lut_template char_config dc_current_template em_lut_template
syn keyword     libertyGroup       fall_net_delay fall_transition_degradation faults_lut_template input_voltage fpga_isd
syn keyword     libertyGroup       iv_lut_template lu_table_template maxcap_lut_template maxtrans_lut_template
syn keyword     libertyGroup       noise_lut_template normalized_driver_waveform operating_conditions output_current_template
syn keyword     libertyGroup       output_voltage part pg_current_template poly_template power_lut_template power_poly_template
syn keyword     libertyGroup       power_supply propagation_lut_template rise_net_delay rise_transition_degradation
syn keyword     libertyGroup       scaled_cell sensitization scaling_factors timing timing_range type user_parameters
syn keyword     libertyGroup       wire_load wire_load_selection wire_load_table critical_area_lut_template
syn keyword     libertyGroup       device_layer poly_layer routing_layer cont_layer
" These are the attributes for the library subgroups
"   Simple
syn keyword     libertySimpleAttr  base_curves_group variable_1 variable_2 variable_3 variable_4 three_state_disable_measurement_method
syn keyword     libertySimpleAttr  three_state_disable_current_threshold_abs three_state_disable_current_threshold_rel three_state_disable_monitor_node
syn keyword     libertySimpleAttr  three_state_cap_add_to_load_index ccs_timing_segment_voltage_tolerance_rel ccs_timing_delay_tolerance_rel
syn keyword     libertySimpleAttr  ccs_timing_voltage_margin_tolerance_rel receiver_capacitance1_voltage_lower_threshold_pct_rise
syn keyword     libertySimpleAttr  receiver_capacitance1_voltage_upper_threshold_pct_rise receiver_capacitance1_voltage_lower_threshold_pct_fall
syn keyword     libertySimpleAttr  receiver_capacitance1_voltage_upper_threshold_pct_fall receiver_capacitance2_voltage_lower_threshold_pct_rise
syn keyword     libertySimpleAttr  receiver_capacitance2_voltage_upper_threshold_pct_rise receiver_capacitance2_voltage_lower_threshold_pct_fall
syn keyword     libertySimpleAttr  receiver_capacitance2_voltage_upper_threshold_pct_fall capacitance_voltage_lower_threshold_pct_rise
syn keyword     libertySimpleAttr  capacitance_voltage_lower_threshold_pct_fall capacitance_voltage_upper_threshold_pct_rise
syn keyword     libertySimpleAttr  capacitance_voltage_upper_threshold_pct_fall vil vih vimin vimax vol voh vomin vomax drive io_type slew
syn keyword     libertySimpleAttr  calc_mode parameteri process temperature tree_type voltage default_step_level fpga_isd num_blockrams
syn keyword     libertySimpleAttr  num_cols num_ffs num_luts num_rows pin_count default_power_rail area auxiliary_pad_cell bus_naming_style
syn keyword     libertySimpleAttr  cell_footprint cell_leakage_power clock_gating_integrated_cell contention_condition dont_fault dont_touch
syn keyword     libertySimpleAttr  dont_use handle_negative_constraint false is_clock_gating_cell map_only pad_cell pad_type preferred scaling_factors
syn keyword     libertySimpleAttr  single_bit_degenerate use_for_size_only vhdl_name faster_factor slower_factor base_type bit_from bit_to bit_width
syn keyword     libertySimpleAttr  data_type downto base_type bit_from bit_to bit_width data_type downto parameter area capacitance resistance slope value
"   Complex
syn keyword     libertyComplexAttr base_curve_type curve_x curve_y index_1 index_2 index_3 index_4 driver_waveform driver_waveform_rise driver_waveform_fall
syn keyword     libertyComplexAttr input_stimulus_transition input_stimulus_interval unrelated_output_net_capacitance default_value_selection_method
syn keyword     libertyComplexAttr default_value_selection_method_rise default_value_selection_method_fall merge_tolerance_abs merge_tolerance_rel merge_selection
syn keyword     libertyComplexAttr values power_rail max_count valid_speed_grade valid_step_level variables variable_n_range mapping orders power_rail
syn keyword     libertyComplexAttr pin_equal pin_opposite rail_connection pin_names vector fanout_length wire_load_from_area fanout_area fanout_capacitance
syn keyword     libertyComplexAttr fanout_length fanout_resistance
"   Group
syn keyword     libertyGroup       domain speed_grade

" Cell Group and its attributes and subgroups
"============================================
syn keyword     libertyGroup       cell
syn keyword     libertySimpleAttr  always_on antenna_diode_type area auxiliary_pad_cell
syn keyword     libertySimpleAttr  base_name bus_naming_style cell_footprint cell_leakage_power
syn keyword     libertySimpleAttr  clock_gating_integrated_cell contention_condition
syn keyword     libertySimpleAttr  dont_fault dont_touch dont_use driver_type em_temp_degradation_factor
syn keyword     libertySimpleAttr  fpga_domain_style handle_negative_constraint interface_timing
syn keyword     libertySimpleAttr  io_type is_clock_gating_cell is_clock_isolation_cell is_isolation_cell
syn keyword     libertySimpleAttr  map_only pad_cell pad_type power_cell_type preferred retention_cell
syn keyword     libertySimpleAttr  scaling_factors single_bit_degenerate slew_type timing_model_type
syn keyword     libertySimpleAttr  use_for_size_only vhdl_name
syn keyword     libertyComplexAttr pin_equal pin_opposite rail_connection
syn keyword     libertyGroup       bundle bus clear_condition clock_condition dynamic_current ff
syn keyword     libertyGroup       ff_bank functional_yield_metric generated_clock intrinsic_parasitic
syn keyword     libertyGroup       latch latch_bank leakage_current leakage_power lut mode_definition
syn keyword     libertyGroup       pin preset_condition retention_condition routing_track statetable
syn keyword     libertyGroup       test_cell type pg_pin


" Model Group and its attributes and subgroups
"===a==========================================
syn keyword     libertyGroup       model
syn keyword     libertySimpleAttr  cell_name
syn keyword     libertyComplexAttr short

" Pin Group and its attributes and subgroups
"===========================================
syn keyword     libertyGroup       pin
syn keyword     libertySimpleAttr  always_on antenna_diode_type antenna_diode_related_ground_pins antenna_diode_related_power_pins
syn keyword     libertySimpleAttr  bit_width capacitance clock clock_gate_clock_pin clock_gate_enable_pin clock_gate_test_pin clock_gate_obs_pin
syn keyword     libertySimpleAttr  clock_gate_out_pin clock_isolation_cell_clock_pin complementary_pin connection_class direction
syn keyword     libertySimpleAttr  dont_fault drive_current driver_type fall_capacitance fall_current_slope_after_threshold
syn keyword     libertySimpleAttr  fall_current_slope_before_threshold fall_time_after_threshold fall_time_before_threshold fanout_load
syn keyword     libertySimpleAttr  fault_model function has_builtin_pad hysteresis input_map input_signal_level input_voltage internal_node
syn keyword     libertySimpleAttr  inverted_output is_pad max_capacitance max_fanout max_input_noise_width max_transition min_capacitance
syn keyword     libertySimpleAttr  min_fanout min_input_noise_width min_period min_pulse_width_high min_pulse_width_low min_transition
syn keyword     libertySimpleAttr  multicell_pad_pin nextstate_type output_signal_level output_voltage pin_func_type prefer_tied primary_output
syn keyword     libertySimpleAttr  pulling_current pulling_resistance restore_action restore_edge_type rise_capacitance rise_current_slope_after_threshold
syn keyword     libertySimpleAttr  rise_current_slope_before_threshold rise_time_after_threshold rise_time_before_threshold save_action
syn keyword     libertySimpleAttr  signal_type slew_control state_function test_output_only three_state vhdl_name x_function pg_type voltage_name
syn keyword     libertySimpleAttr  power_down_function
syn keyword     libertyComplexAttr fall_capacitance_range rise_capacitance_range
syn keyword     libertyGroup       electromigration hyperbolic_noise_above_high hyperbolic_noise_below_low hyperbolic_noise_high
syn keyword     libertyGroup       hyperbolic_noise_low internal_power max_trans min_pulse_width minimum_period timing tlatch
syn keyword     libertyGroup       ccsn_first_stage ccsn_last_stage char_config max_cap pin_capacitance receiver_capacitance
" Attributes for pin subgroups
" Simple
syn keyword     libertySimpleAttr is_inverting is_needed is_pass_gate miller_cap_fall miller_cap_rise stage_type when three_state_disable_measurement_method
syn keyword     libertySimpleAttr three_state_disable_current_threshold_abs three_state_disable_current_threshold_rel three_state_disable_monitor_node
syn keyword     libertySimpleAttr three_state_cap_add_to_load_index ccs_timing_segment_voltage_tolerance_rel ccs_timing_delay_tolerance_rel ccs_timing_voltage_margin_tolerance_rel
syn keyword     libertySimpleAttr receiver_capacitance1_voltage_lower_threshold_pct_rise receiver_capacitance1_voltage_upper_threshold_pct_rise receiver_capacitance1_voltage_lower_threshold_pct_fall
syn keyword     libertySimpleAttr receiver_capacitance1_voltage_upper_threshold_pct_fall receiver_capacitance2_voltage_lower_threshold_pct_rise receiver_capacitance2_voltage_upper_threshold_pct_rise
syn keyword     libertySimpleAttr receiver_capacitance2_voltage_lower_threshold_pct_fall receiver_capacitance2_voltage_upper_threshold_pct_fall capacitance_voltage_lower_threshold_pct_rise
syn keyword     libertySimpleAttr capacitance_voltage_lower_threshold_pct_fall capacitance_voltage_upper_threshold_pct_rise capacitance_voltage_upper_threshold_pct_fall
syn keyword     libertySimpleAttr related_pin related_bus_pins area_coefficient height_coefficient width_coefficient equal_or_opposite_output falling_together_group
syn keyword     libertySimpleAttr power_level related_pin related_pg_pin rising_together_group switching_interval switching_together_group
syn keyword     libertySimpleAttr when constraint_high constraint_low when sdf_cond constraint clock_gating_flag default_timing fall_resistance
syn keyword     libertySimpleAttr fpga_arc_condition fpga_domain_style interdependence_id intrinsic_fall intrinsic_rise related_bus_equivalent
syn keyword     libertySimpleAttr related_bus_pins related_output_pin related_pin rise_resistance sdf_cond sdf_cond_end sdf_cond_start sdf_edges
syn keyword     libertySimpleAttr slope_fall slope_rise steady_state_resistance_above_high steady_state_resistance_below_low steady_state_resistance_high
syn keyword     libertySimpleAttr steady_state_resistance_low tied_off timing_sense non_unate timing_type when when_end when_start edge_type
syn keyword     libertySimpleAttr tdisable related_ground_pin related_power_pin
" Complex
syn keyword     libertyComplexAttr dc_current output_voltage_fall output_voltage_rise propagated_noise_low propagated_noise_rise driver_waveform
syn keyword     libertyComplexAttr driver_waveform_rise driver_waveform_fall input_stimulus_transition input_stimulus_interval unrelated_output_net_capacitance
syn keyword     libertyComplexAttr default_value_selection_method default_value_selection_method_rise default_value_selection_method_fall merge_tolerance_abs
syn keyword     libertyComplexAttr merge_tolerance_rel merge_selection variable_1_range variable_2_range variable_n_range orders coefs fall_delay_intercept
syn keyword     libertyComplexAttr fall_pin_resistance rise_delay_intercept rise_pin_resistance
" Group
syn keyword     libertyGroup       em_max_toggle_rate domain fall_power power rise_power capacitance rise_capacitance fall_capacitance fall_capacitance_range
syn keyword     libertyGroup       rise_capacitance_range receiver_capacitance1_fall receiver_capacitance1_rise receiver_capacitance2_fall receiver_capacitance2_rise
syn keyword     libertyGroup       cell_degradation cell_fall cell_rise char_config fall_constraint fall_propagation fall_transition noise_immunity_above_high
syn keyword     libertyGroup       noise_immunity_below_low noise_immunity_high noise_immunity_low output_current_fall output_current_rise propagated_noise_height_above_high
syn keyword     libertyGroup       propagated_noise_height_below_low propagated_noise_height_high propagated_noise_height_low propagated_noise_peak_time_ratio_above_high
syn keyword     libertyGroup       propagated_noise_peak_time_ratio__below_low propagated_noise_peak_time_ratio_high propagated_noise_peak_time_ratio_low
syn keyword     libertyGroup       propagated_noise_width_above_high propagated_noise_width_below_low propagated_noise_width_high propagated_noise_width_low
syn keyword     libertyGroup       receiver_capacitance1_fall receiver_capacitance1_rise receiver_capacitance2_fall receiver_capacitance2_rise
syn keyword     libertyGroup       retaining_fall retaining_rise retain_fall_slew retain_rise_slew rise_constraint rise_propagation rise_transition
syn keyword     libertyGroup       steady_state_current_high steady_state_current_low steady_state_current_tristate

" Misc
"=====
syn match   libertyWrapLineOperator       "\\$"
syn match   libertyIgnore                 "\ \ \ "

syn region  libertyString       start=+"+ skip=+\\\\\|\\"+ end=+"+

syn region libertyComment start="/\*" end="\*/" contains=libertyTodo

" Matching pairs of parentheses
"==========================================
syn region  libertyParen      transparent matchgroup=libertyOperator start="(" end=")" contains=libertyGroupName,libertyString,libertyNumber
syn region  libertyCurlyBrace transparent matchgroup=libertyOperator start="{" end="}" contains=ALLBUT,libertyCurlyBraceError,libertyGroupName
"syn match libertyKeyword /)\ \<[a-z]\+[0-9]*[a-z]*\>\ /

" Errors
"=======
syn match libertyParenError ")"
syn match libertyCurlyBraceError "}"

" Syncs
" =====
syn sync minlines=50

" Define the default highlighting.
" For version 5.7 and earlier: only when not done already
" For version 5.8 and later: only when an item doesn't have highlighting yet
if version >= 508 || !exists("did_liberty_syntax_inits")
  if version < 508
    let did_liberty_syntax_inits = 1
    command -nargs=+ HiLink hi link <args>
  else
    command -nargs=+ HiLink hi def link <args>
  endif

  HiLink libertyTodo             Todo
  HiLink libertyWrapLineOperator libertyOperator
  HiLink libertySinglequote      libertyExpr
  HiLink libertyExpr             Function
  HiLink libertyParenError       Error
  HiLink libertyNumber           Number
  HiLink libertyValue            String
  HiLink libertyComment          Comment
  HiLink libertyOperator         Operator
  HiLink libertyString           String
  HiLink libertyGroup            Type
  HiLink libertyGroupName        String
  HiLink libertySimpleAttr       Statement
  HiLink libertyComplexAttr      Statement
  HiLink libertyIgnore           Ignore

  delcommand HiLink
endif

let b:current_syntax = "liberty"

" TODO
" insert the following to $VIM/syntax/scripts.vim
" to autodetect HSpice netlists and text listing output:
"
" " Spice netlists and text listings
" elseif getline(1) =~ 'liberty\>' || getline("$") =~ '^\.end'
"   so <sfile>:p:h/liberty.vim

