#!/usr/bin/env python3
import os, re, datetime, argparse
from decimal import Decimal

# Optional deps: if present, we also write CSVs and do a round-trip compare
try:
    import pandas as pd
except Exception:
    pd = None

SCOPE_FILTER_DEFAULT = "tb.dut"  # set to "" to disable filtering
VDD_VOLTS_DEFAULT    = 1.0
CEFF_FARADS_DEFAULT  = 1e-15     # per-bit effective capacitance

class VCDDefs:
    _factor = {"s": '1e0', "ms": '1e-3', "us": '1e-6', "ns": '1e-9', "ps": '1e-12', "fs": '1e-15'}

    def __init__(self, vcd_path):
        self.vcd_path = vcd_path
        self.signals = []   # list of dicts {name,id,size,type}
        self.timescale = {}

    def read_definitions(self):
        hier = []
        with open(self.vcd_path, 'r', errors="ignore") as f:
            for line in f:
                if '$enddefinitions' in line:
                    break
                if line.startswith('$scope'):
                    hier.append(line.split()[2])
                elif line.startswith('$upscope'):
                    if hier:
                        hier.pop()
                elif line.startswith('$var'):
                    parts = line.split()
                    var_type   = parts[1]
                    size       = int(parts[2])
                    identifier = parts[3]
                    raw_name   = ''.join(parts[4:-1])   # keep [msb:lsb]
                    path = '.'.join(hier)
                    full_name = f"{path}.{raw_name}" if path else raw_name
                    self.signals.append({
                        "name": full_name,
                        "id": identifier,
                        "size": size,
                        "type": var_type
                    })
                elif line.startswith('$timescale'):
                    ts = line
                    if '$end' not in ts:
                        while True:
                            nxt = f.readline()
                            if not nxt:
                                break
                            ts += " " + nxt.strip()
                            if '$end' in nxt:
                                break

                    # Robust, anchored, case-insensitive parse: "$timescale <num><space?><unit> $end"
                    m = re.search(r"\$timescale\s*([0-9]+)\s*(fs|ps|ns|us|ms|s)\s*\$end",
                                ts, re.IGNORECASE)
                    if m:
                        mag = Decimal(m.group(1))
                        unit = m.group(2).lower()  # normalize to lowercase keys: fs/ps/ns/us/ms/s
                        self.timescale = {
                            "magnitude": mag,
                            "unit": unit,
                            "factor": Decimal(self._factor[unit]),
                            "timescale": mag * Decimal(self._factor[unit]),  # seconds per tick
                        }
                    else:
                        # Fallback: default to 1 ns per tick if header is odd
                        self.timescale = {
                            "magnitude": Decimal("1"),
                            "unit": "ns",
                            "factor": Decimal(self._factor["ns"]),
                            "timescale": Decimal("1e-9"),
                        }
                        



def norm_scalar(ch):
    ch = ch.strip()
    return ch.lower() if ch in ('0','1','x','X','z','Z') else 'x'

def norm_vector(bits):
    bits = bits.strip()
    return ''.join('x' if c not in '01xzXZ' else c.lower() for c in bits)

def hamming(a, b):
    n = min(len(a), len(b))
    diff = 0
    for i in range(n):
        ca, cb = a[i], b[i]
        if ca in '01' and cb in '01' and ca != cb:
            diff += 1
    return diff

def build_hierarchy(names):
    root = {"children": {}, "nets": set()}
    for full in names:
        parts = full.split('.')
        node = root
        for p in parts[:-1]:
            node = node["children"].setdefault(p, {"children": {}, "nets": set()})
        node["nets"].add(parts[-1])
    return root

def write_saif(saif_path, design_top, activity, duration_ticks, timescale):
    mag = int(timescale.get("magnitude", Decimal("1")))
    unit = timescale.get("unit", "ns")
    now  = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    hier = build_hierarchy(activity.keys())

    def emit_instance(fp, inst_name, node, indent):
        ind = ' ' * indent
        fp.write(f"{ind}(INSTANCE {inst_name}\n")
        for net in sorted(node["nets"]):
            # choose matching activity key
            key = None
            exact = f"{inst_name}.{net}"
            if exact in activity:
                key = exact
            else:
                cand = [k for k in activity if k.endswith(f".{inst_name}.{net}") or k.endswith(f".{net}")]
                if cand:
                    key = cand[-1]
            vals = activity.get(key, {"T0":0,"T1":0,"TX":0,"TC":0})
            fp.write(f"{ind}  (NET {net} (T0 {vals['T0']}) (T1 {vals['T1']}) (TX {vals['TX']}) (TC {vals['TC']}) (IG 0))\n")
        for child_name in sorted(node["children"].keys()):
            emit_instance(fp, child_name, node["children"][child_name], indent+2)
        fp.write(f"{ind})\n")

    with open(saif_path, "w") as fp:
        fp.write("(SAIFILE\n")
        fp.write('  (SAIFVERSION "2.0")\n')
        fp.write("  (DIRECTION FROM_TOP_TO_BOTTOM)\n")
        fp.write(f'  (DESIGN "{design_top}")\n')
        fp.write(f'  (DATE "{now}")\n')
        fp.write('  (VENDOR "custom")\n')
        fp.write('  (PROGRAM_NAME "vcd_automation")\n')
        fp.write('  (VERSION "0.2")\n')
        fp.write(f"  (TIMESCALE {mag} {unit})\n")
        fp.write(f"  (DURATION {duration_ticks})\n")
        emit_instance(fp, design_top, hier, indent=2)
        fp.write(")\n")

def parse_saif(path):
    rows = []
    stack = []
    with open(path, "r") as fp:
        for raw in fp:
            line = raw.strip()
            if not line: 
                continue
            if line.startswith("(INSTANCE "):
                name = line.split()[1]
                stack.append(name)
            elif line == ")":
                if stack: stack.pop()
            elif line.startswith("(NET "):
                m = re.findall(r"\(NET\s+([^\s]+)\s+\(T0\s+(\d+)\)\s+\(T1\s+(\d+)\)\s+\(TX\s+(\d+)\)\s+\(TC\s+(\d+)\)", line)
                if m:
                    net, T0s, T1s, TXs, TCs = m[0]
                    full = ".".join(stack+[net]) if stack else net
                    rows.append({
                        "signal": full,
                        "T0": int(T0s), "T1": int(T1s), "TX": int(TXs), "TC": int(TCs)
                    })
    if pd is None:
        return rows
    return pd.DataFrame(rows)

def analyze_vcd(vcd_path, scope_filter, vdd_volts, ceff_f):
    v = VCDDefs(vcd_path)
    v.read_definitions()
    id_to_meta = {s["id"]: s for s in v.signals}
    ids = list(id_to_meta.keys())
    if scope_filter:
        ids = [sid for sid in ids if id_to_meta[sid]["name"].startswith(scope_filter)]

    last_val   = {sid: None for sid in ids}
    last_time  = {sid: None for sid in ids}
    tc         = {sid: 0 for sid in ids}
    hd_sum     = {sid: 0 for sid in ids}
    t0         = {sid: 0 for sid in ids}
    t1         = {sid: 0 for sid in ids}
    tx         = {sid: 0 for sid in ids}
    current_time = 0
    begin_time = None
    end_time   = 0
    in_dumpvars = False

    def advance_dwell(sid, new_time):
        lv = last_val[sid]
        lt = last_time[sid]
        if lt is None or lv is None:
            last_time[sid] = new_time
            return
        dt = new_time - lt
        if dt <= 0:
            return
        if id_to_meta[sid]["size"] == 1:
            if lv == '0':
                t0[sid] += dt
            elif lv == '1':
                t1[sid] += dt
            else:
                tx[sid] += dt
        else:
            if any(c not in '01' for c in lv):
                tx[sid] += dt
        last_time[sid] = new_time

    with open(v.vcd_path, 'r', errors="ignore") as f:
        for raw in f:
            line = raw.strip()
            if not line:
                continue

            if line.startswith('$'):
                if line.startswith('$dumpvars'):
                    in_dumpvars = True
                elif line.startswith('$end') and in_dumpvars:
                    in_dumpvars = False
                continue

            if line.startswith('#'):
                t = int(line[1:])
                if begin_time is None:
                    begin_time = t
                    for sid in ids:
                        last_time[sid] = begin_time
                current_time = t
                if t > end_time:
                    end_time = t
                continue

            if not ids:
                continue

            c0 = line[0]
            if c0 in '01xXzZ':
                val = norm_scalar(c0)
                sid = line[1:]
                if sid not in id_to_meta or sid not in ids:
                    continue
                advance_dwell(sid, current_time)
                prev = last_val[sid]
                if prev is not None and prev in '01' and val in '01' and prev != val:
                    tc[sid] += 1
                    hd_sum[sid] += 1
                last_val[sid] = val
                continue

            if c0 in 'bBrR':
                try:
                    payload, sid = line[1:].split()
                except ValueError:
                    continue
                if sid not in id_to_meta or sid not in ids:
                    continue
                bits = norm_vector(payload)
                advance_dwell(sid, current_time)
                prev = last_val[sid]
                if prev is not None:
                    hd = hamming(prev, bits)
                    hd_sum[sid] += hd
                    tc[sid] += hd
                last_val[sid] = bits
                continue

    if begin_time is None:
        begin_time = 0
    for sid in ids:
        advance_dwell(sid, end_time)

    # Build rows and compute power/energy using provided vdd & ceff
    rows = []
    for sid in ids:
        meta = id_to_meta[sid]
        rows.append({
            "signal": meta["name"],
            "width":  meta["size"],
            "TC":     tc[sid],
            "HD_sum": hd_sum[sid],
            "T0":     t0[sid],
            "T1":     t1[sid],
            "TX":     tx[sid],
        })

    duration_ticks = max(0, int((end_time or 0) - (begin_time or 0)))
    ts = v.timescale.get("timescale", Decimal("1e-9"))  # default ns per tick if missing
    duration_seconds = float(duration_ticks) * float(ts)
    if duration_seconds <= 0:
        duration_seconds = 1.0

    for r in rows:
        energy = r["TC"] * ceff_f * (vdd_volts**2)   # Joules
        r["Energy_J"] = energy
        r["Power_W"]  = energy / duration_seconds

    activity = {r["signal"]: {"T0": int(r["T0"]), "T1": int(r["T1"]), "TX": int(r["TX"]), "TC": int(r["TC"])} for r in rows}

    if rows and ('.' in rows[0]["signal"]):
        design_top = rows[0]["signal"].split('.')[0]
    else:
        design_top = "TOP"

    return {
        "rows": rows,
        "activity": activity,
        "design_top": design_top,
        "duration_ticks": duration_ticks,
        "timescale": v.timescale,
        "duration_seconds": duration_seconds,
    }

def print_summary(rows, duration_seconds, topn=20):
    total_signals = len(rows)
    total_toggles = sum(r["TC"] for r in rows)
    print("====== VCD ANALYSIS SUMMARY ======")
    print(f"Signals         : {total_signals}")
    print(f"Total Toggles   : {total_toggles}")
    print(f"Duration (s)    : {duration_seconds:.9f}")
    if duration_seconds > 0:
        print(f"Avg Toggle Rate : {total_toggles/duration_seconds:.2f} toggles/s (bit-level)")
    print()
    top = sorted(rows, key=lambda r: r["TC"], reverse=True)[:min(topn, total_signals)]
    print(f"Top {len(top)} toggling signals:")
    print("{:<8}  {:<48}  {:>12}  {:>12}".format("Width","Signal","Toggles","Toggle/s"))
    for r in top:
        rate = r["TC"]/duration_seconds if duration_seconds>0 else 0.0
        print("{:<8}  {:<48}  {:>12}  {:>12.2f}".format(r["width"], r["signal"][:48], r["TC"], rate))
    print()

def print_power_table(rows, vdd, ceff, topn=20):
    print("====== ESTIMATED DYNAMIC POWER (per signal) ======")
    print(f"Assumptions: VDD = {vdd} V, Ceff = {ceff} F per bit")
    print("{:<48}  {:>5}  {:>10}  {:>11}  {:>7}  {:>12}  {:>12}".format(
        "Signal", "W", "Toggles", "Ceff(F)", "VDD(V)", "Power (W)", "Energy (J)"
    ))
    rows_sorted = sorted(rows, key=lambda r: r["Power_W"], reverse=True)[:min(topn, len(rows))]
    for r in rows_sorted:
        print("{:<48}  {:>5}  {:>10}  {:>11.4e}  {:>7.3f}  {:>12.4e}  {:>12.4e}".format(
            r["signal"][:48], r["width"], r["TC"], ceff, vdd, r["Power_W"], r["Energy_J"]
        ))
    print()

def save_csvs(rows, out_dir, vdd, ceff):
    if pd is None:
        return
    df = pd.DataFrame(rows)
    df.sort_values("Power_W", ascending=False, inplace=True)
    df["VDD_V"] = vdd
    df["Ceff_F"] = ceff
    df.to_csv(os.path.join(out_dir, "switching_activity_vcd.csv"), index=False)
    df[["signal","width","TC","T0","T1","TX","Power_W","Energy_J","VDD_V","Ceff_F"]].to_csv(
        os.path.join(out_dir, "power_estimate_vcd.csv"), index=False
    )

def compute_totals(rows):
    total_energy = sum(r["Energy_J"] for r in rows)
    total_power  = sum(r["Power_W"]  for r in rows)
    return total_energy, total_power

def compute_per_round(rows):
    """Group by gen_rounds(<n>) if present in signal name."""
    bank_totals = {}
    for r in rows:
        m = re.search(r"gen_rounds\((\d+)\)", r["signal"])
        key = f"round{m.group(1)}" if m else "other"
        bank_totals.setdefault(key, {"Energy_J":0.0, "Power_W":0.0})
        bank_totals[key]["Energy_J"] += r["Energy_J"]
        bank_totals[key]["Power_W"]  += r["Power_W"]
    return bank_totals

def print_totals(rows):
    E, P = compute_totals(rows)
    print("====== TOTALS ======")
    print(f"Total Energy (J) : {E:.6e}")
    print(f"Total Power  (W) : {P:.6e}")
    print()

def print_per_round(rows):
    groups = compute_per_round(rows)
    print("====== PER-ROUND TOTALS ======")
    print("{:<10}  {:>12}  {:>12}".format("Bucket","Power (W)","Energy (J)"))
    for b, agg in sorted(groups.items()):
        print("{:<10}  {:>12.6e}  {:>12.6e}".format(b, agg["Power_W"], agg["Energy_J"]))
    print()

def main():
    ap = argparse.ArgumentParser(description="VCD analysis + SAIF writer (terminal output + power table).")
    ap.add_argument("-i", "--input", required=True, help="Path to input .vcd")
    ap.add_argument("-s", "--scope", default=SCOPE_FILTER_DEFAULT, help=f"Scope prefix filter (default: {SCOPE_FILTER_DEFAULT!r}; use '' to disable)")
    ap.add_argument("-v", "--vdd", type=float, default=VDD_VOLTS_DEFAULT, help="VDD for simple power model")
    ap.add_argument("-c", "--ceff", type=float, default=CEFF_FARADS_DEFAULT, help="Ceff per bit for power model (F)")
    ap.add_argument("--topn", type=int, default=50, help="How many rows to print in the terminal tables")
    args = ap.parse_args()

    vcd_path = os.path.abspath(args.input)
    if not os.path.isfile(vcd_path):
        raise SystemExit(f"VCD not found: {vcd_path}")

    out_dir = os.path.dirname(vcd_path)
    base = os.path.splitext(os.path.basename(vcd_path))[0]
    saif_path = os.path.join(out_dir, base + ".saif")

    scope_filter = args.scope if args.scope not in ("", "None", "none") else None

    res = analyze_vcd(vcd_path, scope_filter, args.vdd, args.ceff)

    # Terminal outputs
    print_summary(res["rows"], res["duration_seconds"], topn=args.topn)
    print_power_table(res["rows"], args.vdd, args.ceff, topn=args.topn)

    # SAIF next to VCD
    write_saif(saif_path, res["design_top"], res["activity"], res["duration_ticks"], res["timescale"])
    print(f"SAIF written   : {saif_path}")

    # Round-trip check (optional)
    parsed = parse_saif(saif_path)
    if pd is not None and isinstance(parsed, pd.DataFrame):
        import pandas as _pd
        df_vcd = _pd.DataFrame(res["rows"])
        cmp = _pd.merge(df_vcd[["signal","TC","T0","T1","TX"]],
                        parsed[["signal","TC","T0","T1","TX"]],
                        on="signal", suffixes=("_vcd","_saif"))
        cmp["dTC"] = cmp["TC_vcd"] - cmp["TC_saif"]
        cmp["dT0"] = cmp["T0_vcd"] - cmp["T0_saif"]
        cmp["dT1"] = cmp["T1_vcd"] - cmp["T1_saif"]
        cmp["dTX"] = cmp["TX_vcd"] - cmp["TX_saif"]
        mism = cmp[(cmp["dTC"]!=0)|(cmp["dT0"]!=0)|(cmp["dT1"]!=0)|(cmp["dTX"]!=0)]
        print(f"Round-trip mismatched nets: {len(mism)} (0 is ideal)")
    else:
        print("Round-trip check skipped (pandas not available).")
    
    print_totals(res["rows"])
    print_per_round(res["rows"]) 

    # CSVs
    save_csvs(res["rows"], out_dir, args.vdd, args.ceff)
    if pd is not None:
        print(f"Saved CSVs to  : {out_dir}")
    else:
        print("CSV export skipped (pandas not available).")

if __name__ == "__main__":
    main()
