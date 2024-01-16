prefix = $(shell pwd)
# Folder Path
src = $(prefix)/src
testspace = $(prefix)/testspace
testcase = $(prefix)/testcase

sim_testcase = $(testcase)/sim
fpga_testcase = $(testcase)/fpga

sim = $(prefix)/sim
riscv_toolchain = /opt/riscv
riscv_bin = $(riscv_toolchain)/bin
sys = $(prefix)/sys

sources = $(shell find "$(src)" -name '*.v')

testcases=$(shell find $(testcase) -name "*.c")
datafiles=$(testcases:.c=.data)
dumpfiles=$(testcases:.c=.dump)

all: $(datafiles) $(dumpfiles)

_no_testcase_name_check:
	@$(if $(strip $(name)),, echo 'Missing Testcase Name')
	@$(if $(strip $(name)),, exit 1)

# All build result are put at testspace
build_sim:
	@cd $(src) && iverilog -o $(testspace)/test $(sim)/testbench.v  ${sources}

build_sim_test: _no_testcase_name_check all
	@cp $(sim_testcase)/*$(name)*.c $(testspace)/test.c
	@cp $(sim_testcase)/*$(name)*.data $(testspace)/test.data
	@cp $(sim_testcase)/*$(name)*.dump $(testspace)/test.dump


build_sim_test_vector: _no_testcase_name_check
	@$(riscv_bin)/riscv64-unknown-elf-as -o $(sys)/rom.o -march=rv64i $(sys)/rom.s
	@cp $(sim_testcase)/*$(name)*.c $(testspace)/test.c
	@$(riscv_bin)/riscv64-unknown-elf-gcc -o $(testspace)/test.o -I $(sys) -c $(testspace)/test.c -g -march=rv64gv -static -mabi=lp64 -O3
	@$(riscv_bin)/riscv64-unknown-elf-ld -T $(sys)/memory.ld $(sys)/rom.o $(testspace)/test.o -L $(riscv_toolchain)/riscv64-unknown-elf/lib/ -L $(riscv_toolchain)/lib/gcc/riscv64-unknown-elf/13.2.0/ -lc -lgcc -lm -lnosys -o $(testspace)/test.om
	@$(riscv_bin)/riscv64-unknown-elf-objcopy -O verilog $(testspace)/test.om $(testspace)/test.data
	@$(riscv_bin)/riscv64-unknown-elf-objdump -d $(testspace)/test.om > $(testspace)/test.dump

AS=$(riscv_bin)/riscv32-unknown-elf-as
CC=$(riscv_bin)/riscv32-unknown-elf-gcc
LD=$(riscv_bin)/riscv32-unknown-elf-ld
OBJCOPY=$(riscv_bin)/riscv32-unknown-elf-objcopy
OBJDUMP=$(riscv_bin)/riscv32-unknown-elf-objdump

AS_FLAGS=-march=rv32i
CFLAGS=-I $(sys) -O2 -march=rv32i -mabi=ilp32 -Wall

%.dump: %.om
	@$(OBJDUMP) -D $< > $@

%.data: %.om
	@if [[ $@ =~ "fpga" ]] \
	then \
		$(OBJCOPY) -O binary $< $@ ; \
	else \
		$(OBJCOPY) -O verilog $< $@ ; \
	fi

%.om: $(sys)/rom.o %.o
	@$(LD) -T $(sys)/memory.ld $^ -L $(riscv_toolchain)/riscv32-unknown-elf/lib/ -L $(riscv_toolchain)/lib/gcc/riscv32-unknown-elf/13.2.0/ -lc -lgcc -lm -lnosys -o $@

%.o: %.c
	@if [[ $@ =~ "fpga" ]] \
	then \
		$(CC) -o $@ -c $< $(CFLAGS) ; \
	else \
		$(CC) -o $@ -c $< $(CFLAGS) -DSIM ; \
	fi

$(sys)/rom.o: $(sys)/rom.s
	@$(AS) -o $@ -c $< $(AS_FLAGS)

run_sim:
	@cd $(testspace) && ./test

clean:
	@rm -f $(sys)/rom.o $(testspace)/test* $(datafiles) $(dumpfiles)

test_sim: build_sim build_sim_test run_sim

.PHONY: _no_testcase_name_check build_sim build_sim_test run_sim clear test_sim all