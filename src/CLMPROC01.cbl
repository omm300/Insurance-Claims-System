       IDENTIFICATION DIVISION.
       PROGRAM-ID. CLMPROC01.
       AUTHOR. INSURANCE-CLAIMS-SYSTEM.
       DATE-WRITTEN. 2026-10-06.
      *================================================================
      * INSURANCE CLAIMS VALIDATION AND EXCEPTION REPORTING ENGINE
      * Emulates IBM z/OS Mainframe Batch Claims Adjudication
      * DFSORT Pre-sorted Input -> DB2/VSAM Lookups -> Validation
      * -> Settlement Calculation -> Reports + Exception Log
      *================================================================

       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       REPOSITORY.
           FUNCTION ALL INTRINSIC.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
      *--- SORTED CLAIMS INPUT (FROM DFSORT PHASE) ---
           SELECT CLAIM-FILE
               ASSIGN TO WS-CLAIM-PATH
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-CL-STATUS.

      *--- POLICY MASTER REFERENCE (DB2 EMULATION) ---
           SELECT POLICY-MASTER-FILE
               ASSIGN TO WS-POLMASTER-PATH
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-PM-STATUS.

      *--- COVERAGE RATES INDEX (VSAM KSDS EMULATION) ---
           SELECT COVERAGE-FILE
               ASSIGN TO WS-COVERAGE-PATH
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-CV-STATUS.

      *--- OUTPUT: CLAIMS SETTLEMENT REPORT ---
           SELECT SETTLEMENT-FILE
               ASSIGN TO WS-SETTLE-PATH
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-ST-STATUS.

      *--- OUTPUT: PLAN SUMMARY REPORT ---
           SELECT PLAN-SUMMARY-FILE
               ASSIGN TO WS-PLANSUM-PATH
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-PS-STATUS.

      *--- OUTPUT: EXCEPTION LOG ---
           SELECT EXCEPTION-LOG-FILE
               ASSIGN TO WS-EXCLOG-PATH
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-EL-STATUS.

       DATA DIVISION.
       FILE SECTION.

      *--- CLAIM INPUT RECORD (27 BYTES) ---
       FD  CLAIM-FILE
           RECORDING MODE IS F.
       01  TC-RECORD.
           05  TC-CLAIM-ID            PIC X(6).
           05  TC-POLICY-ID           PIC X(5).
           05  TC-AMOUNT              PIC X(7).
           05  TC-AMOUNT-N REDEFINES TC-AMOUNT
                                      PIC 9(5)V99.
           05  TC-COVER-CODE          PIC X(1).
           05  TC-CLAIM-DATE          PIC X(8).

      *--- POLICY MASTER RECORD (53 BYTES) ---
       FD  POLICY-MASTER-FILE
           RECORDING MODE IS F.
       01  PM-RECORD.
           05  PM-POLICY-ID           PIC X(5).
           05  PM-HOLDER-NAME         PIC X(20).
           05  PM-PLAN-CODE           PIC X(4).
           05  PM-SUM-INSURED         PIC X(7).
           05  PM-EFF-DATE            PIC X(8).
           05  PM-EXP-DATE            PIC X(8).
           05  PM-STATUS              PIC X(1).

      *--- COVERAGE RATES RECORD (32 BYTES) ---
       FD  COVERAGE-FILE
           RECORDING MODE IS F.
       01  CV-RECORD.
           05  CV-COVER-CODE          PIC X(1).
           05  CV-PLAN-CODE           PIC X(4).
           05  CV-DESC                PIC X(12).
           05  CV-DEDUCTIBLE          PIC X(5).
           05  CV-COPAY-PCT           PIC X(3).
           05  CV-LIMIT               PIC X(7).

      *--- SETTLEMENT REPORT OUTPUT ---
       FD  SETTLEMENT-FILE
           RECORDING MODE IS F.
       01  ST-RECORD                  PIC X(132).

      *--- PLAN SUMMARY OUTPUT ---
       FD  PLAN-SUMMARY-FILE
           RECORDING MODE IS F.
       01  PS-RECORD                  PIC X(132).

      *--- EXCEPTION LOG OUTPUT ---
       FD  EXCEPTION-LOG-FILE
           RECORDING MODE IS F.
       01  EL-RECORD                  PIC X(132).

       WORKING-STORAGE SECTION.

      *--- FILE PATH VARIABLES ---
       01  WS-CLAIM-PATH              PIC X(256).
       01  WS-POLMASTER-PATH          PIC X(256).
       01  WS-COVERAGE-PATH           PIC X(256).
       01  WS-SETTLE-PATH             PIC X(256).
       01  WS-PLANSUM-PATH            PIC X(256).
       01  WS-EXCLOG-PATH             PIC X(256).

      *--- FILE STATUS CODES ---
       01  WS-CL-STATUS               PIC XX VALUE SPACES.
       01  WS-PM-STATUS               PIC XX VALUE SPACES.
       01  WS-CV-STATUS               PIC XX VALUE SPACES.
       01  WS-ST-STATUS               PIC XX VALUE SPACES.
       01  WS-PS-STATUS               PIC XX VALUE SPACES.
       01  WS-EL-STATUS               PIC XX VALUE SPACES.

      *--- EOF FLAGS ---
       01  WS-CL-EOF                  PIC X VALUE 'N'.
           88  CL-END-OF-FILE         VALUE 'Y'.
       01  WS-PM-EOF                  PIC X VALUE 'N'.
       01  WS-CV-EOF                  PIC X VALUE 'N'.

      *--- CLAIM WORKING FIELDS ---
       01  WS-CLAIM-AMT               PIC 9(5)V99 VALUE ZERO.
       01  WS-CLAIM-DATE-G.
           05  WS-CD-YYYY             PIC 9(4).
           05  WS-CD-MM               PIC 9(2).
           05  WS-CD-DD               PIC 9(2).
       01  WS-CLAIM-DATE-N REDEFINES WS-CLAIM-DATE-G
                                      PIC 9(8).

      *--- SETTLEMENT CALCULATION FIELDS ---
       01  WS-ELIGIBLE                PIC 9(7)V99 VALUE ZERO.
       01  WS-DEDUCTIBLE              PIC 9(7)V99 VALUE ZERO.
       01  WS-DEDUCT-APPLIED          PIC 9(7)V99 VALUE ZERO.
       01  WS-AFTER-DED               PIC 9(7)V99 VALUE ZERO.
       01  WS-COPAY-AMT               PIC 9(7)V99 VALUE ZERO.
       01  WS-PAYABLE                 PIC 9(7)V99 VALUE ZERO.
       01  WS-REMAINING               PIC 9(9)V99 VALUE ZERO.
       01  WS-HV-THRESHOLD            PIC 9(9)V99 VALUE ZERO.
       01  WS-CAPPED-FLAG             PIC X VALUE 'N'.
       01  WS-STATUS-CODE             PIC X(4) VALUE SPACES.
       01  WS-WARN-COUNT              PIC 9(2) VALUE ZERO.

      *--- POLICY MASTER TABLE (IN-MEMORY DB2 SIMULATION) ---
       01  WS-POLICY-TABLE.
           05  WS-POL-ENTRY OCCURS 100 TIMES.
               10  WS-PT-POLICY-ID    PIC X(5).
               10  WS-PT-NAME         PIC X(20).
               10  WS-PT-PLAN         PIC X(4).
               10  WS-PT-SUM-INS      PIC 9(7)V99.
               10  WS-PT-EFF          PIC 9(8).
               10  WS-PT-EXP          PIC 9(8).
               10  WS-PT-STATUS       PIC X(1).
               10  WS-PT-PAID         PIC 9(9)V99.
       01  WS-POL-COUNT               PIC 9(3) VALUE ZERO.

      *--- COVERAGE TABLE (IN-MEMORY VSAM SIMULATION) ---
       01  WS-COVER-TABLE.
           05  WS-COV-ENTRY OCCURS 20 TIMES.
               10  WS-CT-CODE         PIC X(1).
               10  WS-CT-PLAN         PIC X(4).
               10  WS-CT-DESC         PIC X(12).
               10  WS-CT-DEDUCT       PIC 9(5)V99.
               10  WS-CT-COPAY        PIC 9V99.
               10  WS-CT-LIMIT        PIC 9(7)V99.
       01  WS-COV-COUNT               PIC 9(2) VALUE ZERO.

      *--- SETTLED CLAIM IDS (DUPLICATE DETECTION TABLE) ---
       01  WS-SEEN-TABLE.
           05  WS-SEEN-ID OCCURS 500 TIMES PIC X(6).
       01  WS-SEEN-COUNT              PIC 9(3) VALUE ZERO.

      *--- LOOKUP RESULT FLAGS ---
       01  WS-POL-FOUND               PIC X VALUE 'N'.
       01  WS-COV-FOUND               PIC X VALUE 'N'.
       01  WS-DUP-FOUND               PIC X VALUE 'N'.
       01  WS-POL-IDX                 PIC 9(3) VALUE ZERO.
       01  WS-COV-IDX                 PIC 9(2) VALUE ZERO.

      *--- PLAN TOTALS TABLE ---
       01  WS-PLAN-TABLE.
           05  WS-PLAN-ENTRY OCCURS 20 TIMES.
               10  WS-PL-CODE         PIC X(4).
               10  WS-PL-COUNT        PIC 9(5) VALUE ZERO.
               10  WS-PL-CLAIMED      PIC 9(9)V99 VALUE ZERO.
               10  WS-PL-PAYABLE      PIC 9(9)V99 VALUE ZERO.
               10  WS-PL-NOTCOV       PIC 9(9)V99 VALUE ZERO.
       01  WS-PLAN-COUNT              PIC 9(2) VALUE ZERO.
       01  WS-PLAN-IDX                PIC 9(2) VALUE ZERO.
       01  WS-PLAN-FOUND              PIC X VALUE 'N'.

      *--- GRAND TOTALS ---
       01  WS-GRAND-CLAIMED           PIC 9(9)V99 VALUE ZERO.
       01  WS-GRAND-ELIGIBLE          PIC 9(9)V99 VALUE ZERO.
       01  WS-GRAND-DEDUCT            PIC 9(9)V99 VALUE ZERO.
       01  WS-GRAND-COPAY             PIC 9(9)V99 VALUE ZERO.
       01  WS-GRAND-PAYABLE           PIC 9(9)V99 VALUE ZERO.
       01  WS-TOTAL-RECORDS           PIC 9(5) VALUE ZERO.
       01  WS-APPROVED-RECORDS        PIC 9(5) VALUE ZERO.
       01  WS-FLAGGED-RECORDS         PIC 9(5) VALUE ZERO.
       01  WS-REJECTED-RECORDS        PIC 9(5) VALUE ZERO.

      *--- COUNTERS AND INDICES ---
       01  WS-I                       PIC 9(3) VALUE ZERO.

      *--- VALIDATION FLAGS ---
       01  WS-VALID-RECORD            PIC X VALUE 'Y'.
       01  WS-ERROR-CODE              PIC X(6) VALUE SPACES.

      *--- DATE/TIME FIELDS ---
       01  WS-CURRENT-DATE.
           05  WS-CURR-YEAR           PIC 9(4).
           05  WS-CURR-MONTH          PIC 9(2).
           05  WS-CURR-DAY            PIC 9(2).
       01  WS-CURRENT-TIME.
           05  WS-CURR-HOUR           PIC 9(2).
           05  WS-CURR-MIN            PIC 9(2).
           05  WS-CURR-SEC            PIC 9(2).
           05  WS-CURR-HUND           PIC 9(2).
       01  WS-TIMESTAMP               PIC X(19) VALUE SPACES.
       01  WS-HDR-DATE                PIC X(10) VALUE SPACES.

      *--- ERROR / WARNING MESSAGE TABLE (56 BYTES PER ENTRY) ---
       01  WS-MSG-VALUES.
           05  FILLER   PIC X(6)  VALUE 'ERR-01'.
           05  FILLER   PIC X(50) VALUE
               'INVALID FORMAT (NON-NUMERIC/ZERO AMT/BAD DATE)'.
           05  FILLER   PIC X(6)  VALUE 'ERR-02'.
           05  FILLER   PIC X(50) VALUE
               'DUPLICATE CLAIM ID ALREADY SETTLED'.
           05  FILLER   PIC X(6)  VALUE 'ERR-03'.
           05  FILLER   PIC X(50) VALUE
               'POLICY ID NOT FOUND IN MASTER TABLE'.
           05  FILLER   PIC X(6)  VALUE 'ERR-04'.
           05  FILLER   PIC X(50) VALUE
               'COVERAGE CODE NOT FOUND IN INDEX'.
           05  FILLER   PIC X(6)  VALUE 'ERR-05'.
           05  FILLER   PIC X(50) VALUE
               'COVERAGE NOT ALLOWED UNDER POLICY PLAN'.
           05  FILLER   PIC X(6)  VALUE 'ERR-06'.
           05  FILLER   PIC X(50) VALUE
               'POLICY NOT ACTIVE (LAPSED/CANCELLED)'.
           05  FILLER   PIC X(6)  VALUE 'ERR-07'.
           05  FILLER   PIC X(50) VALUE
               'CLAIM DATE OUTSIDE POLICY PERIOD'.
           05  FILLER   PIC X(6)  VALUE 'ERR-08'.
           05  FILLER   PIC X(50) VALUE
               'CLAIM EXCEEDS REMAINING SUM INSURED'.
           05  FILLER   PIC X(6)  VALUE 'WRN-01'.
           05  FILLER   PIC X(50) VALUE
               'CLAIM CAPPED AT COVERAGE PER-CLAIM LIMIT'.
           05  FILLER   PIC X(6)  VALUE 'WRN-02'.
           05  FILLER   PIC X(50) VALUE
               'HIGH VALUE CLAIM - MANUAL REVIEW REQUIRED'.
           05  FILLER   PIC X(6)  VALUE 'WRN-03'.
           05  FILLER   PIC X(50) VALUE
               'CLAIM WITHIN DEDUCTIBLE - NIL PAYOUT'.
       01  WS-MSG-TABLE REDEFINES WS-MSG-VALUES.
           05  WS-MSG-ENTRY OCCURS 11 TIMES.
               10  WS-MSG-CODE        PIC X(6).
               10  WS-MSG-TEXT        PIC X(50).

      *--- SETTLEMENT REPORT HEADER LINES ---
       01  WS-SET-HDR1.
           05  FILLER        PIC X(1)   VALUE SPACES.
           05  FILLER        PIC X(116) VALUE ALL '='.
       01  WS-SET-HDR2.
           05  FILLER        PIC X(1)   VALUE SPACES.
           05  FILLER        PIC X(60)  VALUE
               'INSURANCE CLAIMS VALIDATION - SETTLEMENT REPORT'.
       01  WS-SET-HDR3.
           05  FILLER        PIC X(1)   VALUE SPACES.
           05  FILLER        PIC X(13)  VALUE 'REPORT DATE: '.
           05  WS-HDR3-DATE  PIC X(10)  VALUE SPACES.

       01  WS-SET-COL-HDR.
           05  FILLER        PIC X(44) VALUE
               ' CLAIM#  POLICY HOLDER NAME           PLAN  '.
           05  FILLER        PIC X(44) VALUE
               'CV      CLAIMED     ELIGIBLE   DEDUCTIBLE   '.
           05  FILLER        PIC X(29) VALUE
               '    CO-PAY      PAYABLE  STAT'.

       01  WS-SET-COL-DASH.
           05  FILLER        PIC X(44) VALUE
               ' ------  -----  --------------------  ----  '.
           05  FILLER        PIC X(44) VALUE
               '-- ------------ ------------ ------------ --'.
           05  FILLER        PIC X(29) VALUE
               '---------- ------------  ----'.

      *--- SETTLEMENT DETAIL LINE ---
       01  WS-SET-DETAIL.
           05  FILLER        PIC X(1)  VALUE SPACES.
           05  WS-SD-CLAIM   PIC X(6).
           05  FILLER        PIC X(2)  VALUE SPACES.
           05  WS-SD-POLICY  PIC X(5).
           05  FILLER        PIC X(2)  VALUE SPACES.
           05  WS-SD-NAME    PIC X(20).
           05  FILLER        PIC X(2)  VALUE SPACES.
           05  WS-SD-PLAN    PIC X(4).
           05  FILLER        PIC X(2)  VALUE SPACES.
           05  WS-SD-COVER   PIC X(1).
           05  FILLER        PIC X(2)  VALUE SPACES.
           05  WS-SD-CLAIMED PIC Z,ZZZ,ZZ9.99.
           05  FILLER        PIC X(1)  VALUE SPACES.
           05  WS-SD-ELIG    PIC Z,ZZZ,ZZ9.99.
           05  FILLER        PIC X(1)  VALUE SPACES.
           05  WS-SD-DEDUCT  PIC Z,ZZZ,ZZ9.99.
           05  FILLER        PIC X(1)  VALUE SPACES.
           05  WS-SD-COPAY   PIC Z,ZZZ,ZZ9.99.
           05  FILLER        PIC X(1)  VALUE SPACES.
           05  WS-SD-PAYABLE PIC Z,ZZZ,ZZ9.99.
           05  FILLER        PIC X(2)  VALUE SPACES.
           05  WS-SD-STATUS  PIC X(4).

      *--- GRAND TOTAL LINE (SAME COLUMN LAYOUT AS DETAIL) ---
       01  WS-GRAND-LINE.
           05  FILLER        PIC X(1)  VALUE SPACES.
           05  FILLER        PIC X(45) VALUE
               'GRAND TOTALS (APPROVED CLAIMS ONLY):'.
           05  FILLER        PIC X(1)  VALUE SPACES.
           05  WS-GL-CLAIMED PIC Z,ZZZ,ZZ9.99.
           05  FILLER        PIC X(1)  VALUE SPACES.
           05  WS-GL-ELIG    PIC Z,ZZZ,ZZ9.99.
           05  FILLER        PIC X(1)  VALUE SPACES.
           05  WS-GL-DEDUCT  PIC Z,ZZZ,ZZ9.99.
           05  FILLER        PIC X(1)  VALUE SPACES.
           05  WS-GL-COPAY   PIC Z,ZZZ,ZZ9.99.
           05  FILLER        PIC X(1)  VALUE SPACES.
           05  WS-GL-PAYABLE PIC Z,ZZZ,ZZ9.99.

      *--- PLAN SUMMARY LINES ---
       01  WS-PLAN-HDR2.
           05  FILLER        PIC X(1)  VALUE SPACES.
           05  FILLER        PIC X(50) VALUE
               'PLAN-WISE CLAIMS SETTLEMENT SUMMARY'.
       01  WS-PLAN-COL-HDR.
           05  FILLER        PIC X(1)  VALUE SPACES.
           05  FILLER        PIC X(8)  VALUE 'PLAN    '.
           05  FILLER        PIC X(10) VALUE 'CLAIMS    '.
           05  FILLER        PIC X(16) VALUE 'TOTAL CLAIMED   '.
           05  FILLER        PIC X(16) VALUE 'TOTAL PAYABLE   '.
           05  FILLER        PIC X(16) VALUE 'NOT COVERED     '.

       01  WS-PLAN-DETAIL.
           05  FILLER        PIC X(1)  VALUE SPACES.
           05  WS-PD-PLAN    PIC X(4).
           05  FILLER        PIC X(4)  VALUE SPACES.
           05  WS-PD-COUNT   PIC ZZ,ZZ9.
           05  FILLER        PIC X(4)  VALUE SPACES.
           05  WS-PD-CLAIMED PIC Z,ZZZ,ZZ9.99.
           05  FILLER        PIC X(2)  VALUE SPACES.
           05  WS-PD-PAYABLE PIC Z,ZZZ,ZZ9.99.
           05  FILLER        PIC X(2)  VALUE SPACES.
           05  WS-PD-NOTCOV  PIC Z,ZZZ,ZZ9.99.

      *--- EXCEPTION LOG LINES ---
       01  WS-EXC-HDR2.
           05  FILLER        PIC X(1)  VALUE SPACES.
           05  FILLER        PIC X(60) VALUE
               'CLAIMS EXCEPTION LOG - REJECTS AND REVIEW FLAGS'.

       01  WS-EXC-DETAIL.
           05  FILLER        PIC X(1)  VALUE SPACES.
           05  WS-ED-TS      PIC X(19).
           05  FILLER        PIC X(2)  VALUE SPACES.
           05  WS-ED-RC      PIC X(6).
           05  FILLER        PIC X(2)  VALUE SPACES.
           05  WS-ED-MSG     PIC X(50).
           05  FILLER        PIC X(2)  VALUE SPACES.
           05  WS-ED-REC     PIC X(27).

      *--- TOTALS DISPLAY LINE ---
       01  WS-TOTALS-LINE             PIC X(132) VALUE SPACES.

      *--- RETURN CODE ---
       01  WS-RETURN-CODE             PIC 9(4) VALUE ZERO.

       PROCEDURE DIVISION.
      *================================================================
       0000-MAIN-CONTROL.
      *================================================================
           PERFORM 0100-INITIALIZE
           PERFORM 0150-LOAD-REFERENCE-TABLES
           PERFORM 0180-WRITE-REPORT-HEADERS
           PERFORM 0200-PROCESS-RECORDS
               UNTIL CL-END-OF-FILE
           PERFORM 0800-WRITE-TOTALS
           PERFORM 0900-TERMINATE
           STOP RUN
           .

      *================================================================
       0100-INITIALIZE.
      *================================================================
           ACCEPT WS-CURRENT-DATE FROM DATE YYYYMMDD
           ACCEPT WS-CURRENT-TIME FROM TIME

           INITIALIZE WS-TIMESTAMP
           STRING WS-CURR-YEAR '-' WS-CURR-MONTH '-'
                  WS-CURR-DAY ' ' WS-CURR-HOUR ':'
                  WS-CURR-MIN ':' WS-CURR-SEC
                  DELIMITED BY SIZE
                  INTO WS-TIMESTAMP
           END-STRING

           INITIALIZE WS-HDR-DATE
           STRING WS-CURR-YEAR '-' WS-CURR-MONTH '-'
                  WS-CURR-DAY
                  DELIMITED BY SIZE
                  INTO WS-HDR-DATE
           END-STRING
           MOVE WS-HDR-DATE TO WS-HDR3-DATE

           ACCEPT WS-CLAIM-PATH
               FROM ENVIRONMENT 'CLAIMS_FILE'
           ACCEPT WS-POLMASTER-PATH
               FROM ENVIRONMENT 'POLMASTER_FILE'
           ACCEPT WS-COVERAGE-PATH
               FROM ENVIRONMENT 'COVERAGE_FILE'
           ACCEPT WS-SETTLE-PATH
               FROM ENVIRONMENT 'SETTLE_FILE'
           ACCEPT WS-PLANSUM-PATH
               FROM ENVIRONMENT 'PLANSUM_FILE'
           ACCEPT WS-EXCLOG-PATH
               FROM ENVIRONMENT 'EXCLOG_FILE'

           OPEN INPUT  CLAIM-FILE
           IF WS-CL-STATUS NOT = '00'
               DISPLAY 'ERROR: CANNOT OPEN CLAIMS FILE. '
                   'STATUS=' WS-CL-STATUS
               MOVE 12 TO RETURN-CODE
               STOP RUN
           END-IF

           OPEN OUTPUT SETTLEMENT-FILE
           OPEN OUTPUT PLAN-SUMMARY-FILE
           OPEN OUTPUT EXCEPTION-LOG-FILE

           INITIALIZE WS-POLICY-TABLE
           INITIALIZE WS-COVER-TABLE
           INITIALIZE WS-PLAN-TABLE

           DISPLAY '================================='
               '================'
           DISPLAY ' INSURANCE CLAIMS BATCH ENGINE'
               ' - INITIALIZED'
           DISPLAY ' TIMESTAMP: ' WS-TIMESTAMP
           DISPLAY '================================='
               '================'
           .

      *================================================================
       0150-LOAD-REFERENCE-TABLES.
      *================================================================
      *--- LOAD POLICY MASTER INTO MEMORY (DB2 SIMULATION) ---
           OPEN INPUT POLICY-MASTER-FILE
           IF WS-PM-STATUS NOT = '00'
               DISPLAY 'ERROR: CANNOT OPEN POLICY '
                   'MASTER. STATUS=' WS-PM-STATUS
               MOVE 12 TO RETURN-CODE
               STOP RUN
           END-IF

           MOVE ZERO TO WS-POL-COUNT
           MOVE 'N' TO WS-PM-EOF
           PERFORM UNTIL WS-PM-EOF = 'Y'
               READ POLICY-MASTER-FILE
                   AT END
                       MOVE 'Y' TO WS-PM-EOF
                   NOT AT END
                       ADD 1 TO WS-POL-COUNT
                       MOVE PM-POLICY-ID TO
                           WS-PT-POLICY-ID(WS-POL-COUNT)
                       MOVE PM-HOLDER-NAME TO
                           WS-PT-NAME(WS-POL-COUNT)
                       MOVE PM-PLAN-CODE TO
                           WS-PT-PLAN(WS-POL-COUNT)
                       COMPUTE WS-PT-SUM-INS(WS-POL-COUNT)
                           = FUNCTION NUMVAL(PM-SUM-INSURED)
                       COMPUTE WS-PT-EFF(WS-POL-COUNT)
                           = FUNCTION NUMVAL(PM-EFF-DATE)
                       COMPUTE WS-PT-EXP(WS-POL-COUNT)
                           = FUNCTION NUMVAL(PM-EXP-DATE)
                       MOVE PM-STATUS TO
                           WS-PT-STATUS(WS-POL-COUNT)
               END-READ
           END-PERFORM
           CLOSE POLICY-MASTER-FILE
           DISPLAY '  POLICY MASTER LOADED: '
               WS-POL-COUNT ' RECORDS'

      *--- LOAD COVERAGE RATES INTO MEMORY (VSAM SIMULATION) ---
           OPEN INPUT COVERAGE-FILE
           IF WS-CV-STATUS NOT = '00'
               DISPLAY 'ERROR: CANNOT OPEN COVERAGE INDEX. '
                   'STATUS=' WS-CV-STATUS
               MOVE 12 TO RETURN-CODE
               STOP RUN
           END-IF

           MOVE ZERO TO WS-COV-COUNT
           MOVE 'N' TO WS-CV-EOF
           PERFORM UNTIL WS-CV-EOF = 'Y'
               READ COVERAGE-FILE
                   AT END
                       MOVE 'Y' TO WS-CV-EOF
                   NOT AT END
                       ADD 1 TO WS-COV-COUNT
                       MOVE CV-COVER-CODE TO
                           WS-CT-CODE(WS-COV-COUNT)
                       MOVE CV-PLAN-CODE TO
                           WS-CT-PLAN(WS-COV-COUNT)
                       MOVE CV-DESC TO
                           WS-CT-DESC(WS-COV-COUNT)
                       COMPUTE WS-CT-DEDUCT(WS-COV-COUNT)
                           = FUNCTION NUMVAL(CV-DEDUCTIBLE)
                       COMPUTE WS-CT-COPAY(WS-COV-COUNT)
                           = FUNCTION NUMVAL(CV-COPAY-PCT) / 100
                       COMPUTE WS-CT-LIMIT(WS-COV-COUNT)
                           = FUNCTION NUMVAL(CV-LIMIT)
               END-READ
           END-PERFORM
           CLOSE COVERAGE-FILE
           DISPLAY '  COVERAGE INDEX LOADED: '
               WS-COV-COUNT ' COVER CODES'
           .

      *================================================================
       0180-WRITE-REPORT-HEADERS.
      *================================================================
           WRITE ST-RECORD FROM WS-SET-HDR1
           END-WRITE
           WRITE ST-RECORD FROM WS-SET-HDR2
           END-WRITE
           WRITE ST-RECORD FROM WS-SET-HDR3
           END-WRITE
           WRITE ST-RECORD FROM WS-SET-HDR1
           END-WRITE
           WRITE ST-RECORD FROM WS-SET-COL-HDR
           END-WRITE
           WRITE ST-RECORD FROM WS-SET-COL-DASH
           END-WRITE

           WRITE EL-RECORD FROM WS-SET-HDR1
           END-WRITE
           WRITE EL-RECORD FROM WS-EXC-HDR2
           END-WRITE
           WRITE EL-RECORD FROM WS-SET-HDR1
           END-WRITE
           MOVE SPACES TO EL-RECORD
           STRING ' TIMESTAMP           '
                  'RC      '
                  'DESCRIPTION'
                  '                                         '
                  'RAW RECORD'
                  DELIMITED BY SIZE INTO EL-RECORD
           END-STRING
           WRITE EL-RECORD
           END-WRITE
           MOVE SPACES TO EL-RECORD
           MOVE ALL '-' TO EL-RECORD
           WRITE EL-RECORD
           END-WRITE
           .

      *================================================================
       0200-PROCESS-RECORDS.
      *================================================================
           READ CLAIM-FILE
               AT END
                   MOVE 'Y' TO WS-CL-EOF
               NOT AT END
                   ADD 1 TO WS-TOTAL-RECORDS
                   MOVE 'Y' TO WS-VALID-RECORD
                   MOVE SPACES TO WS-ERROR-CODE

                   PERFORM 0250-VALIDATE-RECORD

                   IF WS-VALID-RECORD = 'Y'
                       PERFORM 0300-CALCULATE
                       PERFORM 0400-WRITE-SETTLEMENT
                       PERFORM 0500-UPDATE-PLAN-TOTALS
                       ADD 1 TO WS-APPROVED-RECORDS
                       IF WS-WARN-COUNT > ZERO
                           ADD 1 TO WS-FLAGGED-RECORDS
                       END-IF
                   ELSE
                       ADD 1 TO WS-REJECTED-RECORDS
                   END-IF
           END-READ
           .

      *================================================================
       0250-VALIDATE-RECORD.
      *================================================================
           MOVE 'N' TO WS-CAPPED-FLAG

      *--- GATE 1: FORMAT (NUMERIC IDS/AMOUNT/DATE, AMOUNT > 0) ---
           IF TC-CLAIM-ID IS NOT NUMERIC
              OR TC-POLICY-ID IS NOT NUMERIC
              OR TC-AMOUNT IS NOT NUMERIC
              OR TC-CLAIM-DATE IS NOT NUMERIC
               MOVE 'N' TO WS-VALID-RECORD
               MOVE 'ERR-01' TO WS-ERROR-CODE
               PERFORM 0700-WRITE-EXCEPTION
               EXIT PARAGRAPH
           END-IF

           MOVE TC-AMOUNT-N TO WS-CLAIM-AMT
           MOVE TC-CLAIM-DATE TO WS-CLAIM-DATE-N
           IF WS-CLAIM-AMT <= ZERO
              OR WS-CD-YYYY < 1900
              OR WS-CD-MM < 1 OR WS-CD-MM > 12
              OR WS-CD-DD < 1 OR WS-CD-DD > 31
               MOVE 'N' TO WS-VALID-RECORD
               MOVE 'ERR-01' TO WS-ERROR-CODE
               PERFORM 0700-WRITE-EXCEPTION
               EXIT PARAGRAPH
           END-IF

      *--- GATE 2: DUPLICATE CLAIM ID ---
           MOVE 'N' TO WS-DUP-FOUND
           PERFORM VARYING WS-I FROM 1 BY 1
               UNTIL WS-I > WS-SEEN-COUNT
                  OR WS-DUP-FOUND = 'Y'
               IF TC-CLAIM-ID = WS-SEEN-ID(WS-I)
                   MOVE 'Y' TO WS-DUP-FOUND
               END-IF
           END-PERFORM

           IF WS-DUP-FOUND = 'Y'
               MOVE 'N' TO WS-VALID-RECORD
               MOVE 'ERR-02' TO WS-ERROR-CODE
               PERFORM 0700-WRITE-EXCEPTION
               EXIT PARAGRAPH
           END-IF

      *--- GATE 3: POLICY EXISTS IN MASTER ---
           MOVE 'N' TO WS-POL-FOUND
           MOVE ZERO TO WS-POL-IDX
           PERFORM VARYING WS-I FROM 1 BY 1
               UNTIL WS-I > WS-POL-COUNT
                  OR WS-POL-FOUND = 'Y'
               IF TC-POLICY-ID = WS-PT-POLICY-ID(WS-I)
                   MOVE 'Y' TO WS-POL-FOUND
                   MOVE WS-I TO WS-POL-IDX
               END-IF
           END-PERFORM

           IF WS-POL-FOUND = 'N'
               MOVE 'N' TO WS-VALID-RECORD
               MOVE 'ERR-03' TO WS-ERROR-CODE
               PERFORM 0700-WRITE-EXCEPTION
               EXIT PARAGRAPH
           END-IF

      *--- GATE 4: COVERAGE CODE EXISTS IN INDEX ---
           MOVE 'N' TO WS-COV-FOUND
           MOVE ZERO TO WS-COV-IDX
           PERFORM VARYING WS-I FROM 1 BY 1
               UNTIL WS-I > WS-COV-COUNT
                  OR WS-COV-FOUND = 'Y'
               IF TC-COVER-CODE = WS-CT-CODE(WS-I)
                   MOVE 'Y' TO WS-COV-FOUND
                   MOVE WS-I TO WS-COV-IDX
               END-IF
           END-PERFORM

           IF WS-COV-FOUND = 'N'
               MOVE 'N' TO WS-VALID-RECORD
               MOVE 'ERR-04' TO WS-ERROR-CODE
               PERFORM 0700-WRITE-EXCEPTION
               EXIT PARAGRAPH
           END-IF

      *--- GATE 5: COVERAGE BELONGS TO THE POLICY PLAN ---
           IF WS-CT-PLAN(WS-COV-IDX) NOT =
              WS-PT-PLAN(WS-POL-IDX)
               MOVE 'N' TO WS-VALID-RECORD
               MOVE 'ERR-05' TO WS-ERROR-CODE
               PERFORM 0700-WRITE-EXCEPTION
               EXIT PARAGRAPH
           END-IF

      *--- GATE 6: POLICY STATUS MUST BE ACTIVE ---
           IF WS-PT-STATUS(WS-POL-IDX) NOT = 'A'
               MOVE 'N' TO WS-VALID-RECORD
               MOVE 'ERR-06' TO WS-ERROR-CODE
               PERFORM 0700-WRITE-EXCEPTION
               EXIT PARAGRAPH
           END-IF

      *--- GATE 7: CLAIM DATE WITHIN POLICY PERIOD ---
           IF WS-CLAIM-DATE-N < WS-PT-EFF(WS-POL-IDX)
              OR WS-CLAIM-DATE-N > WS-PT-EXP(WS-POL-IDX)
               MOVE 'N' TO WS-VALID-RECORD
               MOVE 'ERR-07' TO WS-ERROR-CODE
               PERFORM 0700-WRITE-EXCEPTION
               EXIT PARAGRAPH
           END-IF

      *--- GATE 8: ELIGIBLE AMOUNT WITHIN REMAINING SUM INSURED ---
           IF WS-CLAIM-AMT > WS-CT-LIMIT(WS-COV-IDX)
               MOVE WS-CT-LIMIT(WS-COV-IDX) TO WS-ELIGIBLE
               MOVE 'Y' TO WS-CAPPED-FLAG
           ELSE
               MOVE WS-CLAIM-AMT TO WS-ELIGIBLE
           END-IF

           COMPUTE WS-REMAINING =
               WS-PT-SUM-INS(WS-POL-IDX)
               - WS-PT-PAID(WS-POL-IDX)

           IF WS-ELIGIBLE > WS-REMAINING
               MOVE 'N' TO WS-VALID-RECORD
               MOVE 'ERR-08' TO WS-ERROR-CODE
               PERFORM 0700-WRITE-EXCEPTION
               EXIT PARAGRAPH
           END-IF

      *--- ALL GATES PASSED: REGISTER CLAIM ID ---
           ADD 1 TO WS-SEEN-COUNT
           MOVE TC-CLAIM-ID TO WS-SEEN-ID(WS-SEEN-COUNT)
           .

      *================================================================
       0300-CALCULATE.
      *================================================================
      *--- DEDUCTIBLE APPLIED = MIN(ELIGIBLE, DEDUCTIBLE) ---
           MOVE WS-CT-DEDUCT(WS-COV-IDX) TO WS-DEDUCTIBLE
           IF WS-ELIGIBLE > WS-DEDUCTIBLE
               MOVE WS-DEDUCTIBLE TO WS-DEDUCT-APPLIED
               COMPUTE WS-AFTER-DED =
                   WS-ELIGIBLE - WS-DEDUCTIBLE
           ELSE
               MOVE WS-ELIGIBLE TO WS-DEDUCT-APPLIED
               MOVE ZERO TO WS-AFTER-DED
           END-IF

      *--- CO-PAY (POLICYHOLDER SHARE) AND INSURER PAYABLE ---
           COMPUTE WS-COPAY-AMT ROUNDED =
               WS-AFTER-DED * WS-CT-COPAY(WS-COV-IDX)
           COMPUTE WS-PAYABLE =
               WS-AFTER-DED - WS-COPAY-AMT

      *--- REVIEW FLAGS (WARNINGS - CLAIM STILL SETTLED) ---
           MOVE 'APPR' TO WS-STATUS-CODE
           MOVE ZERO TO WS-WARN-COUNT
           COMPUTE WS-HV-THRESHOLD =
               WS-PT-SUM-INS(WS-POL-IDX) * 0.50

           IF WS-CAPPED-FLAG = 'Y'
               MOVE 'CAPD' TO WS-STATUS-CODE
               MOVE 'WRN-01' TO WS-ERROR-CODE
               PERFORM 0710-WRITE-WARNING
           END-IF

           IF WS-ELIGIBLE >= WS-HV-THRESHOLD
               MOVE 'REVW' TO WS-STATUS-CODE
               MOVE 'WRN-02' TO WS-ERROR-CODE
               PERFORM 0710-WRITE-WARNING
           END-IF

           IF WS-PAYABLE = ZERO
               IF WS-STATUS-CODE = 'APPR'
                   MOVE 'NIL ' TO WS-STATUS-CODE
               END-IF
               MOVE 'WRN-03' TO WS-ERROR-CODE
               PERFORM 0710-WRITE-WARNING
           END-IF

      *--- UPDATE POLICY UTILISATION AND GRAND TOTALS ---
           ADD WS-PAYABLE TO WS-PT-PAID(WS-POL-IDX)
           ADD WS-CLAIM-AMT TO WS-GRAND-CLAIMED
           ADD WS-ELIGIBLE TO WS-GRAND-ELIGIBLE
           ADD WS-DEDUCT-APPLIED TO WS-GRAND-DEDUCT
           ADD WS-COPAY-AMT TO WS-GRAND-COPAY
           ADD WS-PAYABLE TO WS-GRAND-PAYABLE
           .

      *================================================================
       0400-WRITE-SETTLEMENT.
      *================================================================
           INITIALIZE WS-SET-DETAIL
           MOVE TC-CLAIM-ID TO WS-SD-CLAIM
           MOVE TC-POLICY-ID TO WS-SD-POLICY
           MOVE WS-PT-NAME(WS-POL-IDX) TO WS-SD-NAME
           MOVE WS-PT-PLAN(WS-POL-IDX) TO WS-SD-PLAN
           MOVE TC-COVER-CODE TO WS-SD-COVER
           MOVE WS-CLAIM-AMT TO WS-SD-CLAIMED
           MOVE WS-ELIGIBLE TO WS-SD-ELIG
           MOVE WS-DEDUCT-APPLIED TO WS-SD-DEDUCT
           MOVE WS-COPAY-AMT TO WS-SD-COPAY
           MOVE WS-PAYABLE TO WS-SD-PAYABLE
           MOVE WS-STATUS-CODE TO WS-SD-STATUS

           WRITE ST-RECORD FROM WS-SET-DETAIL
           END-WRITE
           .

      *================================================================
       0500-UPDATE-PLAN-TOTALS.
      *================================================================
           MOVE 'N' TO WS-PLAN-FOUND

           PERFORM VARYING WS-I FROM 1 BY 1
               UNTIL WS-I > WS-PLAN-COUNT
                  OR WS-PLAN-FOUND = 'Y'
               IF WS-PT-PLAN(WS-POL-IDX) =
                   WS-PL-CODE(WS-I)
                   MOVE 'Y' TO WS-PLAN-FOUND
                   MOVE WS-I TO WS-PLAN-IDX
               END-IF
           END-PERFORM

           IF WS-PLAN-FOUND = 'N'
               ADD 1 TO WS-PLAN-COUNT
               MOVE WS-PLAN-COUNT TO WS-PLAN-IDX
               MOVE WS-PT-PLAN(WS-POL-IDX) TO
                   WS-PL-CODE(WS-PLAN-IDX)
           END-IF

           ADD 1 TO WS-PL-COUNT(WS-PLAN-IDX)
           ADD WS-CLAIM-AMT TO WS-PL-CLAIMED(WS-PLAN-IDX)
           ADD WS-PAYABLE TO WS-PL-PAYABLE(WS-PLAN-IDX)
           COMPUTE WS-PL-NOTCOV(WS-PLAN-IDX) =
               WS-PL-NOTCOV(WS-PLAN-IDX)
               + WS-CLAIM-AMT - WS-PAYABLE
           .

      *================================================================
       0700-WRITE-EXCEPTION.
      *================================================================
           INITIALIZE WS-EXC-DETAIL
           MOVE WS-TIMESTAMP TO WS-ED-TS
           MOVE WS-ERROR-CODE TO WS-ED-RC
           MOVE TC-RECORD TO WS-ED-REC
           PERFORM 0720-LOOKUP-MESSAGE

           WRITE EL-RECORD FROM WS-EXC-DETAIL
           END-WRITE

           DISPLAY '  ** REJECTED:  '
               WS-ERROR-CODE
               ' RECORD=[' TC-RECORD ']'
           END-DISPLAY
           .

      *================================================================
       0710-WRITE-WARNING.
      *================================================================
           ADD 1 TO WS-WARN-COUNT
           INITIALIZE WS-EXC-DETAIL
           MOVE WS-TIMESTAMP TO WS-ED-TS
           MOVE WS-ERROR-CODE TO WS-ED-RC
           MOVE TC-RECORD TO WS-ED-REC
           PERFORM 0720-LOOKUP-MESSAGE

           WRITE EL-RECORD FROM WS-EXC-DETAIL
           END-WRITE

           DISPLAY '  ** FLAGGED:   '
               WS-ERROR-CODE
               ' RECORD=[' TC-RECORD ']'
           END-DISPLAY
           .

      *================================================================
       0720-LOOKUP-MESSAGE.
      *================================================================
           MOVE 'UNKNOWN ERROR CONDITION' TO WS-ED-MSG
           PERFORM VARYING WS-I FROM 1 BY 1
               UNTIL WS-I > 11
               IF WS-ERROR-CODE = WS-MSG-CODE(WS-I)
                   MOVE WS-MSG-TEXT(WS-I) TO WS-ED-MSG
               END-IF
           END-PERFORM
           .

      *================================================================
       0800-WRITE-TOTALS.
      *================================================================
      *--- WRITE SETTLEMENT GRAND TOTALS ---
           MOVE SPACES TO ST-RECORD
           MOVE ALL '-' TO ST-RECORD
           WRITE ST-RECORD
           END-WRITE

           MOVE WS-GRAND-CLAIMED TO WS-GL-CLAIMED
           MOVE WS-GRAND-ELIGIBLE TO WS-GL-ELIG
           MOVE WS-GRAND-DEDUCT TO WS-GL-DEDUCT
           MOVE WS-GRAND-COPAY TO WS-GL-COPAY
           MOVE WS-GRAND-PAYABLE TO WS-GL-PAYABLE
           WRITE ST-RECORD FROM WS-GRAND-LINE
           END-WRITE

           MOVE SPACES TO WS-TOTALS-LINE
           STRING ' TOTAL CLAIMS PROCESSED: '
                  WS-TOTAL-RECORDS
                  DELIMITED BY SIZE
                  INTO WS-TOTALS-LINE
           END-STRING
           WRITE ST-RECORD FROM WS-TOTALS-LINE
           END-WRITE

           MOVE SPACES TO WS-TOTALS-LINE
           STRING '   APPROVED: '
                  WS-APPROVED-RECORDS
                  DELIMITED BY SIZE
                  INTO WS-TOTALS-LINE
           END-STRING
           WRITE ST-RECORD FROM WS-TOTALS-LINE
           END-WRITE

           MOVE SPACES TO WS-TOTALS-LINE
           STRING '   FLAGGED:  '
                  WS-FLAGGED-RECORDS
                  DELIMITED BY SIZE
                  INTO WS-TOTALS-LINE
           END-STRING
           WRITE ST-RECORD FROM WS-TOTALS-LINE
           END-WRITE

           MOVE SPACES TO WS-TOTALS-LINE
           STRING '   REJECTED: '
                  WS-REJECTED-RECORDS
                  DELIMITED BY SIZE
                  INTO WS-TOTALS-LINE
           END-STRING
           WRITE ST-RECORD FROM WS-TOTALS-LINE
           END-WRITE

      *--- WRITE PLAN SUMMARY REPORT ---
           WRITE PS-RECORD FROM WS-SET-HDR1
           END-WRITE
           WRITE PS-RECORD FROM WS-PLAN-HDR2
           END-WRITE
           MOVE SPACES TO PS-RECORD
           STRING ' REPORT DATE: ' WS-HDR-DATE
                  DELIMITED BY SIZE INTO PS-RECORD
           END-STRING
           WRITE PS-RECORD
           END-WRITE
           WRITE PS-RECORD FROM WS-SET-HDR1
           END-WRITE
           WRITE PS-RECORD FROM WS-PLAN-COL-HDR
           END-WRITE
           MOVE SPACES TO PS-RECORD
           MOVE ALL '-' TO PS-RECORD
           WRITE PS-RECORD
           END-WRITE

           PERFORM VARYING WS-I FROM 1 BY 1
               UNTIL WS-I > WS-PLAN-COUNT
               INITIALIZE WS-PLAN-DETAIL
               MOVE WS-PL-CODE(WS-I) TO WS-PD-PLAN
               MOVE WS-PL-COUNT(WS-I) TO WS-PD-COUNT
               MOVE WS-PL-CLAIMED(WS-I) TO WS-PD-CLAIMED
               MOVE WS-PL-PAYABLE(WS-I) TO WS-PD-PAYABLE
               MOVE WS-PL-NOTCOV(WS-I) TO WS-PD-NOTCOV
               WRITE PS-RECORD FROM WS-PLAN-DETAIL
               END-WRITE
           END-PERFORM

           MOVE SPACES TO PS-RECORD
           MOVE ALL '=' TO PS-RECORD
           WRITE PS-RECORD
           END-WRITE
           .

      *================================================================
       0900-TERMINATE.
      *================================================================
           CLOSE CLAIM-FILE
           CLOSE SETTLEMENT-FILE
           CLOSE PLAN-SUMMARY-FILE
           CLOSE EXCEPTION-LOG-FILE

      *--- RC 0000 = CLEAN RUN, RC 0004 = REJECTS/FLAGS WRITTEN ---
           IF WS-REJECTED-RECORDS > ZERO
              OR WS-FLAGGED-RECORDS > ZERO
               MOVE 4 TO WS-RETURN-CODE
           END-IF

           DISPLAY '================================='
               '================'
           DISPLAY ' CLAIMS BATCH PROCESSING'
               ' COMPLETE'
           DISPLAY ' TOTAL CLAIMS  : '
               WS-TOTAL-RECORDS
           DISPLAY ' APPROVED      : '
               WS-APPROVED-RECORDS
           DISPLAY ' FLAGGED       : '
               WS-FLAGGED-RECORDS
           DISPLAY ' REJECTED      : '
               WS-REJECTED-RECORDS
           DISPLAY ' RETURN CODE   : RC='
               WS-RETURN-CODE
           DISPLAY '================================='
               '================'

           MOVE WS-RETURN-CODE TO RETURN-CODE
           .
