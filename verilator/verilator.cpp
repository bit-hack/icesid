#include <cstdint>

#include "verilated.h"
#include "Vsid.h"


int main(int argc, char **args) {

    Verilated::commandArgs(argc, args);
    Vsid sid;

    for (uint64_t i = 0; i < 10000;) {

        if (Verilated::gotFinish()) {
            break;
        }

        sid.clk = i & 1;
        sid.eval();
    }

    return 0;
}
