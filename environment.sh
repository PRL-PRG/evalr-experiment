R_BIN=$(readlink -m R-dyntrace/bin)

[ -d "$R_BIN" ] || {
cat <<EOM
Missing R-dyntrace in $R_BIN

Please install it using:
  git clone -b r-4.0.2 https://github.com/PRL-PRG/R-dyntrace $(dirname "$R_BIN")
  cd R-dyntrace
  ./build

EOM
return 1
}

export PATH=$R_BIN:$PATH
export R_LIBS=$(readlink -m library-local)
export R_KEEP_PKG_SOURCE=1
export R_ENABLE_JIT=0
export R_COMPILE_PKGS=0
export R_DISABLE_BYTECODE=1

[ -d "$R_LIBS" ] || mkdir -p "$R_LIBS"
[ -d $(CRAN_ZIP_DIR) ] || mkdir -p $(CRAN_ZIP_DIR)
[ -d $(CRAN_SRC_DIR) ] || mkdir -p $(CRAN_SRC_DIR)

