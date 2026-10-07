# Vivado helper. Source this file, then call:
#   adb_package_fuzzy_ip <repository_root> <fresh_output_directory>
# Returns the directory containing user.org:user:my_fuzzy_ip:1.0.
# A real Divider Generator XCI is included; no testbench model is packaged.
namespace eval adb_package {}

proc adb_package::bus_parameter {interface name value} {
    set parameter [ipx::add_bus_parameter $name $interface]
    set_property value $value $parameter
}

proc adb_package::interface {core name bus abstraction port_pairs} {
    set interface [ipx::add_bus_interface $name $core]
    set_property interface_mode slave $interface
    set_property bus_type_vlnv $bus $interface
    set_property abstraction_type_vlnv $abstraction $interface
    foreach {logical physical} $port_pairs {
        if {[llength [ipx::get_ports $physical -of_objects $core]] != 1} {
            error "Packaged top is missing port $physical for $name/$logical."
        }
        set mapping [ipx::add_port_map $logical $interface]
        set_property physical_name $physical $mapping
    }
    return $interface
}

proc adb_package::clock_and_reset {core clock_name reset_name associated_bus} {
    set clock [interface $core $clock_name xilinx.com:signal:clock:1.0 \
        xilinx.com:signal:clock_rtl:1.0 [list CLK $clock_name]]
    bus_parameter $clock FREQ_HZ 50000000
    bus_parameter $clock ASSOCIATED_BUSIF $associated_bus
    bus_parameter $clock ASSOCIATED_RESET $reset_name
    set reset [interface $core $reset_name xilinx.com:signal:reset:1.0 \
        xilinx.com:signal:reset_rtl:1.0 [list RST $reset_name]]
    bus_parameter $reset POLARITY ACTIVE_LOW
}

proc adb_package_fuzzy_ip {repository_root output_directory} {
    if {![llength [info commands ::ipx::package_project]] ||
        ![llength [info commands create_ip]]} {
        error "IP packaging requires the full Vivado Design Suite; Vitis/XSCT is insufficient."
    }
    if {[llength [get_projects -quiet]]} {
        error "Close the active Vivado project before packaging the fuzzy IP."
    }
    set repository_root [file normalize $repository_root]
    set output_directory [file normalize $output_directory]
    set rtl_directory [file join $repository_root fpga rtl]
    set expected {
        Adder_Tree_Generic.v AMU.v Defuzzifier.v Divider_Wrapper.v
        Fuzzifier.v Fuzzy_Control_Unit.v Inference_Engine.v Kalman_Filter.v
        KM_Core.v MAC_Core.v Max_Tree_Generic.v MF_Core.v MM_Core.v
        my_fuzzy_ip_slave_lite_v1_0_S00_AXI.v
        my_fuzzy_ip_slave_stream_v1_0_S00_AXIS.v my_fuzzy_ip_v1_0.v
        PWM_Generator.v Rule_Memory.v
    }
    set sources {}
    foreach name $expected {
        set path [file join $rtl_directory $name]
        if {![file isfile $path]} { error "Required RTL file is missing: $path" }
        lappend sources $path
    }
    # A non-recursive allowlist prevents the simulation div_gen_0 model from
    # shadowing the generated IP, even if more files appear in testbench/.
    set actual [glob -nocomplain -tails -directory $rtl_directory *.v]
    if {[lsort $actual] ne [lsort $expected]} {
        error "The top-level RTL file set has changed. Review the 18-file synthesis allowlist."
    }
    set project_directory [file join $output_directory packaging_project]
    set ip_directory [file join $output_directory my_fuzzy_ip]
    foreach directory [list $project_directory $ip_directory] {
        if {[file exists $directory]} {
            error "Refusing to overwrite $directory; choose a fresh output directory."
        }
    }
    file mkdir $output_directory
    create_project adb_fuzzy_package $project_directory -part xc7z020clg400-1
    set_property target_language Verilog [current_project]
    add_files -norecurse $sources
    set_property top my_fuzzy_ip_v1_0 [get_filesets sources_1]

    create_ip -name div_gen -vendor xilinx.com -library ip -version 5.1 \
        -module_name div_gen_0
    set divider [get_ips div_gen_0]
    set_property -dict [list \
        CONFIG.algorithm_type Radix2 \
        CONFIG.dividend_and_quotient_width 32 \
        CONFIG.divisor_width 16 \
        CONFIG.remainder_type Remainder \
        CONFIG.fractional_width 16 \
        CONFIG.operand_sign Signed \
        CONFIG.clocks_per_division 1 \
        CONFIG.FlowControl NonBlocking \
        CONFIG.latency_configuration Automatic \
        CONFIG.divide_by_zero_detect false \
        CONFIG.aclken false \
        CONFIG.aresetn false] $divider
    generate_target all $divider
    set divider_latency [get_property CONFIG.latency $divider]
    if {$divider_latency ne "36"} {
        error "Automatic divider latency is $divider_latency; the RTL contract requires 36 cycles."
    }
    # Remainder mode with signed 32/16-bit operands produces the byte-aligned
    # 48-bit {quotient[31:0], remainder[15:0]} used by Divider_Wrapper.
    update_compile_order -fileset sources_1
    ipx::package_project -root_dir $ip_directory -vendor user.org -library user \
        -taxonomy /UserIP -import_files -set_current true
    set core [ipx::current_core]
    set_property name my_fuzzy_ip $core
    set_property version 1.0 $core
    set_property display_name {ADB fuzzy controller} $core
    set_property description {AXI-Lite configuration, three-word AXI stream input and two PWM outputs} $core
    set_property core_revision 1 $core

    # Rebuild interface metadata explicitly so port/interface casing and
    # inference heuristics do not change the contract consumed by repair_bd.tcl.
    foreach inferred [ipx::get_bus_interfaces -of_objects $core] {
        ipx::remove_bus_interface [get_property NAME $inferred] $core
    }
    foreach inferred [ipx::get_memory_maps -of_objects $core] {
        ipx::remove_memory_map [get_property NAME $inferred] $core
    }
    set control [adb_package::interface $core S00_AXI \
        xilinx.com:interface:aximm:1.0 xilinx.com:interface:aximm_rtl:1.0 {
            AWADDR s00_axi_awaddr AWPROT s00_axi_awprot
            AWVALID s00_axi_awvalid AWREADY s00_axi_awready
            WDATA s00_axi_wdata WSTRB s00_axi_wstrb
            WVALID s00_axi_wvalid WREADY s00_axi_wready
            BRESP s00_axi_bresp BVALID s00_axi_bvalid BREADY s00_axi_bready
            ARADDR s00_axi_araddr ARPROT s00_axi_arprot
            ARVALID s00_axi_arvalid ARREADY s00_axi_arready
            RDATA s00_axi_rdata RRESP s00_axi_rresp
            RVALID s00_axi_rvalid RREADY s00_axi_rready
        }]
    foreach {name value} {
        PROTOCOL AXI4LITE DATA_WIDTH 32 ADDR_WIDTH 12 READ_WRITE_MODE READ_WRITE
    } { adb_package::bus_parameter $control $name $value }
    set memory_map [ipx::add_memory_map S00_AXI $core]
    set registers [ipx::add_address_block S00_AXI_reg $memory_map]
    set_property base_address 0 $registers
    set_property range 4096 $registers
    set_property width 32 $registers
    set_property usage register $registers
    set_property memory_map_ref S00_AXI $control

    set stream [adb_package::interface $core S00_AXIS \
        xilinx.com:interface:axis:1.0 xilinx.com:interface:axis_rtl:1.0 {
            TDATA s00_axis_tdata TSTRB s00_axis_tstrb TLAST s00_axis_tlast
            TVALID s00_axis_tvalid TREADY s00_axis_tready
        }]
    foreach {name value} {
        TDATA_NUM_BYTES 4 HAS_TSTRB 1 HAS_TKEEP 0 HAS_TLAST 1 HAS_TREADY 1
        TDEST_WIDTH 0 TID_WIDTH 0 TUSER_WIDTH 0
    } { adb_package::bus_parameter $stream $name $value }
    adb_package::clock_and_reset $core s00_axi_aclk s00_axi_aresetn S00_AXI
    adb_package::clock_and_reset $core s00_axis_aclk s00_axis_aresetn S00_AXIS

    # A packaged XCI is needed to regenerate the real arithmetic IP in the
    # consuming project; merely packaging a stub would leave a black box.
    set divider_files {}
    foreach group [ipx::get_file_groups -of_objects $core] {
        foreach packaged_file [ipx::get_files -of_objects $group] {
            set name [get_property NAME $packaged_file]
            if {[string match *div_gen_0.xci $name]} { lappend divider_files $name }
            if {[string match *div_gen_0_model.v $name] ||
                [string match *tb_regression.sv $name]} {
                error "A simulation-only file entered the packaged synthesis IP: $name"
            }
        }
    }
    if {![llength $divider_files]} {
        error "IP packager did not include div_gen_0.xci; inspect the open packaging project."
    }
    foreach port {o_pwm_steer o_pwm_speed} {
        if {[llength [ipx::get_ports $port -of_objects $core]] != 1} {
            error "The packaged IP is missing PWM output $port."
        }
    }
    ipx::create_xgui_files $core
    ipx::check_integrity $core
    ipx::update_checksums $core
    ipx::save_core $core
    if {![file isfile [file join $ip_directory component.xml]]} {
        error "Packaging did not write component.xml."
    }
    ipx::unload_core $core
    close_project
    puts "ADB_FUZZY_IP_PACKAGED: $ip_directory"
    return $ip_directory
}
