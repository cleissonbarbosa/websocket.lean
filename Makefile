.PHONY: all clean build-c build-lean demo perf run check-deps help info distclean

# Dir
C_DIR = c
BUILD_DIR = .lake/build



all: build-c build-lean

# Compile C module
build-c: 
	@echo "Compile C modules..."
	lake script run build_c_modules

build-lean: build-c
	@echo "Compilando projeto Lean..."
	lake build

# Execute test
perf: build-lean
	@echo "Executing tests..."
	lake exe tests

check-deps:
	@echo "Checking dependencies..."
	@command -v cc >/dev/null 2>&1 || { echo "gcc/clang not found!"; exit 1; }
	@command -v lake >/dev/null 2>&1 || { echo "Lake not found!"; exit 1; }  
	@command -v lean >/dev/null 2>&1 || { echo "Lean not found!"; exit 1; }
	@echo "All dependencies are installed ✓"

clean:
	@echo "Cleaning up compiled files..."
	rm -rf $(BUILD_DIR)
	rm -f $(C_OBJS)
	rm -f /tmp/rinha*.sock
	rm -f /dev/shm/rinha*

distclean: clean
	@echo "Complete cleanup..."
	lake clean
