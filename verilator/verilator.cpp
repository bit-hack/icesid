#include <cstdint>

#include "verilated.h"
#include "verilated_vcd_c.h"
#include "Vsid.h"


static void sidClock(Vsid &sid) {
    sid.clk = 0;
    sid.eval();
    Verilated::timeInc(1);
    sid.clk = 1;
    sid.eval();
    Verilated::timeInc(1);
}

static void sidWrite(Vsid &sid, uint8_t reg, uint8_t data) {
    sid.iWE = 1;
    sid.iAddr = reg;
    sid.iDataW = data;
    sidClock(sid);
    sid.iWE = 0;
}

static uint8_t sidRead(Vsid &sid, uint8_t reg) {
    sid.iAddr = reg;
    sidClock(sid);
    return sid.oDataR;
}

static int16_t sidSample(Vsid &sid) {
    return sid.oOut;
}

static void sidClear(Vsid &sid) {
    for (int i=0; i<16; ++i) {
        sidWrite(sid, i, 0);
    }
}

int main(int argc, char **args) {

    Verilated::commandArgs(argc, args);
    Verilated::traceEverOn(true);

    Vsid sid;

    sidClear(sid);

    sid.clkEn = 1;

    sidWrite(sid, 0, 0x80);         // v0, freq lo
    sidWrite(sid, 1, 0x80);         // v0, freq hi
    sidWrite(sid, 2, 0x00);         // v0, duty lo
    sidWrite(sid, 3, 0x08);         // v0, duty hi
    sidWrite(sid, 5, 0x00);         // v0, A D
    sidWrite(sid, 6, 0xf0);         // v0, S R
    sidWrite(sid, 4, 0b00100001);   // v0, ctrl (saw, gate)

    for (uint64_t i = 0; i < 1000; ++i) {

        if (Verilated::gotFinish()) {
            break;
        }

        sidClock(sid);
    }

    return 0;
}
