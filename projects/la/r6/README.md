# LA5 R6 版圖後驗證

這份資料補充 10 Gb/s limiting amplifier 的 R6 版圖後課程驗證。[Olympus nominal 案例](../cases.json)屬於 R3 原理圖版本，仍可依 repo 根目錄的流程重跑。

R6 完成的範圍是 cell-scope DRC／LVS、名目 AC／noise、固定寄生 RC 的 27 點 device PVT 和 32 點 process／mismatch、名目 DM／CM 外迴路 STB，以及 127-bit 10 Gb/s PRBS。完成的電氣驗證使用 **fresh REDUCED**。ALL 電網與 REDUCED 的等效誤差、量產簽核及 BER 仍未驗證。

| 抽取版本 | 用途 |
| --- | --- |
| Filled ALL | 完整浮接金屬電網的抽取輸出 |
| Filled fresh REDUCED | 重做 PHDB、PDB、FMT 的近似模型。R6 課程驗證的後仿來源 |
| Filled FMT-only REDUCED | 沿用 ALL PDB 的獨立診斷，與 fresh REDUCED 分開記錄 |

此目錄保存重現用輸入、指令與雜湊。PEX 由版圖與規則產生。Filled ALL 和 FMT-only 診斷的原始 `.pxi` 各約 178 MiB，超過 [GitHub 一般 Git 的 100 MiB 單檔上限](https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-large-files-on-github)。Fresh REDUCED 三個網表合計約 8.13 MiB，也按同一保留原則由抽取流程生成。Calibre 的 `svdb`、PDB、PHDB 是抽取工作資料庫，原始 PSF 是模擬結果，均由執行環境管理。

| 路徑 | 用途 |
| --- | --- |
| `inputs/oa/` | 24 個專案自有的 OA 檔案。解壓為 `la5_lab`，在目的端的 `cds.lib` 定義此 library 和授權的標準元件庫。 |
| `inputs/layout/` | 未填充與已填充的 GDS、頂層組裝 SKILL、fill merge 設定。頂層 SKILL 引用 OA 子 cell。 |
| `inputs/schematic/core.cdl` | LVS 的原理圖網表。 |
| `inputs/simulation/`、`inputs/scripts/` | Nominal、PRBS、STB、device PVT、MC 等後仿 deck 與模型選角 wrapper。 |
| `manifest.json` | 各輸入的 SHA-256、外部依賴與原 PEX 輸出雜湊。 |

## 重跑前需要的環境

使用具備 28nm PDK、該版 LVS／xRC 規則、`1P8M` 金屬堆疊和對應授權的工作區。歷史環境使用 Calibre `2019.3_15.11`、Virtuoso IC6.1.8 和 Spectre `18.1.0.077`。原 `run.rcx` 及製程檔案由授權環境提供，版本核對見 `manifest.json`。

在獨立工作目錄複製所需輸入，將 `@pdk_28nm_root@`、`@VIRTUOSO_ROOT@` 換成目的端安裝路徑，將 `@LA5_PROJECT_ROOT@` 換成包含 `scripts/` 子目錄的重跑根目錄。LVS 使用 GDS 與 CDL。後仿的 `.include "core.dist"` 要求重建的 `core.dist`、`.pex`、`.pxi` 同在該案例工作目錄。ALL 與 REDUCED 各自使用原 runset 和對應輸出，端點依名稱對應。

以下是驗證過的 fresh REDUCED 抽取階段順序。`run.rcx` 由對應的已授權規則和專案設定建立。在獨立工作目錄使用 `PEX EXTRACT FLOATING NETS REDUCED`，並依序執行。

```sh
calibre -xrc -phdb -nowait run.rcx
calibre -xrc -pdb -rcc -turbo 4 -turbo_all -nowait run.rcx
calibre -xrc -fmt -rcc -nowait run.rcx
```

完整 ALL 路徑使用 `PEX EXTRACT FLOATING NETS ALL`。歷史 disk-recovery 案例從相同版圖的已完成 PHDB 繼續 PDB 和 FMT。有相同版本、網路與設定的 PDB／PHDB 時，可只做 `-fmt` 匯出；資料庫未保留時，從 GDS、CDL 和授權的規則重做完整抽取。獨立 DRC 使用相同 GDS 與對應 DRC 規則，供幾何驗證。
