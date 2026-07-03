package require -exact qsys 12.0

set_module_property NAME s9_snitch_ctrl
set_module_property DISPLAY_NAME "S9 Snitch-Lite HPS Host Control"
set_module_property VERSION 1.0
set_module_property GROUP "DE1-SoC Bring-Up"
set_module_property AUTHOR "hero-tools local"
set_module_property DESCRIPTION "HPS-ready Avalon-MM control/status block around the Snitch-Lite RAM check."
set_module_property INSTANTIATE_IN_SYSTEM_MODULE true
set_module_property EDITABLE false

add_fileset quartus_synth QUARTUS_SYNTH fileset_quartus_synth
add_fileset sim_verilog SIM_VERILOG fileset_sim_verilog

proc wrapper_text {output_name} {
    return [format {module %s (
    input  wire        clk,
    input  wire        reset,

    input  wire [3:0]  avs_address,
    input  wire        avs_read,
    output wire [31:0] avs_readdata,
    input  wire        avs_write,
    input  wire [31:0] avs_writedata,
    input  wire [3:0]  avs_byteenable,
    output wire        avs_waitrequest,

    output wire [9:0]  ledr
);

    s8_snitch_host_ctrl_core u_core (
        .clk             (clk),
        .reset           (reset),
        .avs_address     (avs_address),
        .avs_read        (avs_read),
        .avs_readdata    (avs_readdata),
        .avs_write       (avs_write),
        .avs_writedata   (avs_writedata),
        .avs_byteenable  (avs_byteenable),
        .avs_waitrequest (avs_waitrequest),
        .ledr            (ledr)
    );

endmodule
} $output_name]
}

proc fileset_quartus_synth {output_name} {
    add_fileset_file $output_name.v VERILOG TEXT [wrapper_text $output_name] TOP_LEVEL_FILE
    add_fileset_file generated/snitch_host_ctrl_core.v VERILOG PATH ../../generated/snitch_host_ctrl_core.v
}

proc fileset_sim_verilog {output_name} {
    add_fileset_file $output_name.v VERILOG TEXT [wrapper_text $output_name] TOP_LEVEL_FILE
    add_fileset_file generated/snitch_host_ctrl_core.v VERILOG PATH ../../generated/snitch_host_ctrl_core.v
}

add_interface clk clock end
set_interface_property clk clockRate 0
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
set_interface_property s1 burstOnBurstBoundariesOnly false
set_interface_property s1 explicitAddressSpan 64
set_interface_property s1 holdTime 0
set_interface_property s1 isMemoryDevice false
set_interface_property s1 isNonVolatileStorage false
set_interface_property s1 linewrapBursts false
set_interface_property s1 maximumPendingReadTransactions 0
set_interface_property s1 printableDevice false
set_interface_property s1 readLatency 0
set_interface_property s1 readWaitTime 0
set_interface_property s1 setupTime 0
set_interface_property s1 timingUnits Cycles
set_interface_property s1 writeWaitTime 0

add_interface_port s1 avs_address address Input 4
add_interface_port s1 avs_read read Input 1
add_interface_port s1 avs_readdata readdata Output 32
add_interface_port s1 avs_write write Input 1
add_interface_port s1 avs_writedata writedata Input 32
add_interface_port s1 avs_byteenable byteenable Input 4
add_interface_port s1 avs_waitrequest waitrequest Output 1

add_interface ledr conduit end
add_interface_port ledr ledr export Output 10
