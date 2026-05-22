source $ad_hdl_dir/library/axi_tdd/scripts/axi_tdd.tcl

proc libre_insert_timestamp_blocks {} {
  proc delete_intf_net_if_exists {pin} {
    set obj [get_bd_intf_pins -quiet $pin]
    if {[llength $obj] != 0} {
      set nets [get_bd_intf_nets -quiet -of_objects $obj]
      if {[llength $nets] != 0} {
        delete_bd_objs $nets
      }
    }
  }

  proc delete_pin_net_if_exists {pin} {
    set obj [get_bd_pins -quiet $pin]
    if {[llength $obj] != 0} {
      set nets [get_bd_nets -quiet -of_objects $obj]
      if {[llength $nets] != 0} {
        delete_bd_objs $nets
      }
    }
  }

  foreach cell {
    axi_ad9361
    axi_ad9361_adc_dma
    axi_ad9361_dac_dma
    cpack
    tx_upack
    rx_fir_decimator
    interp_slice
  } {
    if {[llength [get_bd_cells -quiet $cell]] == 0} {
      error "Required BD cell not found: $cell"
    }
  }

  if {[llength [get_bd_cells -quiet cpack_timestamp]] != 0} {
    puts "LibreSDR timestamp blocks already exist; skipping."
    return
  }

  delete_intf_net_if_exists cpack/packed_fifo_wr
  delete_intf_net_if_exists axi_ad9361_adc_dma/fifo_wr
  delete_intf_net_if_exists tx_upack/s_axis
  delete_intf_net_if_exists axi_ad9361_dac_dma/m_axis
  delete_pin_net_if_exists axi_ad9361_adc_dma/fifo_wr_sync
  delete_pin_net_if_exists tx_upack/reset

  if {[llength [get_property CONFIG.SYNC_TRANSFER_START [get_bd_cells axi_ad9361_adc_dma]]] != 0} {
    set_property CONFIG.SYNC_TRANSFER_START true [get_bd_cells axi_ad9361_adc_dma]
  }

  ad_ip_instance util_timestamp_timekeeper timestamp_timekeeper
  ad_ip_parameter timestamp_timekeeper CONFIG.TX_INTERP_FACTOR 8

  ad_ip_instance util_vector_logic timestamp_tx_raw_tick_or [list \
    C_OPERATION {or} \
    C_SIZE 1]

  ad_ip_instance util_cpack2_timestamp cpack_timestamp
  ad_ip_instance util_upack2_timestamp upack_timestamp
  ad_ip_parameter upack_timestamp CONFIG.TIMESTAMP_LIMIT_EVERY_MULTIPLE 4096

  ad_ip_instance xlslice cpack_timestamp_every_slice
  ad_ip_parameter cpack_timestamp_every_slice CONFIG.DIN_WIDTH 32
  ad_ip_parameter cpack_timestamp_every_slice CONFIG.DIN_FROM 31
  ad_ip_parameter cpack_timestamp_every_slice CONFIG.DIN_TO 1

  ad_ip_instance xlconcat cpack_timestamp_every_concat
  ad_ip_parameter cpack_timestamp_every_concat CONFIG.NUM_PORTS 2
  ad_ip_parameter cpack_timestamp_every_concat CONFIG.IN0_WIDTH 31
  ad_ip_parameter cpack_timestamp_every_concat CONFIG.IN1_WIDTH 1

  ad_ip_instance xlslice upack_timestamp_every_slice
  ad_ip_parameter upack_timestamp_every_slice CONFIG.DIN_WIDTH 32
  ad_ip_parameter upack_timestamp_every_slice CONFIG.DIN_FROM 31
  ad_ip_parameter upack_timestamp_every_slice CONFIG.DIN_TO 1

  ad_ip_instance xlconcat upack_timestamp_every_concat
  ad_ip_parameter upack_timestamp_every_concat CONFIG.NUM_PORTS 2
  ad_ip_parameter upack_timestamp_every_concat CONFIG.IN0_WIDTH 31
  ad_ip_parameter upack_timestamp_every_concat CONFIG.IN1_WIDTH 1

  ad_ip_instance util_wr_sync_mux timestamp_wr_sync_mux

  # Match the Wahlm Pluto+ timestamp integration: keep an AXI TDD block
  # as the external RX sync source and as an extra TX timestamp reset source.
  set TDD_CHANNEL_CNT 3
  set TDD_DEFAULT_POL 0b010
  set TDD_REG_WIDTH 32
  set TDD_BURST_WIDTH 32
  set TDD_SYNC_WIDTH 0
  set TDD_SYNC_INT 0
  set TDD_SYNC_EXT 1
  set TDD_SYNC_EXT_CDC 1
  ad_tdd_gen_create axi_tdd_0 $TDD_CHANNEL_CNT \
                              $TDD_DEFAULT_POL \
                              $TDD_REG_WIDTH \
                              $TDD_BURST_WIDTH \
                              $TDD_SYNC_WIDTH \
                              $TDD_SYNC_INT \
                              $TDD_SYNC_EXT \
                              $TDD_SYNC_EXT_CDC

  ad_ip_instance util_vector_logic timestamp_tdd_reset_inv [list \
    C_OPERATION {not} \
    C_SIZE 1]

  ad_ip_instance util_vector_logic timestamp_tx_reset_or [list \
    C_OPERATION {or} \
    C_SIZE 1]

  ad_connect axi_ad9361/l_clk timestamp_timekeeper/clk
  ad_connect axi_ad9361/rst timestamp_timekeeper/reset
  ad_connect rx_fir_decimator/valid_out_0 timestamp_timekeeper/rx_sample_tick
  ad_connect axi_ad9361/dac_valid_i0 timestamp_tx_raw_tick_or/Op1
  ad_connect axi_ad9361/dac_valid_i1 timestamp_tx_raw_tick_or/Op2
  ad_connect timestamp_tx_raw_tick_or/Res timestamp_timekeeper/tx_raw_sample_tick
  ad_connect interp_slice/Dout timestamp_timekeeper/tx_interpolation_active
  ad_connect timestamp_timekeeper/timestamp cpack_timestamp/timestamp
  ad_connect timestamp_timekeeper/timestamp upack_timestamp/timestamp

  ad_connect axi_ad9361/up_adc_gpio_out cpack_timestamp_every_slice/Din
  ad_connect cpack_timestamp_every_slice/Dout cpack_timestamp_every_concat/In0
  ad_connect GND cpack_timestamp_every_concat/In1
  ad_connect cpack_timestamp_every_concat/dout cpack_timestamp/timestamp_every

  ad_connect axi_ad9361/up_dac_gpio_out upack_timestamp_every_slice/Din
  ad_connect upack_timestamp_every_slice/Dout upack_timestamp_every_concat/In0
  ad_connect GND upack_timestamp_every_concat/In1
  ad_connect upack_timestamp_every_concat/dout upack_timestamp/timestamp_every

  ad_connect axi_ad9361/rst cpack/reset
  ad_connect axi_ad9361/l_clk cpack_timestamp/adc_clk
  ad_connect sys_cpu_clk cpack_timestamp/dma_clk
  ad_connect sys_cpu_clk cpack_timestamp/up_clk
  ad_connect cpack/packed_fifo_wr cpack_timestamp/packed_fifo_wr
  ad_connect cpack/packed_fifo_wr_sync cpack_timestamp/packed_fifo_wr_sync
  ad_connect cpack_timestamp/packed_timestamped_fifo_wr axi_ad9361_adc_dma/fifo_wr
  ad_connect cpack_timestamp/debug_status axi_ad9361/up_adc_gpio_in
  ad_connect cpack/fifo_wr_overflow axi_ad9361/adc_dovf

  ad_connect sys_cpu_clk upack_timestamp/dma_clk
  ad_connect axi_ad9361/l_clk upack_timestamp/dac_clk
  ad_connect axi_ad9361_dac_dma/m_axis upack_timestamp/s_axis
  ad_connect upack_timestamp/m_axis tx_upack/s_axis
  ad_connect upack_timestamp/reset_upack tx_upack/reset
  ad_connect axi_ad9361_dac_dma/m_axis_xfer_req upack_timestamp/s_axis_xfer_req
  ad_connect upack_timestamp/discarded_block_count axi_ad9361/up_dac_gpio_in

  ad_connect timestamp_tdd_reset_inv/Op1 axi_ad9361/rst
  ad_connect timestamp_tdd_reset_inv/Res axi_tdd_0/resetn
  ad_connect axi_ad9361/l_clk axi_tdd_0/clk
  ad_connect GND axi_tdd_0/sync_in

  ad_connect timestamp_tx_reset_or/Op1 axi_ad9361/rst
  ad_connect timestamp_tx_reset_or/Op2 axi_tdd_0/tdd_channel_2
  ad_connect timestamp_tx_reset_or/Res upack_timestamp/reset

  ad_connect sys_cpu_clk timestamp_wr_sync_mux/clk
  ad_connect cpack_timestamp_every_concat/dout timestamp_wr_sync_mux/timestamp_every
  ad_connect cpack_timestamp/packed_timestamped_fifo_wr_sync timestamp_wr_sync_mux/timestamp_wr_sync_in
  ad_connect axi_tdd_0/tdd_channel_1 timestamp_wr_sync_mux/ext_wr_sync_in
  ad_connect timestamp_wr_sync_mux/sync_out axi_ad9361_adc_dma/fifo_wr_sync

  ad_cpu_interconnect 0x7C440000 axi_tdd_0

}

libre_insert_timestamp_blocks
