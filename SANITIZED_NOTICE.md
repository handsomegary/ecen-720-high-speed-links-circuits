# Public release notice

De-identified copy of an ECEN 720 (Texas A&M) limiting-amplifier project.

- Foundry PDK identifiers were replaced with generic aliases: device names (`nmos_lvt`, `pmos_lvt`, ...), model/kit files (`pdk_model*`, `pdk_toplevel.scs`), kit codes (`28nm_pdk`; the process node `28nm` is kept), corner sections (`tt`, `ss`, `ff`) and the word for the foundry (`foundry`).
- Install paths, license paths, cluster node names and user names were replaced with placeholders.
- Device sizes, topology and all design values are unchanged.
- History was rebuilt as a single commit; recorded SHA-256 values may no longer match the edited files.
- Binary layout/database files (`projects/la/r6/inputs/layout/*.gds`, `projects/la/r6/inputs/oa/*.tar.gz`) were removed: they embed foundry library/cell names and layer maps that cannot be aliased safely. Netlists, scripts and results remain.
