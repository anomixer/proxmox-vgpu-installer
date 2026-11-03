# PVE Browser LXC Download Pipeline

## 專案目的

本專案在 Proxmox VE（PVE）上建立隔離的 LXC 瀏覽器環境，讓 Chromium 透過圖形化瀏覽器流程，從你有權存取的網站下載檔案。

適用情境包括：

- 網站需要 JavaScript、Cookie、session 或正常瀏覽器互動。
- 需要透過 noVNC 查看瀏覽器畫面，並由授權使用者完成登入或人工確認。
- 下載完成後使用 `pct pull` 將檔案取回 PVE host。

本專案不應用來繞過登入、付費牆、CAPTCHA、存取控制或未授權的網站保護。請遵守來源網站及相關服務的使用條款。

## 整體流程

```text
PVE host
  │
  ├── create-lxc.sh 建立 LXC
  ├── setup-lxc.sh 安裝 Chromium、Browser API、noVNC 與相關元件
  ├── setup-lxc.sh 驗證安裝成功
  ├── setup-lxc.sh 成功後寫入 PVE Notes
  ├── 6081 API 要求 Chromium 開啟下載 URL
  ├── Chromium 在虛擬桌面中完成下載
  ├── test-lxc.sh 確認下載檔案非空
  ├── pct pull 將檔案取回 PVE host
  └── 確認 PVE 檔案成功後，刪除 LXC 內的下載檔案
```

## 預設 LXC 資源

目前 `create-lxc.sh` 的預設配置為：

```text
CTID:     9000
Hostname: browser-api
RAM:      1024 MB
SWAP:     512 MB
Disk:     4 GB
CPU:      1 core
Network:  DHCP，bridge=vmbr0
```

這組配置已實測可以執行 Chromium、Xvfb、Fluxbox、x11vnc、noVNC、Browser API，以及下載、`pct pull` 和清理流程。

實際下載大型檔案時，磁碟空間必須同時容納下載檔案、Chromium 暫存資料與系統空間；若下載檔案接近 4 GB，應增加 rootfs 大小。

## 專案檔案

```text
/root/api/
├── README.md
├── create-lxc.sh
├── setup-lxc.sh
├── browser-supervisor.sh
├── start-browser-lxc.sh
├── test-lxc.sh
└── main.py
```

| 檔案 | 執行位置 | 用途 |
|---|---|---|
| `README.md` | 文件 | 架構、安裝、測試與故障排除 |
| `create-lxc.sh` | PVE host | 建立 LXC 與設定資源；不寫入 PVE Note |
| `setup-lxc.sh` | PVE host | 安裝套件、推送程式、驗證環境，成功後寫入 PVE Note |
| `browser-supervisor.sh` | LXC | 啟動 Xvfb、Fluxbox、x11vnc、noVNC 與 Browser API |
| `start-browser-lxc.sh` | PVE host | 啟動或準備瀏覽器 LXC |
| `test-lxc.sh` | PVE host | 測試服務、呼叫 API、等待下載、取回並清理檔案 |
| `main.py` | LXC | 提供 6081 Browser API |

## `create-lxc.sh`

`create-lxc.sh` 只負責建立乾淨的 LXC，不會寫入 PVE Note。

目前資源預設值：

```bash
MEMORY="${MEMORY:-1024}"
SWAP="${SWAP:-512}"
CORES="${CORES:-1}"
ROOTFS_SIZE="${ROOTFS_SIZE:-4}"
```

建立 LXC：

```bash
cd /root/api
chmod +x create-lxc.sh
./create-lxc.sh
```

也可以明確指定資源：

```bash
CTID=9000 \
MEMORY=1024 \
SWAP=512 \
CORES=1 \
ROOTFS_SIZE=4 \
./create-lxc.sh
```

建立完成後確認：

```bash
pct config 9000
pct status 9000
```

## `setup-lxc.sh`

`setup-lxc.sh` 必須在專案目錄執行，並且會使用目前目錄的 `main.py` 與 `browser-supervisor.sh`：

```bash
cd /root/api
chmod +x setup-lxc.sh
bash -n setup-lxc.sh
./setup-lxc.sh
```

安裝流程包括：

1. 啟動 LXC。
2. 等待 LXC 網路可用。
3. 安裝 Chromium、Xvfb、Fluxbox、x11vnc、noVNC、Python 與相關套件。
4. 建立 Python virtual environment 並安裝 FastAPI、Uvicorn。
5. 推送 `main.py` 和 `browser-supervisor.sh`。
6. 安裝並啟用 OpenRC service。
7. 驗證所有必要執行檔與設定檔。
8. 全部成功後，將 API 說明寫入 PVE UI 的 Notes 欄位。

若安裝或驗證失敗，PVE Note 不會被寫入。若寫入 Note 失敗，腳本會回報錯誤。

如果使用不同 CTID：

```bash
CTID=9001 ./setup-lxc.sh
```

## PVE Note

`setup-lxc.sh` 成功後會將以下資訊寫入 PVE LXC Notes：

- LXC 名稱與用途。
- Browser API、noVNC 和 VNC ports。
- `/health`、`/api/download` 和 `/api/check` 用法。
- `pct pull` 的來源路徑。
- root 登入資訊與安全提醒。

PVE Note 使用 `(LXC_IP)`、`(DOWNLOAD_URL)` 和 `(FILENAME)`，避免 PVE UI 將尖括號當成特殊標記。

## `test-lxc.sh`

### 基本執行

```bash
cd /root/api
chmod +x test-lxc.sh
bash -n test-lxc.sh
./test-lxc.sh
```

### 使用自訂 CTID、檔名與 URL

```bash
CTID=9000 \
FILENAME='GPU-Z.2.69.0.exe' \
DRIVER_URL='https://fs03n3.sendspace.com/dl/191505e0a12cf41ec152d0172b5a5719/6ab4f03a0ad8d535/qs5p0x1t/GPU-Z.2.69.0.exe' \
./test-lxc.sh
```

也可以寫成單行：

```bash
CTID=9000 FILENAME='GPU-Z.2.69.0.exe' DRIVER_URL='https://fs03n3.sendspace.com/dl/191505e0a12cf41ec152d0172b5a5719/6ab4f03a0ad8d535/qs5p0x1t/GPU-Z.2.69.0.exe' ./test-lxc.sh
```

### 取回與清理行為

檔案會依序出現在：

```text
LXC:      /home/user/Downloads/(filename)
PVE 暫存: /root/(filename).part
PVE 最終: /root/(filename)
```

只有在 PVE `.part` 檔案確認非空並改名成功後，腳本才會刪除 LXC 內原始檔案。

成功輸出：

```text
File saved: /root/GPU-Z.2.69.0.exe
LXC file removed: /home/user/Downloads/GPU-Z.2.69.0.exe
Test completed successfully.
```

## Browser API

### Services and ports

| Service | Port | Purpose |
|---|---:|---|
| VNC | 5901 | VNC server |
| noVNC | 6080 | Browser screen and manual interaction |
| Browser API | 6081 | Start Chromium and check download status |

noVNC：

```text
http://(LXC_IP):6080/vnc.html
```

Health check：

```bash
curl --fail --max-time 10 \
    http://(LXC_IP):6081/health
```

Start a browser download：

```bash
curl --fail --silent --show-error --get \
    --data-urlencode "url=https://example.com/file.run" \
    "http://(LXC_IP):6081/api/download"
```

Check download status：

```bash
curl --fail --silent --show-error --get \
    --data-urlencode "filename=file.run" \
    "http://(LXC_IP):6081/api/check"
```

輪詢 `/api/check`，直到回應包含：

```json
{"exists":true,"status":"ready"}
```

## 資源監控

```bash
watch -n 2 'pct exec 9000 -- free -h'
pct exec 9000 -- df -h
pct exec 9000 -- ps
pct exec 9000 -- rc-service browser-supervisor status
pct exec 9000 -- netstat -lntp | grep -E ':5901|:6080|:6081'
```

若出現記憶體不足或 OOM：

```bash
pct exec 9000 -- dmesg | grep -i -E 'oom|killed|memory'
pct exec 9000 -- tail -n 100 /var/log/browser-desktop/chromium.log
```

## 故障排除

### 下載逾時

```bash
pct exec 9000 -- ps
pct exec 9000 -- ls -lah /home/user/Downloads
pct exec 9000 -- tail -n 100 /var/log/browser-desktop/chromium.log
```

同時開啟 noVNC，確認網站是否停在登入、驗證、錯誤或下載提示畫面。

### `pct pull` 失敗

```bash
pct exec 9000 -- ls -lh /home/user/Downloads
df -h /root
```

如果 `pct pull` 失敗，腳本會保留 LXC 原始檔案，不會刪除；可以重新取回，避免資料遺失。

### PVE Note 沒有出現

確認 `setup-lxc.sh` 最後沒有錯誤，並檢查：

```bash
pct config 9000 | grep -A20 '^description:'
```

也可以重新執行：

```bash
cd /root/api
CTID=9000 ./setup-lxc.sh
```

### LXC 內檔案沒有刪除

```bash
ls -lh /root/<filename>
pct exec 9000 -- ls -lah /home/user/Downloads
```

確認 PVE 正式檔案存在且非空後，可以手動清理：

```bash
pct exec 9000 -- rm -f /home/user/Downloads/<filename>
```

## 安全與合規注意事項

API、noVNC 與 VNC 可能綁定在所有介面。正式使用時應套用 PVE firewall 或外部防火牆限制來源網段，不要直接暴露到不可信網路。

只從你有權存取的網站下載檔案。遇到人工驗證時，應由授權使用者透過 noVNC 完成。
