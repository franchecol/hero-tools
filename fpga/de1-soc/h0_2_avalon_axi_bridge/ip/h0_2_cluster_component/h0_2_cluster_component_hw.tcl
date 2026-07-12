package require -exact qsys 12.0

set_module_property NAME h0_2_cluster_component
set_module_property DISPLAY_NAME "H0.2 Upstream Snitch Cluster Bridge"
set_module_property VERSION 1.0
set_module_property GROUP "DE1-SoC Upstream Snitch"
set_module_property AUTHOR "hero-tools local"
set_module_property DESCRIPTION "32-bit Avalon bridge to the SRAM-correct upstream Snitch narrow AXI host port."
set_module_property INSTANTIATE_IN_SYSTEM_MODULE true
set_module_property EDITABLE false

add_fileset quartus_synth QUARTUS_SYNTH fileset_quartus_synth

proc wrapper_text {output_name} {
    return [format {module %s (
    input  wire        clk,
    input  wire        reset,
    input  wire [15:0] avs_address,
    input  wire        avs_read,
    output wire [31:0] avs_readdata,
    input  wire        avs_write,
    input  wire [31:0] avs_writedata,
    input  wire [3:0]  avs_byteenable,
    output wire        avs_waitrequest
);
    wire boot_fetch_seen_unused;
    wire boot_result_valid_unused;
    wire [31:0] boot_result_unused;
    h0_2_cluster_component_core u_core (
        .cluster_hold_reset (1'b0),
        .boot_fetch_seen    (boot_fetch_seen_unused),
        .boot_result_valid  (boot_result_valid_unused),
        .boot_result        (boot_result_unused),
        .*
    );
endmodule
} $output_name]
}

proc fileset_quartus_synth {output_name} {
    add_fileset_file $output_name.sv SYSTEM_VERILOG TEXT [wrapper_text $output_name] TOP_LEVEL_FILE
    add_fileset_file h0_2_cluster_component.sv SYSTEM_VERILOG PATH ../../rtl/h0_2_cluster_component.sv
    add_fileset_file avalon_to_narrow_axi.sv SYSTEM_VERILOG PATH ../../rtl/avalon_to_narrow_axi.sv
    add_fileset_file upstream_cluster_shell.sv SYSTEM_VERILOG PATH ../../../h0_1_upstream_cluster_shell/rtl/upstream_cluster_shell.sv
    add_fileset_file axi_boot_rom.sv SYSTEM_VERILOG PATH ../../../h0_6_axi_boot_rom/rtl/axi_boot_rom.sv
    add_fileset_file axi_signature_sink.sv SYSTEM_VERILOG PATH ../../../h0_7_observable_boot/rtl/axi_signature_sink.sv
    add_fileset_file cyclone_sram_primitive.sv SYSTEM_VERILOG PATH ../../../u5_1_sram_retention/rtl/cyclone_sram_primitive.sv
    add_fileset_file de1_u4_cluster_quartus.v VERILOG PATH ../../../u4_cyclone_memory_boundary/generated/de1_u4_cluster_quartus.v
}

add_interface clk clock end
set_interface_property clk clockRate 20000000
add_interface_port clk clk clk Input 1

add_interface reset reset end
set_interface_property reset associatedClock clk
set_interface_property reset synchronousEdges DEASSERT
add_interface_port reset reset reset Input 1

add_interface s1 avalon end
set_interface_property s1 addressAlignment NATIVE
set_interface_property s1 addressUnits WORDS
set_interface_property s1 associatedClock clk
set_interface_property s1 associatedReset reset
set_interface_property s1 explicitAddressSpan 262144
set_interface_property s1 maximumPendingReadTransactions 0
set_interface_property s1 readLatency 0
set_interface_property s1 timingUnits Cycles

add_interface_port s1 avs_address address Input 16
add_interface_port s1 avs_read read Input 1
add_interface_port s1 avs_readdata readdata Output 32
add_interface_port s1 avs_write write Input 1
add_interface_port s1 avs_writedata writedata Input 32
add_interface_port s1 avs_byteenable byteenable Input 4
add_interface_port s1 avs_waitrequest waitrequest Output 1
