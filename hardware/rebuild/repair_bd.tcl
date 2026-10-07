# Apply to an open design_ADB block design in Vivado (not XSCT/Vitis).
# Preserves the existing PS7 DDR/MIO configuration and control interconnect.
namespace eval adb_repair {}

proc adb_repair::one {objects description} {
    if {[llength $objects] != 1} {
        error "Expected exactly one $description; found [llength $objects]."
    }
    return [lindex $objects 0]
}

proc adb_repair::pin {name} {
    return [one [get_bd_pins -quiet $name] "pin $name"]
}

proc adb_repair::interface {name} {
    return [one [get_bd_intf_pins -quiet $name] "interface $name"]
}

# Connect only unconnected pins, or accept the already-correct connection.
# An unrelated existing net is an error, never silently disconnected.
proc adb_repair::connect_pins {source destination} {
    set source_net [get_bd_nets -quiet -of_objects $source]
    set destination_net [get_bd_nets -quiet -of_objects $destination]
    if {[llength $destination_net] != 0} {
        if {$source_net eq $destination_net} { return }
        error "$destination is connected to another net; inspect the design before changing it."
    }
    connect_bd_net $source $destination
}

proc adb_repair::connect_interfaces {source destination} {
    set source_net [get_bd_intf_nets -quiet -of_objects $source]
    set destination_net [get_bd_intf_nets -quiet -of_objects $destination]
    if {[llength $source_net] && [llength $destination_net]} {
        if {$source_net eq $destination_net} { return }
        error "Interfaces $source and $destination already belong to different nets."
    }
    foreach endpoint [list $source $destination] {
        set net [get_bd_intf_nets -quiet -of_objects $endpoint]
        if {[llength $net] &&
            [llength [get_bd_intf_pins -quiet -of_objects $net]] > 1} {
            error "Interface $endpoint already connects to another endpoint."
        }
    }
    connect_bd_intf_net $source $destination
}

proc adb_repair::check_property {object property expected} {
    set value [get_property $property $object]
    if {$value ne $expected} {
        error "$object $property must be $expected; found '$value'."
    }
}

proc adb_repair::mapped_segment {space slave} {
    set related [get_bd_addr_segs -quiet -of_objects $slave]
    set result {}
    foreach segment [get_bd_addr_segs -quiet -of_objects $space] {
        if {[lsearch -exact $related $segment] >= 0} { lappend result $segment }
    }
    return $result
}

proc adb_repair::check_or_map {space slave offset range} {
    set mapped [mapped_segment $space $slave]
    if {![llength $mapped]} {
        assign_bd_address -offset $offset -range $range \
            -target_address_space $space $slave
        set mapped [mapped_segment $space $slave]
    }
    set mapped [one $mapped "mapping for $slave in $space"]
    foreach {property expected} [list OFFSET $offset RANGE $range] {
        set actual [get_property $property $mapped]
        if {[expr {wide($actual)}] != [expr {wide($expected)}]} {
            error "$mapped $property is $actual; expected $expected. No address was overwritten."
        }
    }
}

proc adb_repair::external_pwm {pin_name port_name} {
    set output [pin $pin_name]
    set ports [get_bd_ports -quiet $port_name]
    if {![llength $ports]} {
        # Refuse to attach an external signal onto an unrelated existing net.
        if {[llength [get_bd_nets -quiet -of_objects $output]]} {
            error "$pin_name is already connected but $port_name does not exist."
        }
        set port [create_bd_port -dir O $port_name]
    } else {
        set port [one $ports "port $port_name"]
        check_property $port DIR O
    }
    connect_pins $output $port
}

proc adb_repair::apply {} {
    if {![llength [info commands get_bd_cells]]} {
        error "Run repair_bd.tcl in Vivado with design_ADB open. Vitis/XSCT cannot edit a BD."
    }
    if {[current_bd_design -quiet] ne "design_ADB"} {
        error "Open the design_ADB block design before sourcing this script."
    }
    set ps [one [get_bd_cells -quiet processing_system7_0] "PS7 cell"]
    set dma [one [get_bd_cells -quiet axi_dma_0] "DMA cell"]
    one [get_bd_cells -quiet my_fuzzy_ip_0] "fuzzy IP cell"
    set reset [one [get_bd_cells -quiet rst_ps7_0_50M] "reset controller"]
    one [get_bd_cells -quiet ps7_0_axi_periph] "CPU control interconnect"
    if {![string match "xilinx.com:ip:processing_system7:*" [get_property VLNV $ps]]} {
        error "processing_system7_0 is not a Zynq-7000 PS7 IP."
    }
    if {abs(double([get_property CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ $ps])-50.0)>0.0001} {
        error "FCLK_CLK0 must already be configured for 50 MHz."
    }
    check_property $dma CONFIG.c_include_sg 0
    check_property $dma CONFIG.c_include_mm2s 1
    check_property $dma CONFIG.c_include_s2mm 0
    check_property $dma CONFIG.c_m_axi_mm2s_data_width 32
    check_property $dma CONFIG.c_m_axis_mm2s_tdata_width 32
    check_property $reset CONFIG.C_EXT_RESET_HIGH 0
    # Check the current RTL interface before making any design changes.
    foreach name {
        processing_system7_0/FCLK_CLK0 processing_system7_0/FCLK_RESET0_N
        processing_system7_0/M_AXI_GP0_ACLK
        rst_ps7_0_50M/slowest_sync_clk rst_ps7_0_50M/ext_reset_in
        rst_ps7_0_50M/peripheral_aresetn
        axi_dma_0/s_axi_lite_aclk axi_dma_0/m_axi_mm2s_aclk axi_dma_0/axi_resetn
        my_fuzzy_ip_0/s00_axi_aclk my_fuzzy_ip_0/s00_axis_aclk
        my_fuzzy_ip_0/s00_axi_aresetn my_fuzzy_ip_0/s00_axis_aresetn
        my_fuzzy_ip_0/o_pwm_steer my_fuzzy_ip_0/o_pwm_speed
    } { pin $name }
    foreach name {
        axi_dma_0/M_AXI_MM2S axi_dma_0/M_AXIS_MM2S
        my_fuzzy_ip_0/S00_AXIS my_fuzzy_ip_0/S00_AXI axi_dma_0/S_AXI_LITE
    } { interface $name }
    set cpu_space [one [get_bd_addr_spaces -quiet processing_system7_0/Data] "CPU address space"]
    set dma_regs [one [get_bd_addr_segs -quiet axi_dma_0/S_AXI_LITE/Reg] "DMA registers"]
    set fuzzy_regs [one [get_bd_addr_segs -quiet -of_objects \
        [interface my_fuzzy_ip_0/S00_AXI]] "fuzzy register segment"]
    # Preserve firmware addresses; stop on conflicting existing assignments.
    check_or_map $cpu_space $dma_regs 0x40400000 0x00010000
    check_or_map $cpu_space $fuzzy_regs 0x43C00000 0x00010000

    # HP0 remains 64-bit; AXI Interconnect adapts the 32-bit DMA master.
    # This does not change the board's DDR timing, MIO, or DDR part settings.
    set_property -dict [list CONFIG.PCW_USE_S_AXI_HP0 1 \
        CONFIG.PCW_S_AXI_HP0_DATA_WIDTH 64] $ps
    set memory_ic [get_bd_cells -quiet axi_mem_intercon]
    if {![llength $memory_ic]} {
        set memory_ic [create_bd_cell -type ip \
            -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_mem_intercon]
        set_property -dict [list CONFIG.NUM_SI 1 CONFIG.NUM_MI 1] $memory_ic
    } else {
        set memory_ic [one $memory_ic "memory interconnect"]
        if {![string match "xilinx.com:ip:axi_interconnect:*" [get_property VLNV $memory_ic]]} {
            error "axi_mem_intercon is not an AXI Interconnect."
        }
        check_property $memory_ic CONFIG.NUM_SI 1
        check_property $memory_ic CONFIG.NUM_MI 1
    }
    connect_interfaces [interface axi_dma_0/M_AXI_MM2S] [interface axi_mem_intercon/S00_AXI]
    connect_interfaces [interface axi_mem_intercon/M00_AXI] [interface processing_system7_0/S_AXI_HP0]
    connect_interfaces [interface axi_dma_0/M_AXIS_MM2S] [interface my_fuzzy_ip_0/S00_AXIS]

    set clock [pin processing_system7_0/FCLK_CLK0]
    foreach name {
        processing_system7_0/M_AXI_GP0_ACLK processing_system7_0/S_AXI_HP0_ACLK
        rst_ps7_0_50M/slowest_sync_clk
        axi_dma_0/s_axi_lite_aclk axi_dma_0/m_axi_mm2s_aclk
        my_fuzzy_ip_0/s00_axi_aclk my_fuzzy_ip_0/s00_axis_aclk
        axi_mem_intercon/ACLK axi_mem_intercon/S00_ACLK axi_mem_intercon/M00_ACLK
    } { connect_pins $clock [pin $name] }
    connect_pins [pin processing_system7_0/FCLK_RESET0_N] [pin rst_ps7_0_50M/ext_reset_in]
    set resetn [pin rst_ps7_0_50M/peripheral_aresetn]
    foreach name {
        axi_dma_0/axi_resetn my_fuzzy_ip_0/s00_axi_aresetn my_fuzzy_ip_0/s00_axis_aresetn
        axi_mem_intercon/ARESETN axi_mem_intercon/S00_ARESETN axi_mem_intercon/M00_ARESETN
    } { connect_pins $resetn [pin $name] }

    set dma_space [one [get_bd_addr_spaces -quiet axi_dma_0/Data_MM2S] "DMA MM2S address space"]
    set ddr [one [get_bd_addr_segs -quiet processing_system7_0/S_AXI_HP0/HP0_DDR_LOWOCM] \
        "HP0 DDR segment"]
    # Let PS7's existing DDR aperture define the accessible range; do not guess
    # the DDR capacity or remap peripheral/control address spaces.
    if {![llength [mapped_segment $dma_space $ddr]]} {
        assign_bd_address -target_address_space $dma_space $ddr
    }
    one [mapped_segment $dma_space $ddr] "DMA-to-DDR address mapping"
    external_pwm my_fuzzy_ip_0/o_pwm_steer o_pwm_steer_0
    external_pwm my_fuzzy_ip_0/o_pwm_speed o_pwm_speed_0
    validate_bd_design
    save_bd_design
    puts "ADB_BD_REPAIR_VALIDATED: DDR path, common clock/reset, addresses and PWM ports."
    puts "Physical PWM pins still require a completed pwm_pins.xdc. No bitstream was generated."
}

# The switch is useful for Tcl syntax checks; it does not validate a Vivado design.
if {![info exists ::adb_repair_library_only] || !$::adb_repair_library_only} {
    adb_repair::apply
}
