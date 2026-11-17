#!/usr/bin/env python3
"""Prepare one independent ECEN720 transient run from the installed package."""

import argparse
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


LA_BITS = 2048
LA_UI = 100e-12
LA_STOP = LA_BITS * LA_UI
TIME_ROUNDING = 1e-15
LA_VIN = 'VIN (stim 0) vsource dc=0 mag=1'


def la_prbs_points():
    # Same PRBS7 state and taps as vm_project/scripts/r3_la_sim.py.
    state = 0x7f
    levels = []
    for _ in range(LA_BITS):
        levels.append(0.005 if state & 1 else -0.005)
        feedback = ((state >> 6) ^ (state >> 5)) & 1
        state = ((state << 1) & 0x7f) | feedback

    half_edge = 5e-12
    points = [(0.0, 0.0), (half_edge, levels[0])]
    for index, level in enumerate(levels[1:], start=1):
        previous = levels[index - 1]
        if level != previous:
            boundary = index * LA_UI
            points.extend([(boundary - half_edge, previous),
                           (boundary + half_edge, level)])
    points.append((LA_STOP, levels[-1]))
    return points


def make_la_transient(deck):
    if deck.splitlines().count(LA_VIN) != 1:
        raise ValueError('Expected exactly one nominal LA stimulus source.')
    if re.search(r'(?m)^\s*\w+\s+tran\b', deck):
        raise ValueError('The nominal LA source already contains a transient analysis.')
    wave = ' '.join('{:.15g} {:.15g}'.format(t, v) for t, v in la_prbs_points())
    deck = deck.replace(LA_VIN + '\n', LA_VIN + ' type=pwl wave=[' + wave + ']\n', 1)
    return deck.rstrip() + '\ntranLong tran stop={:.15g} maxstep=1p errpreset=conservative\n'.format(LA_STOP)


def make_config(project, stop, end_tolerance, signals):
    # All strings and numbers come from the fixed project choices below.
    lines = ['ecen720Project = "{}"'.format(project),
             'ecen720Stop = {:.16g}'.format(stop),
             'ecen720EndTolerance = {:.16g}'.format(end_tolerance)]
    names = ('ecen720InputP', 'ecen720InputN', 'ecen720OutputP', 'ecen720OutputN')
    lines.extend('{} = "{}"'.format(name, signal) for name, signal in zip(names, signals))
    return ('\n'.join(lines) + '\n').encode('ascii')


def main():
    kit = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('project', choices=('la',))
    parser.add_argument('--root', type=Path, default=kit.parents[1] / 'projects',
                        help='Directory containing the la project folder')
    parser.add_argument('--pdk-root', type=Path, help='Pass a nondefault PDK directory to prepare_deck.py')
    args = parser.parse_args()
    root = args.root.expanduser().resolve()

    bundle, case = 'la', 'nominal'
    stop, signals = LA_STOP, ('inp', 'inn', 'outp', 'outn')
    end_tolerance = TIME_ROUNDING

    preparer = root / bundle / 'olympus' / 'prepare_deck.py'
    if not preparer.is_file():
        parser.error('Installed package preparer missing: {}'.format(preparer))

    with tempfile.TemporaryDirectory(prefix='.ecen720_prepare.', dir=str(root)) as stage:
        adapted = Path(stage) / 'input.scs'
        command = [sys.executable, str(preparer), '--case', case, '--mode', 'full',
                   '--output', str(adapted)]
        if args.pdk_root is not None:
            command.extend(['--pdk-root', str(args.pdk_root)])
        subprocess.run(command, check=True)
        deck = make_la_transient(adapted.read_text(encoding='utf-8')).encode('utf-8')

    run_dir = Path(tempfile.mkdtemp(prefix='{}_long.'.format(args.project), dir=str(root)))
    (run_dir / 'input.scs').write_bytes(deck)
    (run_dir / 'measurement_config.il').write_bytes(make_config(args.project, stop, end_tolerance, signals))
    for filename in ('run_long.sbatch', 'measure_transient.ocn'):
        shutil.copyfile(str(kit / filename), str(run_dir / filename))

    print('RUN_DIR={}'.format(run_dir))
    print('PROJECT={}  CASE={}  TRAN_STOP_S={:.16g}'.format(args.project, case, stop))
    print('STIMULUS=PRBS7  BITS={}  BIT_RATE=10Gb/s  DIFF_VPP=10mV'.format(LA_BITS))
    print('Prepared input.scs, measurement_config.il, measure_transient.ocn and run_long.sbatch')


if __name__ == '__main__':
    main()
