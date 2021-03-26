R_BIN=$(readlink -e ../R-dyntrace/bin)
R_LIBS=$(readlink -e ../library)

export PATH=$R_BIN:$PATH
export R_LIBS
export R_KEEP_PKG_SOURCE=1
export R_ENABLE_JIT=0
export R_COMPILE_PKGS=0
export R_DISABLE_BYTECODE=1
