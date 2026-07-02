package require -exact qsys 12.0

set_module_property NAME d2_mmio_regs
set_module_property DISPLAY_NAME "D2 MMIO Register Accelerator"
set_module_property VERSION 1.0
set_module_property GROUP "DE1-SoC Bring-Up"
set_module_property AUTHOR "hero-tools local"
set_module_property DESCRIPTION "Small Avalon-MM register block used by D2 JTAG/HPS MMIO tests."
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

    output wire [9:0]  ledr,
    output wire [6:0]  hex0,
    output wire [6:0]  hex1,
    output wire [6:0]  hex2,
    output wire [6:0]  hex3,
    output wire [6:0]  hex4,
    output wire [6:0]  hex5
);

    d2_mmio_regs u_regs (
        .clk             (clk),
        .reset           (reset),
        .avs_address     (avs_address),
        .avs_read        (avs_read),
        .avs_readdata    (avs_readdata),
        .avs_write       (avs_write),
        .avs_writedata   (avs_writedata),
        .avs_byteenable  (avs_byteenable),
        .avs_waitrequest (avs_waitrequest),
        .ledr            (ledr),
        .hex0            (hex0),
        .hex1            (hex1),
        .hex2            (hex2),
        .hex3            (hex3),
        .hex4            (hex4),
        .hex5            (hex5)
    );

endmodule
} $output_name]
}

proc fileset_quartus_synth {output_name} {
    add_fileset_file $output_name.v VERILOG TEXT [wrapper_text $output_name] TOP_LEVEL_FILE
    add_fileset_file rtl/d2_mmio_regs.v VERILOG PATH rtl/d2_mmio_regs.v
}

proc fileset_sim_verilog {output_name} {
    add_fileset_file $output_name.v VERILOG TEXT [wrapper_text $output_name] TOP_LEVEL_FILE
    add_fileset_file rtl/d2_mmio_regs.v VERILOG PATH rtl/d2_mmio_regs.v
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

add_interface hex0 conduit end
add_interface_port hex0 hex0 export Output 7

add_interface hex1 conduit end
add_interface_port hex1 hex1 export Output 7

add_interface hex2 conduit end
add_interface_port hex2 hex2 export Output 7

add_interface hex3 conduit end
add_interface_port hex3 hex3 export Output 7

add_interface hex4 conduit end
add_interface_port hex4 hex4 export Output 7

add_interface hex5 conduit end
add_interface_port hex5 hex5 export Output 7
