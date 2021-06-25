BASE_DIR=$(dirname "$0")
SCRIPTS_DIR="$BASE_DIR/scripts"
R_BIN=$("$SCRIPTS_DIR/readlink.sh" R-dyntrace/bin)

export PATH=$R_BIN:$PATH
export R_LIBS=$("$SCRIPTS_DIR/readlink.sh" library-local)
export R_KEEP_PKG_SOURCE=1
export R_ENABLE_JIT=0
export R_COMPILE_PKGS=0
export R_DISABLE_BYTECODE=1
export RUNR_DIR=$("$SCRIPTS_DIR/readlink.sh" runr/inst)

[ -d "$R_LIBS" ] || mkdir -p "$R_LIBS"
