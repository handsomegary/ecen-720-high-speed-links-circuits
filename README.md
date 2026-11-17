# ECEN 720 High-Speed Links Circuits

ECEN 720 的 10 Gb/s limiting amplifier（LA）專案，包含 Spectre 網表、案例設定、OCEAN 讀取腳本與 Slurm 範例。

歷史交接：[2026-11-06 project checkpoint](PROJECT_CHECKPOINT_20261106.md)。歷史來源和工具供保存與檢視，不得自動重啟舊排程或重試失敗模擬。

[LA5 R6 版圖後重現輸入](projects/la/r6/)包含可編輯 OA、GDS、CDL、後仿案例與 Calibre 重建說明。

| 專案 | 輸入案例 | 訊號與分析 |
| --- | --- | --- |
| [10 Gb/s LA](projects/la/) | `nominal` | 名目 DC、AC、noise。長測試加入 2,048-bit PRBS7，差動輸入 10 mVpp，204.8 ns。 |

`projects/la/netlists/` 是設計輸入。網表只替換了原本的 PDK 根目錄，電路、分析、刺激和元件尺寸照原始輸入保存。`SOURCE_PROVENANCE.json` 記錄原始網表與範本的 SHA-256。執行需要已安裝且有權使用的 28nm PDK、Cadence IC231、Spectre 與 Python 3.8 以上。

## 在 Olympus 準備並提交

登入後依課程流程取得 Slurm 環境。在 repo 根目錄，先設定自己已安裝的 PDK 根目錄。它應有 `models/spectre/` 子目錄。

```bash
export ECEN720_PDK_ROOT="$HOME/pdks/28nm/pdk_kit.0_2p2a_20160226_all/28nm_pdk"
repo="$PWD"
```

逐行執行，`prepare_deck.py` 會檢查案例雜湊與模型 include，寫入新的模擬目錄。

```bash
export PROJECT_BUNDLE_ROOT="$repo/projects/la"
run_dir="$(mktemp -d "$HOME/ECEN720/la_nominal.XXXXXXXX")"
python3 "$PROJECT_BUNDLE_ROOT/olympus/prepare_deck.py" --case nominal --output "$run_dir/input.scs"
cd "$run_dir"
sbatch "$PROJECT_BUNDLE_ROOT/olympus/background_example.sbatch"
```

提交後可斷開連線，用該次回傳的 Job ID 查狀態。

```bash
squeue -j <JOB_ID>
sacct -X -j <JOB_ID> --format=JobID,State,ExitCode,Elapsed,NodeList
```

較長的 transient 量測用以下命令準備。它會產生獨立的 `input.scs`、SKILL 量測設定、OCEAN 腳本和 Slurm 腳本。準備完進入顯示的 `RUN_DIR`，執行 `sbatch run_long.sbatch`。

```bash
cd "$repo"
python3 tools/long-jobs/prepare_long_run.py la
```

確認 Slurm 為 `COMPLETED 0:0`，並檢查 `ocean_read.log` 的 `ECEN720_MEASURE_PASS` 與 `measurements.csv`。批次腳本先載入 IC231 環境，再把 Spectre 執行檔加到 `PATH`。這個順序保留 IC231 的 OpenAccess 程式庫，避免混載 Spectre 環境時遇到的符號載入錯誤。

## 來源與可重現範圍

- `projects/la/reference/source_snapshot/` 保存歷史 Python、SKILL、OCEAN 原始碼。部分歷史流程需要本機 OA library、凍結資料或其他專案檔案。已有 OA library 時可設定 `ECEN720_OA_LIBRARY_DIR`，再使用該專案的 `create_cds_lib.py`。
- [LA Monte Carlo 規格](projects/la/reference/monte_carlo_specs.json)保存名目與高溫低電壓兩組各 32 個樣本的最差增益、頻寬及輸入雜訊。

PDK、模型、OA 資料庫、原始波形與機器憑證均由各環境自行管理。
