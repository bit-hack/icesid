`default_nettype none


module clk_filter(
        input iClk,      // system clk
        input iPhi2,
        output oFall
        );

    reg state;
    reg [6:0] shift;
    reg fall;
    assign oFall = fall;

    wire isHigh = &  shift[6:1];    // if all bits high
    wire isLow  = &(~shift[6:1]);   // if all bits low

    initial begin
        state <= 0;
        shift <= 0;
        fall  <= 0;
    end

    always @(posedge iClk) begin
        shift <= { shift[5:0], iPhi2 };
    end

    always @(posedge iClk) begin
        fall <= 0;
        if (state) begin
            if (isLow) begin
                state <= 0;
                fall  <= 1;     // falling edge
            end
        end else begin
            if (isHigh) begin
                state <= 1;
            end
        end
    end
endmodule

module sid_biu(
        input        clk,
        input        d0,    // data lsb
        input        d1,
        input        d2,
        input        d3,
        input        d4,
        input        d5,
        input        d6,
        input        d7,    // data msb
        input        a0,    // addr lsb
        input        a1,
        input        a2,
        input        a3,
        input        a4,    // addr msb
        input        cs,    // chip seect
        input        rw,    // read / write
        input        phi2,
        output       oCLKen,
        output [7:0] oData,
        output [4:0] oAddr,
        output       oWR    // write strobe
    );

    initial begin
        bRW      <= 2'b11;  // read
        bCS      <= 2'b11;  // deselected
        bAddr[0] <= 0;
        bAddr[1] <= 0;
        bData[0] <= 0;
        bData[1] <= 0;
    end

    // simple clock filter
    wire didFall;
    clk_filter clk_flt(clk, phi2, didFall);

    // WR signal
    wire sidWrite = !bRW[1];    // r/w low
    wire sidRead  =  bRW[1];    // r/w high
    reg [1:0] bRW;
    always @(posedge clk) begin
        bRW <= { bRW[0], rw };
    end

    // chip select signal
    reg [1:0] bCS;              // cs active low
    always @(posedge clk) begin
        bCS <= { bCS[0], cs };
    end

    // register address
    reg [4:0] bAddr[2];
    always @(posedge clk) begin
        bAddr[0] <= { a4, a3, a2, a1, a0 };
        bAddr[1] <= bAddr[0];
    end

    // register data
    reg [7:0] bData[2];
    always @(posedge clk) begin
        bData[0] <= { d7, d6, d5, d4, d3, d2, d1, d0 };
        bData[1] <= bData[0];
    end

    // register phi2
//    reg [2:0] bPHI2;
//    always @(posedge clk) begin
//        bPHI2 <= { bPHI2[1:0], phi2 };
//    end

    assign oData  = bData[1];
    assign oAddr  = bAddr[1];
    // rising edge of phi2
    assign oCLKen = didFall;
    // falling edge of phi2, WR low, CS low
    // register this?
    assign oWR    = didFall & sidWrite & !bCS[1];
endmodule
