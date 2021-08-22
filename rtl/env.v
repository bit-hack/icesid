`default_nettype none
`timescale 1us/1ns

// theory of operation:
// - ~1Mhz clocks LFSR15
// - current rate setting (att/dec/rel) sets the compare value for LFSR15
// - when next LFSR15 value has a compare match it resets
// - when LFSR15 resets in ATTACK phase, the envelope increments
// - when the envelope reaches 0xff it enters the DECAY phase
// - if GATE goes low at any time it enters the RELEASE phase
// - in the DEC/REL phase the env is clocked on LFSR5 reset
// - when envelope hits a threshold, the LFSR5 reset compare value advances
module sid_env_imp(input        CLK,
                   input        CLKen,
                   input        GATE,
                   input  [3:0] ATT,
                   input  [3:0] DEC,
                   input  [3:0] SUS,
                   input  [3:0] REL,
                   output [7:0] OUT);

  reg [ 7:0] env;           // envelope output value
  reg [14:0] lfsr15;        // 15 stage lfsr
  reg [ 4:0] lfsr5;         // 5 stage lfsr
  reg gate_lag;             // delayed gate signal
  reg dir;                  // 0: down, 1: up

  assign OUT = env;

  initial begin
    env          = 0;
    lfsr15       = 'h7fff;
    lfsr5        = 'h1f;
    gate_lag     = 0;
    dir          = 0;
    env_dec_cmp  = 0;
    lfsr5_sel    = 1;
    lfsr15_reset = 0;
    lfsr5_reset  = 0;
    lfsr15_cmp   = 0;
    lfsr5_cmp    = 0;
    stage_rate   = 0;
    env_sus_cmp  = 0;
  end

  // envelope decay/release comparitor
  reg env_dec_cmp;
  always @(posedge CLK) begin
    env_dec_cmp <=
//    env == 'hff |              //   1 (pseudo)
      env == 'h5d |              //   2
      env == 'h36 |              //   4
      env == 'h1a |              //   8
      env == 'h0e |              //  16
      env == 'h06 |              //  30
      env == 'h00;               // INF
  end

  reg [5:0] lfsr5_cmp;           // stores all the comparisons against lfsr5
  reg [5:0] lfsr5_sel;           // select which bit of lfsr5_cmp to reset on
  always @(*) begin
    lfsr5_cmp = {
      lfsr5_next == 'h0f,        //  30
      lfsr5_next == 'h08,        //  16
      lfsr5_next == 'h1b,        //   8
      lfsr5_next == 'h11,        //   4
      lfsr5_next == 'h1c,        //   2
      lfsr5_next == 'h1e         //   1 (added)
    };
  end

  reg [15:0] lfsr15_cmp;         // stores all the comparisons against lfsr15
  always @(*) begin
    lfsr15_cmp = {
                                 // count  attack  decay (x3)
      lfsr15_next == 'h0a93,     // 31250    8s       24s
      lfsr15_next == 'h7625,     // 19531    5s       15s
      lfsr15_next == 'h77e2,     // 11719    3s        9s
      lfsr15_next == 'h3840,     //  3906    1s        3s
      lfsr15_next == 'h59b8,     //  3125  800ms       2.4s
      lfsr15_next == 'h1848,     //  1953  500ms       1.5s
      lfsr15_next == 'h0222,     //   976  250ms     750ms
      lfsr15_next == 'h1212,     //   391  100ms     300ms
      lfsr15_next == 'h500e,     //   312   80ms     240ms
      lfsr15_next == 'h3800,     //   266   68ms     204ms
      lfsr15_next == 'h6755,     //   219   56ms     168ms
      lfsr15_next == 'h20c0,     //   148   38ms     114ms
      lfsr15_next == 'h0330,     //    94   24ms      72ms
      lfsr15_next == 'h003c,     //    62   16ms      48ms
      lfsr15_next == 'h0006,     //    31    8ms      24ms
      lfsr15_next == 'h7f00      //     8    2ms       6ms
    };
  end

  // envelope sustain comparitor
  reg env_sus_cmp;
  always @(posedge CLK) begin
    env_sus_cmp <= (env == { SUS, SUS });
  end

  // update lfsr15 register
  wire [14:0] lfsr15_next = { lfsr15[13:0], lfsr15[13] ^ lfsr15[14] };
  reg lfsr15_reset;
  always @(posedge CLK) begin
    lfsr15_reset <= 0;
    if (CLKen) begin
      if (lfsr15_cmp[stage_rate]) begin
        // reset the lfsr
        lfsr15_reset <= 1;
        lfsr15 <= 'h7fff;
      end else begin
        lfsr15 <= lfsr15_next;
      end
    end
  end

  // update lfsr5 register
  wire [4:0] lfsr5_next = { lfsr5[3:0], lfsr5[2] ^ lfsr5[4] };
  reg lfsr5_reset;
  always @(posedge CLK) begin
    lfsr5_reset <= 0;
    if (lfsr15_reset) begin
      if (lfsr5_cmp & lfsr5_sel) begin
        lfsr5_reset <= 1;
        lfsr5 <= 'h1f;
      end else begin
        lfsr5 <= lfsr5_next;
      end
    end
  end

  // update envelope direction
  always @(posedge CLK) begin
    gate_lag <= GATE;
    if (GATE) begin
      if (!gate_lag) begin
        dir <= 1;               // up for attack
      end else begin
        if (env == 'hff) begin
          dir <= 0;             // down for decay phase
        end
      end
    end else begin
      dir <= 0;                 // down for the release phase
    end
  end

  // update the current stages rate selection
  reg [3:0] stage_rate;
  always @(posedge CLK) begin
    case ({GATE, dir})
    2'b00: stage_rate <= REL;
    2'b01: stage_rate <= ATT;   // unused
    2'b10: stage_rate <= DEC;
    2'b11: stage_rate <= ATT;
    endcase
  end

  // update lfsr_sel to model the exponential decay
  // when we get a env_dec_cmp we increase the period for the lfsr5 counter
  always @(posedge CLK) begin
    if (dir == 0) begin
      if (lfsr5_reset) begin
        if (env_dec_cmp) begin  // on compare match for env value
          // shift left to
          lfsr5_sel <= { lfsr5_sel[4:0], 1'b0 };
        end
      end
    end else begin
      lfsr5_sel <= 'b1;         // set to 1 which will reset lfsr5 to div/1
    end
  end

  // update envelope
  always @(posedge CLK) begin
    case ({GATE, dir})
    2'b00: begin                // release
      if (env != 0) begin
        if (lfsr5_reset) begin
          env <= env - 'd1;
        end
      end
    end
    2'b10: begin                // decay
      if (env_sus_cmp) begin
        // sustaining, do nothing
      end else begin
        if (lfsr5_reset) begin
          env <= env - 'd1;
        end
      end
    end
    2'b11: begin                // attack
      if (lfsr15_reset) begin
        env <= env + 'd1;
      end
    end
    endcase
  end
endmodule

module sid_env(input CLK,           // master clock
               input CLKen,         // asserted at 1Mhz
               input WR,            // data write
               input [4:0] ADDR,    // address bus
               input [7:0] DATA,    // data bus
               output [7:0] OUTPUT
               );

  // register base address
  parameter BASE_ADDR = 0;

  reg reg_gate;             // envelope gate
  reg [3:0] reg_att;        // envelope attack
  reg [3:0] reg_dec;        // envelope decay
  reg [3:0] reg_sus;        // envelope systain
  reg [3:0] reg_rel;        // envelope release

  sid_env_imp impl(.CLK  (CLK),
                   .CLKen(CLKen),
                   .GATE (reg_gate),
                   .ATT  (reg_att),
                   .DEC  (reg_dec),
                   .SUS  (reg_sus),
                   .REL  (reg_rel),
                   .OUT  (OUTPUT));

  initial begin
    reg_gate    = 0;
    reg_att     = 0;
    reg_dec     = 0;
    reg_sus     = 'hf;      // 100% sustain
    reg_rel     = 0;
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
