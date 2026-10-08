"""
Insurance Claims Validation & Exception Reporting System — Web Dashboard
Flask server linking the COBOL batch engine (CLMPROC01) to a browser UI.
"""

import os
import subprocess
from datetime import datetime
from decimal import Decimal, ROUND_HALF_UP

from flask import Flask, render_template, jsonify, request

app = Flask(__name__, template_folder='templates', static_folder='static')

PROJECT_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.join(PROJECT_DIR, 'data')
WSL_DISTRO = os.environ.get('WSL_DISTRO', 'Ubuntu')

SETTLEMENT = 'CLAIMS_SETTLEMENT_REPORT.txt'
PLAN_SUMMARY = 'PLAN_CLAIMS_SUMMARY.txt'
EXCEPTION_LOG = 'CLAIMS_EXCEPTION_LOG.txt'

ERROR_TEXT = {
    'ERR-01': 'Invalid format (non-numeric / zero amount / bad date)',
    'ERR-02': 'Duplicate claim ID already settled',
    'ERR-03': 'Policy ID not found in master table',
    'ERR-04': 'Coverage code not found in index',
    'ERR-05': 'Coverage not allowed under policy plan',
    'ERR-06': 'Policy not active (lapsed / cancelled)',
    'ERR-07': 'Claim date outside policy period',
    'ERR-08': 'Claim exceeds remaining sum insured',
    'WRN-01': 'Claim capped at coverage per-claim limit',
    'WRN-02': 'High value claim - manual review required',
    'WRN-03': 'Claim within deductible - nil payout',
}


# ----------------------------------------------------------------------
# File helpers
# ----------------------------------------------------------------------
def read_file_lines(filepath):
    try:
        with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
            return [ln.rstrip('\r\n') for ln in f.readlines() if ln.strip()]
    except FileNotFoundError:
        return []


def read_report(filename):
    try:
        with open(os.path.join(DATA_DIR, 'output', filename), 'r',
                  encoding='utf-8', errors='replace') as f:
            return f.read()
    except FileNotFoundError:
        return None


def get_report_time(filename):
    try:
        mtime = os.path.getmtime(os.path.join(DATA_DIR, 'output', filename))
        return datetime.fromtimestamp(mtime).strftime('%Y-%m-%d %H:%M:%S')
    except FileNotFoundError:
        return None


def money(text):
    return float(text.replace(',', '').strip() or 0)


# ----------------------------------------------------------------------
# Input / reference parsers (fixed-width)
# ----------------------------------------------------------------------
def parse_policies():
    """policy_master.dat (53 bytes): ID5 NAME20 PLAN4 SUM7 EFF8 EXP8 STATUS1"""
    out = []
    for ln in read_file_lines(os.path.join(DATA_DIR, 'ref', 'policy_master.dat')):
        if len(ln) >= 52:
            out.append({
                'id': ln[0:5], 'name': ln[5:25].strip(), 'plan': ln[25:29],
                'sum_insured': int(ln[29:36]), 'eff': ln[36:44],
                'exp': ln[44:52], 'status': ln[52:53] if len(ln) > 52 else ' ',
            })
    return out


def parse_coverages():
    """coverage_rates_index.dat (32 bytes): CODE1 PLAN4 DESC12 DED5 COPAY3 LIMIT7"""
    out = []
    for ln in read_file_lines(os.path.join(DATA_DIR, 'ref', 'coverage_rates_index.dat')):
        if len(ln) >= 32:
            out.append({
                'code': ln[0], 'plan': ln[1:5], 'desc': ln[5:17].strip(),
                'deductible': int(ln[17:22]), 'copay': int(ln[22:25]),
                'limit': int(ln[25:32]),
            })
    return out


def parse_claims():
    """raw_claims.dat (27 bytes): CLAIM6 POLICY5 AMT7(v99) COVER1 DATE8"""
    out = []
    for ln in read_file_lines(os.path.join(DATA_DIR, 'input', 'raw_claims.dat')):
        if len(ln) >= 27:
            raw_amt = ln[11:18]
            try:
                amt = f"{int(raw_amt) / 100:.2f}"
            except ValueError:
                amt = raw_amt
            out.append({'claim_id': ln[0:6], 'policy_id': ln[6:11],
                        'amount': amt, 'cover': ln[18], 'date': ln[19:27],
                        'raw': ln[:27]})
    return out


# ----------------------------------------------------------------------
# Pre-flight validator: mirrors CLMPROC01 gates 1-8 (processes in the
# same DFSORT order: stable sort on policy id) so the Input tab can
# preview the outcome before the batch is submitted.
# ----------------------------------------------------------------------
def preflight(claims, policies, coverages):
    pol = {p['id']: p for p in policies}
    cov = {c['code']: c for c in coverages}
    paid = {p['id']: Decimal('0') for p in policies}
    seen = set()
    result = {}
    order = sorted(range(len(claims)), key=lambda i: claims[i]['policy_id'])
    for i in order:
        c = claims[i]
        result[i] = _check(c, pol, cov, paid, seen)
    return [result[i] for i in range(len(claims))]


def _check(c, pol, cov, paid, seen):
    D = Decimal
    cid, pid, raw_amt, code, date = (c['claim_id'], c['policy_id'],
                                     c['raw'][11:18], c['cover'], c['date'])
    if not (cid.isdigit() and pid.isdigit() and raw_amt.isdigit() and date.isdigit()):
        return 'ERR-01'
    amt = D(int(raw_amt)) / 100
    yy, mm, dd = int(date[:4]), int(date[4:6]), int(date[6:])
    if amt <= 0 or yy < 1900 or not 1 <= mm <= 12 or not 1 <= dd <= 31:
        return 'ERR-01'
    if cid in seen:
        return 'ERR-02'
    p = pol.get(pid)
    if not p:
        return 'ERR-03'
    cv = cov.get(code)
    if not cv:
        return 'ERR-04'
    if cv['plan'] != p['plan']:
        return 'ERR-05'
    if p['status'] != 'A':
        return 'ERR-06'
    if not (int(p['eff']) <= int(date) <= int(p['exp'])):
        return 'ERR-07'
    eligible = min(amt, D(cv['limit']))
    if eligible > D(p['sum_insured']) - paid[pid]:
        return 'ERR-08'
    seen.add(cid)
    after = max(D(0), eligible - D(cv['deductible']))
    copay = (after * D(cv['copay']) / 100).quantize(D('0.01'), ROUND_HALF_UP)
    paid[pid] += after - copay
    flags = []
    if amt > D(cv['limit']):
        flags.append('WRN-01')
    if eligible >= D(p['sum_insured']) * D('0.5'):
        flags.append('WRN-02')
    if after - copay == 0:
        flags.append('WRN-03')
    return 'OK' if not flags else 'OK:' + ','.join(flags)


# ----------------------------------------------------------------------
# Report parsers (fixed-column slicing; layout defined in CLMPROC01.cbl)
# ----------------------------------------------------------------------
def parse_settlement():
    content = read_report(SETTLEMENT)
    if not content:
        return {'claims': [], 'totals': {}}
    claims, totals = [], {}
    for ln in content.splitlines():
        ln = ln.ljust(132)  # COBOL line-sequential output trims trailing blanks
        s = ln.strip()
        if ln[1:7].isdigit() and ln[9:14].isdigit():
            claims.append({
                'claim_id': ln[1:7], 'policy_id': ln[9:14],
                'name': ln[16:36].strip(), 'plan': ln[38:42].strip(),
                'cover': ln[44:45], 'claimed': money(ln[47:59]),
                'eligible': money(ln[60:72]), 'deductible': money(ln[73:85]),
                'copay': money(ln[86:98]), 'payable': money(ln[99:111]),
                'status': ln[113:117].strip(),
            })
        elif s.startswith('GRAND TOTALS'):
            totals.update(claimed=money(ln[47:59]), eligible=money(ln[60:72]),
                          deductible=money(ln[73:85]), copay=money(ln[86:98]),
                          payable=money(ln[99:111]))
        elif s.startswith('TOTAL CLAIMS PROCESSED:'):
            totals['total_records'] = int(s.split(':')[-1])
        elif s.startswith('APPROVED:'):
            totals['approved'] = int(s.split(':')[-1])
        elif s.startswith('FLAGGED:'):
            totals['flagged'] = int(s.split(':')[-1])
        elif s.startswith('REJECTED:'):
            totals['rejected'] = int(s.split(':')[-1])
    return {'claims': claims, 'totals': totals}


def parse_plan_summary():
    content = read_report(PLAN_SUMMARY)
    if not content:
        return []
    plans = []
    for ln in content.splitlines():
        p = ln.split()
        if len(p) == 5 and p[0] in ('HLTH', 'AUTO', 'HOME'):
            try:
                plans.append({'plan': p[0], 'count': int(p[1]),
                              'claimed': money(p[2]), 'payable': money(p[3]),
                              'not_covered': money(p[4])})
            except ValueError:
                continue
    return plans


def parse_exception_log():
    content = read_report(EXCEPTION_LOG)
    if not content:
        return []
    out = []
    for ln in content.splitlines():
        p = ln.split()
        if len(p) >= 4 and p[2].startswith(('ERR-', 'WRN-')):
            out.append({'timestamp': f'{p[0]} {p[1]}', 'rc': p[2],
                        'desc': ' '.join(p[3:-1]), 'raw': p[-1],
                        'severity': 'ERROR' if p[2].startswith('ERR') else 'WARNING'})
    return out


def get_analytics_data():
    settle = parse_settlement()
    exceptions = parse_exception_log()
    policies = {p['id']: p for p in parse_policies()}

    err_counts, wrn_counts = {}, {}
    for e in exceptions:
        bucket = err_counts if e['severity'] == 'ERROR' else wrn_counts
        bucket[e['rc']] = bucket.get(e['rc'], 0) + 1

    util = {}
    for c in settle['claims']:
        u = util.setdefault(c['policy_id'], {
            'policy_id': c['policy_id'], 'name': c['name'], 'plan': c['plan'],
            'sum_insured': policies.get(c['policy_id'], {}).get('sum_insured', 0),
            'paid': 0.0})
        u['paid'] += c['payable']

    status_counts = {}
    for c in settle['claims']:
        status_counts[c['status']] = status_counts.get(c['status'], 0) + 1

    return {
        'claims': settle['claims'],
        'totals': settle['totals'],
        'plans': parse_plan_summary(),
        'exceptions': exceptions,
        'error_counts': err_counts,
        'warning_counts': wrn_counts,
        'status_counts': status_counts,
        'utilisation': list(util.values()),
        'error_text': ERROR_TEXT,
    }


# ----------------------------------------------------------------------
# Routes
# ----------------------------------------------------------------------
@app.route('/')
def dashboard():
    return render_template('dashboard.html')


@app.route('/api/data')
def get_data():
    policies, coverages, claims = parse_policies(), parse_coverages(), parse_claims()
    for c, r in zip(claims, preflight(claims, policies, coverages)):
        c['preflight'] = r
    return jsonify({'policies': policies, 'coverages': coverages,
                    'claims': claims, 'error_text': ERROR_TEXT})


@app.route('/api/reports')
def get_reports():
    return jsonify({
        'settlement': read_report(SETTLEMENT),
        'plan_summary': read_report(PLAN_SUMMARY),
        'exceptions': read_report(EXCEPTION_LOG),
        'analytics': get_analytics_data(),
        'generated_at': get_report_time(SETTLEMENT),
        'has_reports': read_report(SETTLEMENT) is not None,
    })


@app.route('/api/analytics')
def get_analytics():
    return jsonify(get_analytics_data())


def _to_wsl_path(win_path):
    drive, rest = os.path.splitdrive(win_path)
    return f"/mnt/{drive[0].lower()}{rest.replace(os.sep, '/')}"


@app.route('/api/run', methods=['POST'])
def run_batch():
    """Run the JCL emulation script (natively on Linux/macOS, via WSL on Windows)."""
    now = lambda: datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    try:
        if os.name == 'nt':
            cmd = f"cd '{_to_wsl_path(PROJECT_DIR)}' && bash scripts/run_batch.sh 2>&1"
            args = ['wsl', '-d', WSL_DISTRO, '--', 'bash', '-c', cmd]
        else:
            args = ['bash', 'scripts/run_batch.sh']
        r = subprocess.run(args, capture_output=True, text=True,
                           timeout=120, cwd=PROJECT_DIR)
        # JCL convention: RC 0000 clean, 0004 completed with exceptions
        return jsonify({'success': r.returncode in (0, 4),
                        'return_code': r.returncode,
                        'output': r.stdout + r.stderr, 'timestamp': now()})
    except subprocess.TimeoutExpired:
        return jsonify({'success': False, 'return_code': -1,
                        'output': 'ERROR: Batch job timed out after 120 seconds',
                        'timestamp': now()})
    except Exception as e:
        return jsonify({'success': False, 'return_code': -1,
                        'output': f'ERROR: {e}', 'timestamp': now()})


@app.route('/api/claims', methods=['POST'])
def save_claims():
    data = (request.json or {}).get('claims', '')
    try:
        with open(os.path.join(DATA_DIR, 'input', 'raw_claims.dat'), 'w',
                  encoding='ascii', newline='\n') as f:
            f.write(data)
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})


if __name__ == '__main__':
    print('=' * 60)
    print('  INSURANCE CLAIMS VALIDATION SYSTEM — WEB DASHBOARD')
    print('  Open http://localhost:5000 in your browser')
    print('=' * 60)
    app.run(debug=True, port=5000)
