# ECEN 720 high-speed links checkpoint — 2026-11-06

## Scope

This checkpoint covers the 10 Gb/s limiting amplifier (LA). The repository contains circuit inputs, case metadata, historic source snapshots, and Olympus preparation, simulation, and measurement helpers. See [the main README](README.md) for setup and dependencies.

The repository does not contain a PDK, foundry model files or coefficients, OA databases, raw waveforms, or credentials. The historical code is a source reference, not proof that every old workflow can run without its original project data. The available VM and Olympus installations and their separate project data remain necessary for some workflows. Do not restart an old queue or retry a failed simulation automatically.

## Olympus execution evidence

On 2026-11-06 the documented Olympus work included LA DC/AC/noise and a PRBS7 transient. These are historical execution records, not a claim that current remote files remain in place. Execution notes are maintained separately in the Olympus Cadence notes repository.

## Retained environments and deletion boundary

Per the user's 2026-11-06 instruction, any subsequent cleanup is limited to local Windows copies of explicitly identified project artifacts. The VMware project and Olympus data are retained. Preserve shared infrastructure, SSH keys, other courses and projects, and the separate Olympus notes repository. An independently verifiable remote commit must exist before deleting any local source or result. The local LA transfer ZIP and the shared packaging and notes folders were not deleted.
