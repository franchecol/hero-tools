package de1_s3_snitch_core_probe_pkg;
  typedef logic [31:0] addr_t;
  typedef logic [31:0] data_t;
  typedef logic [31:0] pa_t;

  typedef struct packed {
    logic [9:0] ppn1;
    logic [9:0] ppn0;
  } l0_pa_fields_t;

  typedef struct packed {
    l0_pa_fields_t          pa;
    snitch_pkg::pte_flags_t flags;
  } l0_pte_t;

  typedef struct packed {
    logic                 write;
    addr_t                addr;
    reqrsp_pkg::amo_op_e  amo;
    logic [1:0]           size;
    data_t                data;
    logic [3:0]           strb;
  } data_q_t;

  typedef struct packed {
    data_t data;
    logic  error;
  } data_p_t;

  typedef struct packed {
    logic    q_valid;
    data_q_t q;
    logic    p_ready;
  } dreq_t;

  typedef struct packed {
    logic    q_ready;
    logic    p_valid;
    data_p_t p;
  } drsp_t;

  typedef struct packed {
    logic [4:0]            id;
    logic [31:0]           data_op;
    logic [63:0]           data_arga;
    logic [63:0]           data_argb;
    addr_t                 data_argc;
    snitch_pkg::acc_addr_e addr;
  } acc_req_t;

  typedef struct packed {
    logic [4:0]  id;
    logic [63:0] data;
  } acc_resp_t;
endpackage

module de1_s3_snitch_core_probe (
    input  logic       CLOCK_50,
    input  logic [3:0] KEY,
    output logic [9:0] LEDR
);
    import snitch_pkg::*;
    import de1_s3_snitch_core_probe_pkg::*;

    logic rst_i;
    assign rst_i = ~KEY[0];

    interrupts_t irq;
    assign irq = '0;

    logic          flush_i_valid;
    logic [31:0]   inst_addr;
    logic          inst_cacheable;
    logic          inst_valid;
    dreq_t         data_req;
    drsp_t         data_rsp;
    acc_req_t      acc_req;
    acc_resp_t     acc_resp;
    logic          acc_qvalid;
    logic          acc_pready;
    logic [1:0]    ptw_valid;
    snitch_pkg::va_t [1:0] ptw_va;
    pa_t [1:0]     ptw_ppn;
    l0_pte_t [1:0] ptw_pte;
    fpnew_pkg::roundmode_e fpu_rnd_mode;
    fpnew_pkg::fmt_mode_t  fpu_fmt_mode;
    snitch_pkg::core_events_t core_events;
    logic barrier;

    assign data_rsp.q_ready = 1'b1;
    assign data_rsp.p_valid = 1'b0;
    assign data_rsp.p = '0;

    assign acc_resp = '0;
    assign ptw_pte = '0;

    snitch #(
        .BootAddr                 (32'h0000_0000),
        .AddrWidth                (32),
        .DataWidth                (32),
        .RVE                      (1'b1),
        .Xdma                     (1'b0),
        .Xssr                     (1'b0),
        .FP_EN                    (1'b0),
        .RVF                      (1'b0),
        .RVD                      (1'b0),
        .XF16                     (1'b0),
        .XF16ALT                  (1'b0),
        .XF8                      (1'b0),
        .XF8ALT                   (1'b0),
        .XDivSqrt                 (1'b0),
        .XFVEC                    (1'b0),
        .XFDOTP                   (1'b0),
        .XFAUX                    (1'b0),
        .FLEN                     (32),
        .VMSupport                (1'b0),
        .Xipu                     (1'b0),
        .dreq_t                   (dreq_t),
        .drsp_t                   (drsp_t),
        .acc_req_t                (acc_req_t),
        .acc_resp_t               (acc_resp_t),
        .pa_t                     (pa_t),
        .l0_pte_t                 (l0_pte_t),
        .NumIntOutstandingLoads   (1),
        .NumIntOutstandingMem     (1),
        .NumDTLBEntries           (1),
        .NumITLBEntries           (1),
        // snitch_pma_t is a packed 1664-bit struct in this upstream version.
        // Use an explicit vector so sv2v does not emit an assignment pattern
        // that Yosys cannot parse.
        .SnitchPMACfg             (1664'b0),
        .DebugSupport             (1'b0)
    ) i_snitch (
        .clk_i                    (CLOCK_50),
        .rst_i                    (rst_i),
        .hart_id_i                (32'd0),
        .irq_i                    (irq),
        .flush_i_valid_o          (flush_i_valid),
        .flush_i_ready_i          (1'b1),
        .inst_addr_o              (inst_addr),
        .inst_cacheable_o         (inst_cacheable),
        .inst_data_i              (32'h0000_0013),
        .inst_valid_o             (inst_valid),
        .inst_ready_i             (1'b1),
        .acc_qreq_o               (acc_req),
        .acc_qvalid_o             (acc_qvalid),
        .acc_qready_i             (1'b1),
        .acc_prsp_i               (acc_resp),
        .acc_pvalid_i             (1'b0),
        .acc_pready_o             (acc_pready),
        .data_req_o               (data_req),
        .data_rsp_i               (data_rsp),
        .ptw_valid_o              (ptw_valid),
        .ptw_ready_i              (2'b11),
        .ptw_va_o                 (ptw_va),
        .ptw_ppn_o                (ptw_ppn),
        .ptw_pte_i                (ptw_pte),
        .ptw_is_4mega_i           (2'b00),
        .fpu_rnd_mode_o           (fpu_rnd_mode),
        .fpu_fmt_mode_o           (fpu_fmt_mode),
        .fpu_status_i             ('0),
        .core_events_o            (core_events),
        .barrier_o                (barrier),
        .barrier_i                (1'b0)
    );

    assign LEDR[0] = inst_valid;
    assign LEDR[1] = data_req.q_valid;
    assign LEDR[2] = acc_qvalid;
    assign LEDR[3] = flush_i_valid;
    assign LEDR[4] = barrier;
    assign LEDR[5] = inst_cacheable;
    assign LEDR[6] = acc_pready;
    assign LEDR[7] = |ptw_valid;
    assign LEDR[8] = ~rst_i;
    assign LEDR[9] = 1'b1;
endmodule
