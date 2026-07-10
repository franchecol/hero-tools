package dm;
  localparam logic [3:0] DataCount = 4'h2;
  localparam logic [63:0] HaltAddress = 64'h800;
  localparam logic [63:0] ExceptionAddress = HaltAddress + 16;
  localparam logic [11:0] DataAddr = 12'h380;

  localparam logic [2:0] CauseBreakpoint = 3'h1;
  localparam logic [2:0] CauseRequest = 3'h3;
  localparam logic [2:0] CauseSingleStep = 3'h4;

  typedef enum logic [1:0] {
    PRIV_LVL_U = 2'b00,
    PRIV_LVL_S = 2'b01,
    PRIV_LVL_M = 2'b11
  } priv_lvl_t;

  typedef struct packed {
    logic [31:24] zero1;
    logic [23:20] nscratch;
    logic [19:17] zero0;
    logic         dataaccess;
    logic [15:12] datasize;
    logic [11:0]  dataaddr;
  } hartinfo_t;

  typedef struct packed {
    logic [31:28] xdebugver;
    logic [27:16] zero2;
    logic         ebreakm;
    logic         zero1;
    logic         ebreaks;
    logic         ebreaku;
    logic         stepie;
    logic         stopcount;
    logic         stoptime;
    logic [8:6]   cause;
    logic         zero0;
    logic         mprven;
    logic         nmip;
    logic         step;
    priv_lvl_t    prv;
  } dcsr_t;
endpackage

package fpnew_pkg;
  typedef enum logic [2:0] {
    RNE = 3'b000,
    RTZ = 3'b001,
    RDN = 3'b010,
    RUP = 3'b011,
    RMM = 3'b100,
    DYN = 3'b111
  } roundmode_e;

  typedef struct packed {
    logic src;
    logic dst;
  } fmt_mode_t;

  typedef struct packed {
    logic NV;
    logic DZ;
    logic OF;
    logic UF;
    logic NX;
  } status_t;
endpackage

package reqrsp_pkg;
  typedef enum logic [3:0] {
    AMONone = 4'h0,
    AMOSwap = 4'h1,
    AMOAdd  = 4'h2,
    AMOAnd  = 4'h3,
    AMOOr   = 4'h4,
    AMOXor  = 4'h5,
    AMOMax  = 4'h6,
    AMOMaxu = 4'h7,
    AMOMin  = 4'h8,
    AMOMinu = 4'h9,
    AMOLR   = 4'hA,
    AMOSC   = 4'hB
  } amo_op_e;
endpackage
