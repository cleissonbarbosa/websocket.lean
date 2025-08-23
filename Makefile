.PHONY: all clean build-c build-lean demo perf run check-deps help info distclean

# Dir
C_DIR = c
BUILD_DIR = .lake/build

# compile flags
CFLAGS = -std=gnu11 -O3 -DNDEBUG -D_GNU_SOURCE -D_POSIX_C_SOURCE=200809L
LEAN_INC = $(shell lean --print-prefix)/include

# C objects files
C_OBJS = \
		 $(C_DIR)/ws_socket.o

all: build-c build-lean

# Compile C module
build-c: $(C_OBJS)

$(C_DIR)/%.o: $(C_DIR)/%.c
	@echo "Compilando $<..."
	cc $(CFLAGS) -I$(C_DIR) -I$(LEAN_INC) -c $< -o $@

build-lean: build-c
	@echo "Compilando projeto Lean..."
	lake build

# Execute test
perf: build-lean
	@echo "Executando teste..."
	lake exe tests

check-deps:
	@echo "Verificando dependências..."
	@command -v cc >/dev/null 2>&1 || { echo "gcc/clang não encontrado!"; exit 1; }
	@command -v lake >/dev/null 2>&1 || { echo "Lake não encontrado!"; exit 1; }  
	@command -v lean >/dev/null 2>&1 || { echo "Lean não encontrado!"; exit 1; }
	@echo "Todas as dependências estão instaladas ✓"

clean:
	@echo "Limpando arquivos compilados..."
	rm -rf $(BUILD_DIR)
	rm -f $(C_OBJS)
	rm -f /tmp/rinha*.sock
	rm -f /dev/shm/rinha*

distclean: clean
	@echo "Limpeza completa..."
	lake clean
