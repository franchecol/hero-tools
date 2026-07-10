package snitch_genus_mem_probe_pkg;
  typedef logic [32:0] addr_t;
  typedef logic [31:0] data_t;
  typedef logic [32:0] pa_t;

  typedef struct packed {
    logic [9:0] ppn1;
    logic [9:0] ppn0;
  } l0_pa_fields_t;

  typedef struct packed {
    l0_pa_fields_t          pa;
    snitch_pkg::pte_flags_t flags;
  } l0_pte_t;

  typedef struct packed {
    logic                write;
    addr_t               addr;
    reqrsp_pkg::amo_op_e amo;
    logic [1:0]          size;
    data_t               data;
    logic [3:0]          strb;
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

module snitch_genus_mem_probe (
    input  logic        clk_i,
    input  logic        rst_i,
    input  logic [31:0] hart_id_i,
    input  logic [31:0] inst_data_i,
    input  logic        inst_ready_i,
    output logic [32:0] inst_addr_o,
    output logic        inst_valid_o,
    output logic        data_q_valid_o,
    input  logic        data_q_ready_i,
    output logic        data_q_write_o,
    output logic [32:0] data_q_addr_o,
    output logic [31:0] data_q_data_o,
    output logic [3:0]  data_q_strb_o,
    input  logic        data_p_valid_i,
    output logic        data_p_ready_o,
    input  logic [31:0] data_p_data_i,
    input  logic        data_p_error_i,
    output logic        barrier_o
);
  import snitch_pkg::*;
  import snitch_genus_mem_probe_pkg::*;

  interrupts_t irq;
  dreq_t data_req;
  drsp_t data_rsp;
  acc_req_t acc_req;
  acc_resp_t acc_resp;
  logic flush_i_valid;
  logic inst_cacheable;
  logic acc_qvalid;
  logic acc_pready;
  logic [1:0] ptw_valid;
  snitch_pkg::va_t [1:0] ptw_va;
  pa_t [1:0] ptw_ppn;
  l0_pte_t [1:0] ptw_pte;
  fpnew_pkg::roundmode_e fpu_rnd_mode;
  fpnew_pkg::fmt_mode_t fpu_fmt_mode;
  snitch_pkg::core_events_t core_events;

  assign irq = '0;
  assign data_rsp.q_ready = data_q_ready_i;
  assign data_rsp.p_valid = data_p_valid_i;
  assign data_rsp.p.data = data_p_data_i;
  assign data_rsp.p.error = data_p_error_i;
  assign acc_resp = '0;
  assign ptw_pte = '0;

  assign data_q_valid_o = data_req.q_valid;
  assign data_q_write_o = data_req.q.write;
  assign data_q_addr_o = data_req.q.addr;
  assign data_q_data_o = data_req.q.data;
  assign data_q_strb_o = data_req.q.strb;
  assign data_p_ready_o = data_req.p_ready;

  snitch #(
      .BootAddr               (32'h0000_0000),
      .AddrWidth              (33),
      .DataWidth              (32),
      .RVE                    (1'b1),
      .Xdma                   (1'b0),
      .Xssr                   (1'b0),
      .FP_EN                  (1'b0),
      .RVF                    (1'b0),
      .RVD                    (1'b0),
      .XF16                   (1'b0),
      .XF16ALT                (1'b0),
      .XF8                    (1'b0),
      .XF8ALT                 (1'b0),
      .XDivSqrt               (1'b0),
      .XFVEC                  (1'b0),
      .XFDOTP                 (1'b0),
      .XFAUX                  (1'b0),
      .FLEN                   (32),
      .VMSupport              (1'b0),
      .Xipu                   (1'b0),
      .dreq_t                 (dreq_t),
      .drsp_t                 (drsp_t),
      .acc_req_t              (acc_req_t),
      .acc_resp_t             (acc_resp_t),
      .pa_t                   (pa_t),
      .l0_pte_t               (l0_pte_t),
      .NumIntOutstandingLoads (1),
      .NumIntOutstandingMem   (1),
      .NumDTLBEntries         (1),
      .NumITLBEntries         (1),
      .SnitchPMACfg           (1664'b0),
      .DebugSupport           (1'b0)
  ) i_snitch (
      .clk_i,
      .rst_i,
      .hart_id_i,
      .irq_i                  (irq),
      .flush_i_valid_o        (flush_i_valid),
      .flush_i_ready_i        (1'b1),
      .inst_addr_o,
      .inst_cacheable_o       (inst_cacheable),
      .inst_data_i,
      .inst_valid_o,
      .inst_ready_i,
      .acc_qreq_o             (acc_req),
      .acc_qvalid_o           (acc_qvalid),
      .acc_qready_i           (1'b1),
      .acc_prsp_i             (acc_resp),
      .acc_pvalid_i           (1'b0),
      .acc_pready_o           (acc_pready),
      .data_req_o             (data_req),
      .data_rsp_i             (data_rsp),
      .ptw_valid_o            (ptw_valid),
      .ptw_ready_i            (2'b11),
      .ptw_va_o               (ptw_va),
      .ptw_ppn_o              (ptw_ppn),
      .ptw_pte_i              (ptw_pte),
      .ptw_is_4mega_i         (2'b00),
      .fpu_rnd_mode_o         (fpu_rnd_mode),
      .fpu_fmt_mode_o         (fpu_fmt_mode),
      .fpu_status_i           ('0),
      .core_events_o          (core_events),
      .barrier_o,
      .barrier_i              (1'b0)
  );
endmodule
