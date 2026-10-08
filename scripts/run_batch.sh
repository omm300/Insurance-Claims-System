#!/bin/bash
#=====================================================================
# JCL EMULATION SCRIPT - INSURANCE CLAIMS VALIDATION BATCH
# Emulates IBM z/OS JCL Job Steps on Linux/WSL via GnuCOBOL
#=====================================================================
# //CLMPROC JOB CLASS=A,MSGCLASS=X,MSGLEVEL=(1,1)
#=====================================================================

echo "========================================================="
echo " JOB: CLMPROC01 - INSURANCE CLAIMS VALIDATION ENGINE"
echo " JOBCLASS: A   MSGCLASS: X   MSGLEVEL: (1,1)"
echo " SUBMITTED: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================================="
echo ""

# --- Resolve base directory ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Dataset Directory Assignments (DD Emulation) ---
INPUT_DIR="$BASE_DIR/data/input"
REF_DIR="$BASE_DIR/data/ref"
WORK_DIR="$BASE_DIR/data/work"
OUTPUT_DIR="$BASE_DIR/data/output"
SRC_DIR="$BASE_DIR/src"
mkdir -p "$WORK_DIR" "$OUTPUT_DIR"

RC=0

#=====================================================================
# STEP01: VERIFY COMPILER (IEFBR14 EQUIVALENT)
#=====================================================================
echo "//STEP01  EXEC PGM=IEFBR14,PARM='VERIFY COMPILER'"
echo "-----------------------------------------------------------"

if ! command -v cobc &> /dev/null; then
    echo "** ABEND: GnuCOBOL compiler (cobc) not found!"
    echo "   Install with: sudo apt-get install gnucobol"
    echo "   STEP01 RC=0012"
    exit 12
fi

echo "  COMPILER: $(cobc --version | head -1)"
echo "  STEP01 RC=0000"
echo ""

#=====================================================================
# STEP02: DFSORT EMULATION - SORT CLAIMS BY POLICY-ID (COLS 7-11)
#=====================================================================
echo "//STEP02  EXEC PGM=DFSORT"
echo "//SORTIN   DD DSN=DATA.INPUT.CLAIMS,DISP=SHR"
echo "//SORTOUT  DD DSN=DATA.WORK.SORTED,DISP=(NEW,CATLG)"
echo "//SYSIN    DD *"
echo "  SORT FIELDS=(7,5,CH,A),EQUALS"
echo "/*"
echo "-----------------------------------------------------------"

if [ ! -f "$INPUT_DIR/raw_claims.dat" ]; then
    echo "** ABEND: Input dataset DATA.INPUT.CLAIMS not found!"
    echo "  STEP02 RC=0008"
    exit 8
fi

# Normalise Windows line endings
sed -i 's/\r$//' "$INPUT_DIR/raw_claims.dat"

# Stable sort on columns 7-11 (EQUALS keeps original order of ties)
LC_ALL=C sort -s -k1.7,1.11 "$INPUT_DIR/raw_claims.dat" > "$WORK_DIR/sorted_claims.dat"

echo "  RECORDS SORTED: $(wc -l < "$WORK_DIR/sorted_claims.dat")"
echo "  OUTPUT: $WORK_DIR/sorted_claims.dat"
echo "  STEP02 RC=0000"
echo ""

#=====================================================================
# STEP03: COMPILE COBOL SOURCE (IKFCBL00 EMULATION)
#=====================================================================
echo "//STEP03  EXEC PGM=IKFCBL00,PARM='COMPILE'"
echo "//SYSIN    DD DSN=SRC.CLMPROC01.CBL,DISP=SHR"
echo "//SYSLIN   DD DSN=LOAD.CLMPROC01,DISP=(NEW,CATLG)"
echo "-----------------------------------------------------------"

sed -i 's/\r$//' "$SRC_DIR/CLMPROC01.cbl"
sed -i 's/\r$//' "$REF_DIR/policy_master.dat"
sed -i 's/\r$//' "$REF_DIR/coverage_rates_index.dat"

rm -f "$BASE_DIR/CLMPROC01"
cobc -x -o "$BASE_DIR/CLMPROC01" -Wno-obsolete -Wno-terminator \
     "$SRC_DIR/CLMPROC01.cbl" 2>&1

if [ ! -f "$BASE_DIR/CLMPROC01" ]; then
    echo "** ABEND: COMPILATION FAILED - NO OUTPUT BINARY"
    echo "  STEP03 RC=0012"
    exit 12
fi

echo "  COMPILATION SUCCESSFUL"
echo "  LOAD MODULE: $BASE_DIR/CLMPROC01"
echo "  STEP03 RC=0000"
echo ""

#=====================================================================
# STEP04: EXECUTE CLAIMS ENGINE (PGM=CLMPROC01)
#=====================================================================
echo "//STEP04  EXEC PGM=CLMPROC01"
echo "//CLAIMS   DD DSN=DATA.WORK.SORTED,DISP=SHR"
echo "//POLMASTR DD DSN=DATA.REF.POLICY.MASTER,DISP=SHR"
echo "//COVINDEX DD DSN=DATA.REF.COVERAGE.RATES,DISP=SHR"
echo "//SETTLE   DD DSN=DATA.OUTPUT.SETTLEMENT,DISP=(NEW,CATLG)"
echo "//PLANSUM  DD DSN=DATA.OUTPUT.PLANSUM,DISP=(NEW,CATLG)"
echo "//EXCLOG   DD DSN=DATA.OUTPUT.EXCLOG,DISP=(NEW,CATLG)"
echo "//SYSOUT   DD SYSOUT=A"
echo "-----------------------------------------------------------"

export CLAIMS_FILE="$WORK_DIR/sorted_claims.dat"
export POLMASTER_FILE="$REF_DIR/policy_master.dat"
export COVERAGE_FILE="$REF_DIR/coverage_rates_index.dat"
export SETTLE_FILE="$OUTPUT_DIR/CLAIMS_SETTLEMENT_REPORT.txt"
export PLANSUM_FILE="$OUTPUT_DIR/PLAN_CLAIMS_SUMMARY.txt"
export EXCLOG_FILE="$OUTPUT_DIR/CLAIMS_EXCEPTION_LOG.txt"

"$BASE_DIR/CLMPROC01"
EXEC_RC=$?

echo ""
if [ $EXEC_RC -ge 8 ]; then
    echo "  ** ABEND: CLMPROC01 returned RC=$EXEC_RC"
elif [ $EXEC_RC -ne 0 ]; then
    echo "  ** NOTE: CLMPROC01 completed with exceptions (RC=$EXEC_RC)"
fi
RC=$EXEC_RC
echo "  STEP04 RC=$(printf '%04d' $EXEC_RC)"
echo ""

#=====================================================================
# STEP05: VERIFY OUTPUTS (IEBGENER EQUIVALENT)
#=====================================================================
echo "//STEP05  EXEC PGM=IEBGENER,PARM='VERIFY'"
echo "-----------------------------------------------------------"

VERIFY_OK=true
for OUTFILE in CLAIMS_SETTLEMENT_REPORT.txt PLAN_CLAIMS_SUMMARY.txt CLAIMS_EXCEPTION_LOG.txt; do
    if [ -f "$OUTPUT_DIR/$OUTFILE" ]; then
        LINES=$(wc -l < "$OUTPUT_DIR/$OUTFILE")
        SIZE=$(stat --format="%s" "$OUTPUT_DIR/$OUTFILE" 2>/dev/null)
        echo "  DATASET: $OUTFILE  RECORDS=$LINES  BYTES=$SIZE  STATUS=OK"
    else
        echo "  DATASET: $OUTFILE  STATUS=MISSING"
        VERIFY_OK=false
    fi
done

if [ "$VERIFY_OK" = true ]; then
    echo "  STEP05 RC=0000"
else
    echo "  STEP05 RC=0008"
    [ $RC -lt 8 ] && RC=8
fi
echo ""

#=====================================================================
# SYSOUT DISPLAY - PRINT GENERATED REPORTS
#=====================================================================
echo "========================================================="
echo " SYSOUT CLASS A - REPORT OUTPUT LISTING"
echo "========================================================="
for F in CLAIMS_SETTLEMENT_REPORT.txt PLAN_CLAIMS_SUMMARY.txt CLAIMS_EXCEPTION_LOG.txt; do
    echo ""
    echo "--- $F ---"
    echo ""
    cat "$OUTPUT_DIR/$F" 2>/dev/null
done
echo ""

#=====================================================================
# JOB COMPLETION  (RC 0000 clean | 0004 exceptions | 0008+ failure)
#=====================================================================
echo "========================================================="
echo " JOB CLMPROC01 COMPLETED"
echo " MAXIMUM RETURN CODE: RC=$(printf '%04d' $RC)"
echo " ENDED: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================================="

exit $RC
