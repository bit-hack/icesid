`default_nettype none
`timescale 1us/1ns

module sid_env_imp(
    input        CLK,
    input        CLKen,
    input        GATE,
    input  [3:0] ATT,
    input  [3:0] DEC,
    input  [3:0] SUS,
    input  [3:0] REL,
    output [7:0] OUT
    );

  reg [7:0] env;    // envelope output value
  assign OUT = env;

  localparam STAGE_ATT     = 1;
  localparam STAGE_DEC_SUS = 2;
  localparam STAGE_REL     = 4;
  reg [2:0] stage;

  wire [7:0] sustain_val = { SUS, SUS };

  initial begin
    env     = 0;
    stage   = STAGE_REL;
    cnt     = 0;
    cnt_rst = 0;
    div     = 0;
    div_max = 1;
    div_rst = 0;
  end

  // envelope decay/release comparitor
  reg [4:0] div_max;
  always @(posedge CLK) begin
    case (env)
    8'hff: div_max <=  1;
    8'h5d: div_max <=  2;
    8'h36: div_max <=  4;
    8'h1a: div_max <=  8;
    8'h0e: div_max <= 16;
    8'h06: div_max <= 30;
    8'h00: div_max <=  1;
    default: ;
    endcase
  end

  reg [3:0] rate;
  always @(*) begin
    case (stage)
    STAGE_ATT:     rate = ATT;
    STAGE_DEC_SUS: rate = DEC;
    default:       rate = REL;
    endcase
  end

  reg [14:0] cnt_max;
  always @(*) begin
    case (rate)             // ATT      DEC/REL
    4'hf: cnt_max = 31250;  //   8s       24s
    4'he: cnt_max = 19531;  //   5s       15s
    4'hd: cnt_max = 11719;  //   3s        9s
    4'hc: cnt_max =  3906;  //   1s        3s
    4'hb: cnt_max =  3125;  // 800ms       2.4s
    4'ha: cnt_max =  1953;  // 500ms       1.5s
    4'h9: cnt_max =   976;  // 250ms     750ms
    4'h8: cnt_max =   391;  // 100ms     300ms
    4'h7: cnt_max =   312;  //  80ms     240ms
    4'h6: cnt_max =   266;  //  68ms     204ms
    4'h5: cnt_max =   219;  //  56ms     168ms
    4'h4: cnt_max =   148;  //  38ms     114ms
    4'h3: cnt_max =    94;  //  24ms      72ms
    4'h2: cnt_max =    62;  //  16ms      48ms
    4'h1: cnt_max =    31;  //   8ms      24ms
    4'h0: cnt_max =     8;  //   2ms       6ms
    endcase
  end

  reg [14:0] cnt;
  reg cnt_rst;
  always @(posedge CLK) begin
    cnt_rst <= 0;
    if (CLKen) begin
      if (cnt == 0) begin
        cnt_rst <= 1;
        cnt <= cnt_max;
      end else begin
        cnt <= cnt - 1;
      end
    end
  end

  reg [4:0] div;
  reg div_rst;
  always @(posedge CLK) begin
    div_rst <= 0;
    if (cnt_rst) begin
      if (div == 0) begin
        div_rst <= 1;
        div <= div_max;
      end else begin
        div <= div - 1;
      end
    end
  end

  always @(posedge CLK) begin
    case (stage)
    STAGE_ATT: begin
      if (GATE) begin
        if (env == 8'hff) begin
          stage <= STAGE_DEC_SUS;
        end else begin
          if (cnt_rst) begin
            env <= env + 1;
          end
        end
      end else begin
        stage <= STAGE_REL;
      end
    end  // STAGE_ATT
    STAGE_DEC_SUS: begin
      if (GATE) begin
        if (div_rst) begin
          if (env == sustain_val) begin
            // sustain so do nothing
          end else begin
            env <= (env == 0) ? 0 : (env - 1);
          end
        end
      end else begin
        stage <= STAGE_REL;
      end
    end  // STAGE_DEC_SUS
    STAGE_REL: begin
      if (GATE) begin
        stage <= STAGE_ATT;
      end else begin
        if (div_rst) begin
          env <= (env == 0) ? 0 : (env - 1);
        end
      end
    end  // STAGE_REL
    default:
      stage <= STAGE_REL;
    endcase
  end
endmodule

module sid_env(
    input        CLK,       // master clock
    input        CLKen,     // asserted at 1Mhz
    input        WR,        // data write
    input  [4:0] ADDR,      // address bus
    input  [7:0] DATA,      // data bus
    output [7:0] OUTPUT
    );

  // register base address
  parameter BASE_ADDR = 0;

  reg reg_gate;             // envelope gate
  reg [3:0] reg_att;        // envelope attack
  reg [3:0] reg_dec;        // envelope decay
  reg [3:0] reg_sus;        // envelope systain
  reg [3:0] reg_rel;        // envelope release

  sid_env_imp impl(
    .CLK  (CLK),
    .CLKen(CLKen),
    .GATE (reg_gate),
    .ATT  (reg_att),
    .DEC  (reg_dec),
    .SUS  (reg_sus),
    .REL  (reg_rel),
    .OUT  (OUTPUT));

  initial begin
    reg_gate = 0;
    reg_att  = 0;
    reg_dec  = 0;
    reg_sus  = 0;
    reg_rel  = 0;
  end

  // address/data decoder
  always @(posedge CLK) begin
    if (WR) begin
      case (ADDR)
      (BASE_ADDR+'h4): begin reg_gate <= DATA[0];                         end
      (BASE_ADDR+'h5): begin reg_att  <= DATA[7:4]; reg_dec <= DATA[3:0]; end
      (BASE_ADDR+'h6): begin reg_sus  <= DATA[7:4]; reg_rel <= DATA[3:0]; end
      endcase
    end
  end
endmodule
