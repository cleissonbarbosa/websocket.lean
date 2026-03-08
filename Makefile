.PHONY: all clean build-c build-lean demo perf run check-deps help info distclean

BUILD_DIR = .lake/build

all: build-lean

build-lean:
	@echo "Compile Lean project..."
	lake build

# Execute test
perf: build-lean
	@echo "Executing tests..."
	lake exe tests

check-deps:
	@echo "Checking dependencies..."
	@command -v lake >/dev/null 2>&1 || { echo "Lake not found!"; exit 1; }  
	@command -v lean >/dev/null 2>&1 || { echo "Lean not found!"; exit 1; }
	@echo "All dependencies are installed ✓"

clean:
	@echo "Cleaning up compiled files..."
	rm -rf $(BUILD_DIR)

distclean: clean
	@echo "Complete cleanup..."
	lake clean
