package s8_snitch_host_ctrl_core_pkg;
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

module s8_snitch_host_ctrl_core (
    input  logic        clk,
    input  logic        reset,

    input  logic [3:0]  avs_address,
    input  logic        avs_read,
    output logic [31:0] avs_readdata,
    input  logic        avs_write,
    input  logic [31:0] avs_writedata,
    input  logic [3:0]  avs_byteenable,
    output logic        avs_waitrequest,

    output logic [9:0]  ledr
);
    import snitch_pkg::*;
    import s8_snitch_host_ctrl_core_pkg::*;

    `include "rom_words.svh"

    localparam logic [31:0] ID_VALUE = 32'h5338_0001;

    localparam logic [3:0] REG_ID          = 4'h0;
    localparam logic [3:0] REG_CONTROL     = 4'h1;
    localparam logic [3:0] REG_STATUS      = 4'h2;
    localparam logic [3:0] REG_RESULT      = 4'h3;
    localparam logic [3:0] REG_START_COUNT = 4'h4;
    localparam logic [3:0] REG_RUN_CYCLES  = 4'h5;
    localparam logic [3:0] REG_ROM_WORDS   = 4'h6;
    localparam logic [3:0] REG_RAM0        = 4'h7;

    localparam logic [1:0] STATE_IDLE  = 2'd0;
    localparam logic [1:0] STATE_RESET = 2'd1;
    localparam logic [1:0] STATE_RUN   = 2'd2;
    localparam logic [1:0] STATE_DONE  = 2'd3;

    localparam addr_t DONE_MMIO_ADDR = 33'h0_4000_0000;
    localparam addr_t RAM_BASE_ADDR  = 33'h0_0000_1000;
    localparam int unsigned RAM_WORDS = 16;

    interrupts_t irq;
    assign irq = '0;

    logic          snitch_rst;
    logic          flush_i_valid;
    addr_t         inst_addr;
    logic          inst_cacheable;
    logic          inst_valid;
    logic [31:0]   inst_data;
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

    logic [1:0] state_q;
    logic [9:0] result_q;
    logic [31:0] start_count_q;
    logic [31:0] run_cycles_q;

    logic       data_rsp_valid_q;
    data_t      data_rsp_data_q;
    logic       data_rsp_error_q;
    data_t      ram_q [RAM_WORDS];

    logic data_q_fire;
    logic data_p_fire;
    logic done_mmio_access;
    logic ram_access;
    logic [3:0] ram_word_index;

    logic write_control;
    logic clear_cmd;
    logic start_cmd;
    logic busy;
    logic done;
    logic pass;
    logic fail;

    assign avs_waitrequest = 1'b0;
    assign acc_resp = '0;
    assign ptw_pte = '0;

    assign write_control = avs_write && avs_byteenable[0] && (avs_address == REG_CONTROL);
    assign clear_cmd = write_control && avs_writedata[1];
    assign start_cmd = write_control && avs_writedata[0] && !busy;

    assign busy = (state_q == STATE_RESET) || (state_q == STATE_RUN);
    assign done = (state_q == STATE_DONE);
    assign pass = done && result_q[8];
    assign fail = done && !result_q[8];

    assign snitch_rst = reset || (state_q != STATE_RUN);

    always_comb begin
        inst_data = s8_rom_word({2'b0, inst_addr[31:2]});
    end

    assign data_q_fire = data_req.q_valid && data_rsp.q_ready;
    assign data_p_fire = data_rsp.p_valid && data_req.p_ready;
    assign done_mmio_access = data_req.q.addr == DONE_MMIO_ADDR;
    assign ram_access = data_req.q.addr[32:6] == RAM_BASE_ADDR[32:6];
    assign ram_word_index = data_req.q.addr[5:2];

    assign data_rsp.q_ready = ~data_rsp_valid_q;
    assign data_rsp.p_valid = data_rsp_valid_q;
    assign data_rsp.p.data  = data_rsp_data_q;
    assign data_rsp.p.error = data_rsp_error_q;

    always_ff @(posedge clk) begin
        if (reset || clear_cmd) begin
            state_q          <= STATE_IDLE;
            result_q         <= 10'b0;
            start_count_q    <= 32'd0;
            run_cycles_q     <= 32'd0;
            data_rsp_valid_q <= 1'b0;
            data_rsp_data_q  <= '0;
            data_rsp_error_q <= 1'b0;
            for (int unsigned i = 0; i < RAM_WORDS; i++) begin
                ram_q[i] <= '0;
            end
        end else begin
            if (data_p_fire) begin
                data_rsp_valid_q <= 1'b0;
            end

            unique case (state_q)
                STATE_IDLE, STATE_DONE: begin
                    if (start_cmd) begin
                        state_q          <= STATE_RESET;
                        result_q         <= 10'b0;
                        run_cycles_q     <= 32'd0;
                        data_rsp_valid_q <= 1'b0;
                        start_count_q    <= start_count_q + 32'd1;
                        for (int unsigned i = 0; i < RAM_WORDS; i++) begin
                            ram_q[i] <= '0;
                        end
                    end
                end

                STATE_RESET: begin
                    state_q <= STATE_RUN;
                end

                STATE_RUN: begin
                    run_cycles_q <= run_cycles_q + 32'd1;

                    if (data_q_fire) begin
                        data_rsp_valid_q <= 1'b1;
                        data_rsp_error_q <= 1'b0;

                        if (done_mmio_access && !data_req.q.write) begin
                            data_rsp_data_q <= {{22{1'b0}}, result_q};
                        end else if (ram_access && !data_req.q.write) begin
                            data_rsp_data_q <= ram_q[ram_word_index];
                        end else begin
                            data_rsp_data_q <= '0;
                        end

                        if (data_req.q.write && done_mmio_access) begin
                            result_q <= data_req.q.data[9:0];
                            state_q  <= STATE_DONE;
                        end

                        if (data_req.q.write && ram_access) begin
                            if (data_req.q.strb[0]) begin
                                ram_q[ram_word_index][7:0] <= data_req.q.data[7:0];
                            end
                            if (data_req.q.strb[1]) begin
                                ram_q[ram_word_index][15:8] <= data_req.q.data[15:8];
                            end
                            if (data_req.q.strb[2]) begin
                                ram_q[ram_word_index][23:16] <= data_req.q.data[23:16];
                            end
                            if (data_req.q.strb[3]) begin
                                ram_q[ram_word_index][31:24] <= data_req.q.data[31:24];
                            end
                        end
                    end
                end

                default: begin
                    state_q <= STATE_IDLE;
                end
            endcase
        end
    end

    always_comb begin
        unique case (avs_address)
            REG_ID:          avs_readdata = ID_VALUE;
            REG_CONTROL:     avs_readdata = 32'h0000_0000;
            REG_STATUS:      avs_readdata = {27'd0, state_q != STATE_IDLE, fail, pass, busy, done};
            REG_RESULT:      avs_readdata = {22'd0, result_q};
            REG_START_COUNT: avs_readdata = start_count_q;
            REG_RUN_CYCLES:  avs_readdata = run_cycles_q;
            REG_ROM_WORDS:   avs_readdata = S8_ROM_WORDS;
            REG_RAM0:        avs_readdata = ram_q[0];
            default:         avs_readdata = 32'h0000_0000;
        endcase
    end

    snitch #(
        .BootAddr                 (32'h0000_0000),
        .AddrWidth                (33),
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
        .SnitchPMACfg             (1664'b0),
        .DebugSupport             (1'b0)
    ) i_snitch (
        .clk_i                    (clk),
        .rst_i                    (snitch_rst),
        .hart_id_i                (32'd0),
        .irq_i                    (irq),
        .flush_i_valid_o          (flush_i_valid),
        .flush_i_ready_i          (1'b1),
        .inst_addr_o              (inst_addr),
        .inst_cacheable_o         (inst_cacheable),
        .inst_data_i              (inst_data),
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

    assign ledr[7:0] = result_q[7:0];
    assign ledr[8] = pass;
    assign ledr[9] = busy;
endmodule
