all:
	verilator -sv --timing -Wno-INITIALDLY --cc --exe --build -j mac.sv verilator_tb.sv sim_main.cpp --top-module verilator_tb
	./obj_dir/Vverilator_tb

clean:
	rm -rf obj_dir