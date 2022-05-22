// .___               _________.___________
// |   | ____  ____  /   _____/|   \______ \
// |   |/ ___\/ __ \ \_____  \ |   ||    |  \
// |   \  \__\  ___/ /        \|   ||    `   \
// |___|\___  >___  >_______  /|___/_______  /
//          \/    \/        \/             \/
`default_nettype none

module sid_env_imp (
    input        clk,
    input        clkEn,
    input        iRst,
    input        iGate,
    input  [3:0] iAtt,
    input  [3:0] iDec,
    input  [3:0] iSus,
    input  [3:0] iRel,
    output [7:0] oOut
);

  reg [7:0] env;  // envelope output value
  assign oOut = env;

  localparam STAGE_ATT     = 1;
  localparam STAGE_DEC_SUS = 2;
  localparam STAGE_REL     = 4;
  reg [2:0] stage;

  wire [7:0] sustainVal = {iSus, iSus};

  initial begin
    env    = 0;
    stage  = STAGE_REL;
    cnt    = 0;
    cntRst = 0;
    div    = 0;
    divMax = 1;
    divRst = 0;
  end

  // envelope decay/release comparitor
  reg [4:0] divMax;
  always @(posedge clk) begin
    /* verilog_format: off */
    case (env)
      8'hff: divMax <= 0;
      8'h5d: divMax <= 1;
      8'h36: divMax <= 3;
      8'h1a: divMax <= 7;
      8'h0e: divMax <= 15;
      8'h06: divMax <= 29;
      8'h00: divMax <= 0;
      default: ;
    endcase
    /* verilog_format: on */
  end

  reg [3:0] rate;
  always @(*) begin
    case (stage)
      STAGE_ATT:     rate = iAtt;
      STAGE_DEC_SUS: rate = iDec;
      default:       rate = iRel;
    endcase
  end

  reg [14:0] cntMax;
  always @(*) begin
    /* verilog_format: off */
    case (rate)              //  ATT      DEC/REL
      4'hf: cntMax = 31250;  //   8s       24s
      4'he: cntMax = 19531;  //   5s       15s
      4'hd: cntMax = 11719;  //   3s        9s
      4'hc: cntMax = 3906;   //   1s        3s
      4'hb: cntMax = 3125;   // 800ms       2.4s
      4'ha: cntMax = 1953;   // 500ms       1.5s
      4'h9: cntMax = 976;    // 250ms     750ms
      4'h8: cntMax = 391;    // 100ms     300ms
      4'h7: cntMax = 312;    //  80ms     240ms
      4'h6: cntMax = 266;    //  68ms     204ms
      4'h5: cntMax = 219;    //  56ms     168ms
      4'h4: cntMax = 148;    //  38ms     114ms
      4'h3: cntMax = 94;     //  24ms      72ms
      4'h2: cntMax = 62;     //  16ms      48ms
      4'h1: cntMax = 31;     //   8ms      24ms
      4'h0: cntMax = 8;      //   2ms       6ms
    endcase
    /* verilog_format: on */
  end

  reg [14:0] cnt;
  reg cntRst;
  always @(posedge clk) begin
    cntRst <= 0;
    if (clkEn) begin
      if (cnt == 0) begin
        cntRst <= 1;
        cnt <= cntMax;
      end else begin
        cnt <= cnt - 1;
      end
    end
  end

  // decay / release phase goes through a divider so they are longer
  reg [4:0] div;
  reg divRst;
  always @(posedge clk) begin
    if (iRst) begin
      divRst <= 0;
      div    <= 0;
    end else begin
      divRst <= 0;
      if (cntRst) begin
        if (div == 0) begin
          divRst <= 1;
          div <= divMax;
        end else begin
          div <= div - 1;
        end
      end
    end
  end

  always @(posedge clk) begin
    if (iRst) begin
      env   <= 8'haa;
      stage <= STAGE_REL;
    end else begin
      case (1'b1)
        stage[0]: begin  // att
          if (iGate) begin
            if (env == 8'hff) begin
              stage <= STAGE_DEC_SUS;
            end else begin
              if (cntRst) begin
                env <= env + 1;
              end
            end
          end else begin
            stage <= STAGE_REL;
          end
        end
        stage[1]: begin  // dec/sus
          if (iGate) begin
            if (divRst) begin
              if (env == sustainVal) begin
                // sustain so do nothing
              end else begin
                env <= (env == 0) ? 0 : (env - 1);
              end
            end
          end else begin
            stage <= STAGE_REL;
          end
        end
        stage[2]: begin  // rel
          if (iGate) begin
            stage <= STAGE_ATT;
          end else begin
            if (divRst) begin
              env <= (env == 0) ? 0 : (env - 1);
            end
          end
        end
        default: stage <= STAGE_REL;
      endcase
    end
  end
endmodule

module sid_env (
    input        clk,    // master clock
    input        clkEn,  // asserted at 1Mhz
    input        iRst,   // reset
    input        iWE,    // write enable
    input  [4:0] iAddr,  // address bus
    input  [7:0] iData,  // data bus
    output [7:0] oOut
);

  // register base address
  parameter BASE_ADDR = 0;

  reg       regGate;  // envelope gate
  reg [3:0] regAtt;  // envelope attack
  reg [3:0] regDec;  // envelope decay
  reg [3:0] regSus;  // envelope systain
  reg [3:0] regRel;  // envelope release

  sid_env_imp impl (
      .clk   (clk),
      .clkEn (clkEn),
      .iRst  (iRst),
      .iGate (regGate),
      .iAtt  (regAtt),
      .iDec  (regDec),
      .iSus  (regSus),
      .iRel  (regRel),
      .oOut  (oOut)
  );

  initial begin
    regGate = 0;
    regAtt  = 0;
    regDec  = 0;
    regSus  = 0;
    regRel  = 0;
  end

  // address/data decoder
  always @(posedge clk) begin
    if (iWE) begin
      case (iAddr)
        (BASE_ADDR + 'h4): begin
          regGate <= iData[0];
        end
        (BASE_ADDR + 'h5): begin
          regAtt <= iData[7:4];
          regDec <= iData[3:0];
        end
        (BASE_ADDR + 'h6): begin
          regSus <= iData[7:4];
          regRel <= iData[3:0];
        end
      endcase
    end
  end
endmodule
