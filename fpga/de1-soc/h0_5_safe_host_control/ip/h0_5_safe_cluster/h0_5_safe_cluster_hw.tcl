package require -exact qsys 12.0

set_module_property NAME h0_5_safe_cluster
set_module_property DISPLAY_NAME "H0.5 Safe Upstream Snitch Cluster"
set_module_property VERSION 1.0
set_module_property GROUP "DE1-SoC Upstream Snitch"
set_module_property AUTHOR "hero-tools local"
set_module_property DESCRIPTION "Reset-held control plane and forwarded Avalon bridge for the upstream cluster."
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
    output wire        avs_waitrequest,
    output wire        irq
);
    wire        cluster_hold_reset;
    wire [15:0] cluster_address;
    wire        cluster_read;
    wire [31:0] cluster_readdata;
    wire        cluster_write;
    wire [31:0] cluster_writedata;
    wire [3:0]  cluster_byteenable;
    wire        cluster_waitrequest;
    wire        boot_fetch_seen;
    wire        boot_result_valid;
    wire [31:0] boot_result;
    wire        boot_host_write;
    wire [9:0]  boot_host_word_addr;
    wire [31:0] boot_host_wdata;
    wire [3:0]  boot_host_be;
    wire        data_host_write;
    wire [9:0]  data_host_word_addr;
    wire [31:0] data_host_wdata;
    wire [3:0]  data_host_be;
    wire [31:0] data_host_rdata;
    wire        job_active;
    wire        result_ack;

    safe_host_control u_control (
        .clk_i                    (clk),
        .rst_i                    (reset),
        .pll_locked_i             (~reset),
        .boot_fetch_seen_i        (boot_fetch_seen),
        .boot_result_valid_i      (boot_result_valid),
        .boot_result_i            (boot_result),
        .avs_address_i            (avs_address),
        .avs_read_i               (avs_read),
        .avs_readdata_o           (avs_readdata),
        .avs_write_i              (avs_write),
        .avs_writedata_i          (avs_writedata),
        .avs_byteenable_i         (avs_byteenable),
        .avs_waitrequest_o        (avs_waitrequest),
        .cluster_hold_reset_o     (cluster_hold_reset),
        .cluster_address_o        (cluster_address),
        .cluster_read_o           (cluster_read),
        .cluster_readdata_i       (cluster_readdata),
        .cluster_write_o          (cluster_write),
        .cluster_writedata_o      (cluster_writedata),
        .cluster_byteenable_o     (cluster_byteenable),
        .cluster_waitrequest_i    (cluster_waitrequest),
        .boot_host_write_o        (boot_host_write),
        .boot_host_word_addr_o    (boot_host_word_addr),
        .boot_host_wdata_o        (boot_host_wdata),
        .boot_host_be_o           (boot_host_be),
        .data_host_write_o        (data_host_write),
        .data_host_word_addr_o    (data_host_word_addr),
        .data_host_wdata_o        (data_host_wdata),
        .data_host_be_o           (data_host_be),
        .data_host_rdata_i        (data_host_rdata),
        .job_active_o             (job_active),
        .result_ack_o             (result_ack),
        .irq_o                    (irq)
    );

    h0_2_cluster_component_core u_cluster (
        .clk                  (clk),
        .reset                (reset),
        .cluster_hold_reset   (cluster_hold_reset),
        .avs_address          (cluster_address),
        .avs_read             (cluster_read),
        .avs_readdata         (cluster_readdata),
        .avs_write            (cluster_write),
        .avs_writedata        (cluster_writedata),
        .avs_byteenable       (cluster_byteenable),
        .avs_waitrequest      (cluster_waitrequest),
        .boot_host_write      (boot_host_write),
        .boot_host_word_addr  (boot_host_word_addr),
        .boot_host_wdata      (boot_host_wdata),
        .boot_host_be         (boot_host_be),
        .data_host_write      (data_host_write),
        .data_host_word_addr  (data_host_word_addr),
        .data_host_wdata      (data_host_wdata),
        .data_host_be         (data_host_be),
        .data_host_rdata      (data_host_rdata),
        .job_active           (job_active),
        .result_ack           (result_ack),
        .boot_fetch_seen      (boot_fetch_seen),
        .boot_result_valid    (boot_result_valid),
        .boot_result          (boot_result)
    );
endmodule
} $output_name]
}

proc fileset_quartus_synth {output_name} {
    add_fileset_file $output_name.sv SYSTEM_VERILOG TEXT [wrapper_text $output_name] TOP_LEVEL_FILE
    add_fileset_file safe_host_control.sv SYSTEM_VERILOG PATH ../../rtl/safe_host_control.sv
    add_fileset_file h0_2_cluster_component.sv SYSTEM_VERILOG PATH ../../../h0_2_avalon_axi_bridge/rtl/h0_2_cluster_component.sv
    add_fileset_file avalon_to_narrow_axi.sv SYSTEM_VERILOG PATH ../../../h0_2_avalon_axi_bridge/rtl/avalon_to_narrow_axi.sv
    add_fileset_file upstream_cluster_shell.sv SYSTEM_VERILOG PATH ../../../h0_1_upstream_cluster_shell/rtl/upstream_cluster_shell.sv
    add_fileset_file axi_boot_ram.sv SYSTEM_VERILOG PATH ../../../h2_host_program_memory/rtl/axi_boot_ram.sv
    add_fileset_file axi_shared_data_ram.sv SYSTEM_VERILOG PATH ../../../h3_shared_data_memory/rtl/axi_shared_data_ram.sv
    add_fileset_file cyclone_sram_primitive.sv SYSTEM_VERILOG PATH ../../../u5_1_sram_retention/rtl/cyclone_sram_primitive.sv
    add_fileset_file de1_u4_cluster_quartus.v VERILOG PATH ../../../u4_cyclone_memory_boundary/generated/de1_u4_cluster_quartus.v
}

add_interface clk clock end
set_interface_property clk clockRate 15000000
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

add_interface irq interrupt sender
set_interface_property irq associatedAddressablePoint s1
set_interface_property irq associatedClock clk
set_interface_property irq associatedReset reset
add_interface_port irq irq irq Output 1
