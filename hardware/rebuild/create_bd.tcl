# Vivado 2024.1 batch entry point; no board connection is required.
# vivado -mode batch -source hardware/rebuild/create_bd.tcl \
#   -tclargs build/ps7_config.tcl build/adb
# Generates a project and BD, not a verified bitstream. See README.md.
namespace eval adb_create {
    variable script_dir [file dirname [file normalize [info script]]]
}

proc adb_create::main {arguments} {
    variable script_dir
    if {[llength $arguments] != 2} {
        error "Usage: create_bd.tcl <extracted_ps7_config.tcl> <new_output_directory>"
    }
    if {![llength [info commands create_bd_design]]} {
        error "Use full Vivado 2024.1 with Zynq-7000 device support, not Vitis/XSCT."
    }
    if {![string match "2024.1*" [version -short]]} {
        error "This reconstruction targets Vivado 2024.1. Review IP versions before porting it."
    }
    if {[llength [get_projects -quiet]]} {
        error "Start a fresh Vivado session; an existing project will not be closed or changed."
    }
    lassign $arguments config_file output_dir
    set config_file [file normalize $config_file]
    set output_dir [file normalize $output_dir]
    if {![file isfile $config_file]} { error "Missing extracted PS7 configuration: $config_file" }
    if {[file exists $output_dir]} { error "Output directory already exists: $output_dir" }
    source $config_file
    if {![info exists adb_ps7_config] || [dict size $adb_ps7_config] == 0} {
        error "Run extract_ps7.py first; the input must define adb_ps7_config."
    }
    foreach {key expected} {
        CONFIG.PCW_UIPARAM_DDR_ENABLE 1
        CONFIG.PCW_UIPARAM_DDR_BUS_WIDTH {32 Bit}
        CONFIG.PCW_USE_M_AXI_GP0 1
        CONFIG.PCW_EN_CLK0_PORT 1
        CONFIG.PCW_EN_RST0_PORT 1
    } {
        if {![dict exists $adb_ps7_config $key] || [dict get $adb_ps7_config $key] ne $expected} {
            error "Unexpected source PS7 setting: $key must be '$expected'."
        }
    }
    if {abs(double([dict get $adb_ps7_config CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ])-50.0)>0.0001} {
        error "Source FCLK0 must be 50 MHz for the RTL PWM timing."
    }
    set repo_root [file normalize [file join $script_dir ../..]]
    file mkdir $output_dir
    uplevel #0 [list source [file join $script_dir package_fuzzy_ip.tcl]]
    set ip_root [adb_package_fuzzy_ip $repo_root [file join $output_dir packaged_ip]]
    create_project adb_rebuilt [file join $output_dir project] -part xc7z020clg400-1
    set_property target_language Verilog [current_project]
    set_property ip_repo_paths [list $ip_root] [current_project]
    update_ip_catalog
    create_bd_design design_ADB

    set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0]
    set available [list_property $ps]
    dict for {key value} $adb_ps7_config {
        if {[lsearch -exact $available $key] < 0} {
            error "PS7 does not support extracted property $key; no setting was silently dropped."
        }
    }
    set_property -dict $adb_ps7_config $ps
    # HP0 is restored by repair_bd.tcl. Keep all source board DDR/MIO settings.
    foreach name {DDR FIXED_IO} {
        set interface [get_bd_intf_pins processing_system7_0/$name]
        make_bd_intf_pins_external $interface
        set ports [get_bd_intf_ports -of_objects [get_bd_intf_nets -of_objects $interface]]
        if {[llength $ports] != 1} { error "Expected one external PS interface for $name" }
        set_property name $name $ports
    }

    set dma [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_0]
    set_property -dict [list CONFIG.c_include_sg 0 CONFIG.c_include_mm2s 1 \
        CONFIG.c_include_s2mm 0 CONFIG.c_m_axi_mm2s_data_width 32 \
        CONFIG.c_m_axis_mm2s_tdata_width 32 CONFIG.c_addr_width 32 \
        CONFIG.c_sg_length_width 23] $dma
    create_bd_cell -type ip -vlnv user.org:user:my_fuzzy_ip:1.0 my_fuzzy_ip_0
    set control [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 ps7_0_axi_periph]
    set_property -dict [list CONFIG.NUM_SI 1 CONFIG.NUM_MI 2] $control
    set reset [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ps7_0_50M]
    set_property -dict [list CONFIG.C_EXT_RESET_HIGH 0 CONFIG.C_AUX_RESET_HIGH 1] $reset
    set high [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_one]
    set_property -dict [list CONFIG.CONST_WIDTH 1 CONFIG.CONST_VAL 1] $high
    set low [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_zero]
    set_property -dict [list CONFIG.CONST_WIDTH 1 CONFIG.CONST_VAL 0] $low
    connect_bd_net [get_bd_pins const_one/dout] [get_bd_pins rst_ps7_0_50M/dcm_locked]
    connect_bd_net [get_bd_pins const_zero/dout] \
        [get_bd_pins rst_ps7_0_50M/aux_reset_in] [get_bd_pins rst_ps7_0_50M/mb_debug_sys_rst]
    # The saved USB0/MIO setup is retained; no external power-fault signal was
    # wired in the saved design. Explicitly deassert that optional input.
    set usb_fault [get_bd_pins -quiet processing_system7_0/USB0_VBUS_PWRFAULT]
    if {[llength $usb_fault]} { connect_bd_net [get_bd_pins const_zero/dout] $usb_fault }
    connect_bd_intf_net [get_bd_intf_pins processing_system7_0/M_AXI_GP0] \
        [get_bd_intf_pins ps7_0_axi_periph/S00_AXI]
    connect_bd_intf_net [get_bd_intf_pins ps7_0_axi_periph/M00_AXI] \
        [get_bd_intf_pins axi_dma_0/S_AXI_LITE]
    connect_bd_intf_net [get_bd_intf_pins ps7_0_axi_periph/M01_AXI] \
        [get_bd_intf_pins my_fuzzy_ip_0/S00_AXI]
    foreach name {ACLK S00_ACLK M00_ACLK M01_ACLK} {
        connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
            [get_bd_pins ps7_0_axi_periph/$name]
    }
    foreach name {ARESETN S00_ARESETN M00_ARESETN M01_ARESETN} {
        connect_bd_net [get_bd_pins rst_ps7_0_50M/peripheral_aresetn] \
            [get_bd_pins ps7_0_axi_periph/$name]
    }
    # Supply the remaining DDR/stream/PWM, clock/reset and fixed address wiring.
    uplevel #0 [list source [file join $script_dir repair_bd.tcl]]
    set bd [get_files */design_ADB.bd]
    generate_target all $bd
    set wrappers [make_wrapper -files $bd -top]
    add_files -norecurse $wrappers
    set_property top design_ADB_wrapper [current_fileset]
    update_compile_order -fileset sources_1
    puts "ADB_PROJECT_CREATED: [file join $output_dir project adb_rebuilt.xpr]"
    puts "No synthesis, implementation, pin assignment or bitstream generation was run."
}

if {![info exists ::adb_create_library_only] || !$::adb_create_library_only} {
    adb_create::main $argv
}
