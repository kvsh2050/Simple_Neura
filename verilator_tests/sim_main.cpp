#include <memory>
#include "Vverilator_tb.h"
#include "Vverilator_tb___024root.h" // Include the root structure header
#include "verilated.h"

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    auto top = std::make_unique<Vverilator_tb>();

    // Access clk through the top-level root pointer
    top->rootp->verilator_tb__DOT__clk = 0; 

    for (int cycle = 0; cycle < 1000; ++cycle) {
        top->rootp->verilator_tb__DOT__clk = !top->rootp->verilator_tb__DOT__clk; 
        top->eval();          
        
        if (Verilated::gotFinish()) break;
    }
    top->final();
    return 0;
}