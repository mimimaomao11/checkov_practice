# Checkov 實作練習：在部署前攔截 Missing Config
 
本練習對應文章〈用 Checkov 在部署前攔截 Missing Config〉，用最少的 Terraform 程式碼，實際觀察 Checkov 如何發現缺漏的設定，以及它的限制。
 
- 所有練習只掃描 `.tf` 檔，**不需要 GCP 帳號，也不會建立任何雲端資源**
- 使用版本：Checkov 3.3.30
---
 
## 目錄結構
 
```
checkov-practice/
├── README.md
├── lab1/
│   └── main.tf                 # 步驟 1–4：Missing Config 偵測、略過註解、檢查強度
├── lab2/
│   └── main.tf                 # 步驟 5–6：規則盲點與自訂規則
├── policies/
│   └── require_ports.yaml      # 步驟 6：自訂規則
└── lab3/
    ├── main.tf                 # 步驟 7：呼叫 Module
    └── modules/
        └── subnet/
            └── main.tf         # 步驟 7：內建安全預設的 Module
```
 
---
 
## 環境準備（macOS）
 
```bash
# 方法 1：Homebrew
brew install checkov
 
# 方法 2：pip
python3 -m pip install --user checkov
echo 'export PATH="$(python3 -m site --user-base)/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
 
checkov --version
```
 
> **關於 SSL 警告：** 執行時若出現 `Failed to get the checkov mappings and guidelines from https://api0.prismacloud.io/...` 與 `CERTIFICATE_VERIFY_FAILED`，是 Checkov 嘗試連線下載規則說明失敗，**不影響掃描結果**。若想消除，可執行：
> ```bash
> open "/Applications/Python 3.12/Install Certificates.command"
> ```
 
---
 
## 常用指令
 
| 指令 | 說明 |
|---|---|
| `checkov -d <資料夾> --compact` | 掃描資料夾內所有 `.tf`，跑全部內建規則 |
| `-c <規則ID>` | 只跑指定規則（`--check` 的縮寫） |
| `--soft-fail` | 發現問題時仍回傳結束碼 0，只提出警示 |
| `--external-checks-dir <資料夾>` | 額外載入自訂規則 |
| `--quiet` | 只顯示未通過的項目 |
 
---
 
## 步驟 1：寫一個漏掉設定的子網路
 
**目的：** 觀察 Missing Config 是否會被偵測。
 
`lab1/main.tf`：
 
```hcl
resource "google_compute_subnetwork" "no_flow_logs" {
  name          = "app-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = "asia-east1"
  network       = "projects/demo/global/networks/vpc"
}
```
 
```bash
checkov -d lab1 --compact
```
 
**結果：**
 
| 規則 | 說明 | 結果 |
|---|---|---|
| CKV_GCP_26 | 子網路是否啟用 VPC Flow Logs | FAILED |
| CKV_GCP_74 | 子網路是否啟用 Private Google Access | FAILED |
 
**觀察：** 只寫了最基本的子網路，就有兩項安全設定因為「沒寫」而未通過。未宣告的屬性會沿用預設值，而預設值不一定符合安全基準。
 
---
 
## 步驟 2：補上設定
 
**目的：** 比較「有寫」與「沒寫」的差異。
 
在 `lab1/main.tf` 加上第二個子網路：
 
```hcl
resource "google_compute_subnetwork" "with_flow_logs" {
  name          = "app-subnet-2"
  ip_cidr_range = "10.0.2.0/24"
  region        = "asia-east1"
  network       = "projects/demo/global/networks/vpc"
 
  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
  }
 
  private_ip_google_access = true
}
```
 
```bash
checkov -d lab1 -c CKV_GCP_26 --compact
```
 
**結果：** `no_flow_logs` FAILED，`with_flow_logs` PASSED。
 
**語法筆記：**
- 文字要加引號：`name = "app-subnet-2"`
- 布林值與數字不加引號，且布林值必須小寫：`true` / `false`（`True` 是錯誤寫法）
---
 
## 步驟 3：標註略過
 
**目的：** 觀察例外如何被記錄。
 
在 `lab1/main.tf` 加上第三個子網路：
 
```hcl
resource "google_compute_subnetwork" "skipped" {
  #checkov:skip=CKV_GCP_26:Sandbox subnet, flow logs not required
  name          = "sandbox-subnet"
  ip_cidr_range = "10.0.3.0/24"
  region        = "asia-east1"
  network       = "projects/demo/global/networks/vpc"
}
```
 
```bash
checkov -d lab1 -c CKV_GCP_26 --compact
```
 
**結果：** `skipped` 顯示 SKIPPED，並帶出註解中的原因。
 
**觀察：** 略過原因會留在掃描結果中，之後審查或稽核時都查得到當初略過的依據。
 
---
 
## 步驟 4：檢查強度
 
**目的：** 了解 CI/CD 如何決定要不要擋下部署。
 
```bash
checkov -d lab1 -c CKV_GCP_26 --quiet; echo $?
checkov -d lab1 -c CKV_GCP_26 --quiet --soft-fail; echo $?
```
 
**結果：**
 
| 模式 | 結束碼 | CI/CD 行為 |
|---|---|---|
| 預設 | `1` | 中斷流程，阻擋部署 |
| `--soft-fail` | `0` | 流程繼續，只提出警示 |
 
**觀察：** 這就是「正式環境阻擋、非正式環境警示」的實作方式。
 
---
 
## 步驟 5：規則盲點
 
**目的：** 驗證並非每條規則都能偵測 Missing Config。
 
`lab2/main.tf`：
 
```hcl
resource "google_compute_firewall" "default" {
  name          = "allow-ssh-any"
  network       = "vpc"
  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
 
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}
 
resource "google_compute_firewall" "default2" {
  name          = "allow-all-tcp"
  network       = "vpc"
  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
 
  allow {
    protocol = "tcp"
  }
}
```
 
```bash
checkov -d lab2 --compact
```
 
**結果：**
 
| 規則 | 設定 | 實際開放 | Checkov 結果 |
|---|---|---|---|
| `default` | `ports = ["22"]` | 只開 SSH | CKV_GCP_2 FAILED |
| `default2` | **沒寫 `ports`** | **所有 TCP 連接埠（含 22）** | 防火牆相關檢查**全部 PASSED** |
 
**觀察：**
- 依 Terraform 官方文件，`ports` 未指定時，規則會套用到所有連接埠
- Checkov 的 SSH 檢查只在 `ports` 中包含 22 時才判定未通過；沒寫 `ports` 時沒有東西可比對，直接判定通過
- 連 CKV2_GCP_12（不允許對所有連接埠無限制存取）也沒有抓到
- 風險較大的 `default2` 反而沒有被標示為問題
> **補充：** Ingress 規則若沒有寫 `source_ranges`、`source_tags` 或 `source_service_accounts` 其中之一，Terraform 的 Google Provider 會在 `terraform plan` 階段直接報錯，因此「沒寫來源範圍」在 Terraform 中不會被部署出去，不屬於這裡的盲點。
 
---
 
## 步驟 6：自訂規則補上盲點
 
**目的：** 自己寫一條規則，補上步驟 5 的盲點。
 
`policies/require_ports.yaml`：
 
```yaml
metadata:
  id: "CKV2_MY_GCP_1"
  name: "Ensure firewall allow rules explicitly declare ports"
  category: "NETWORKING"
definition:
  cond_type: attribute
  resource_types:
    - google_compute_firewall
  attribute: allow.ports
  operator: exists
```
 
| 欄位 | 說明 |
|---|---|
| `id` | 自訂規則編號，不能與內建規則重複 |
| `name` | 規則說明，顯示在掃描結果中 |
| `category` | 規則分類 |
| `cond_type: attribute` | 檢查資源的屬性 |
| `resource_types` | 要檢查的資源類型 |
| `attribute: allow.ports` | 要檢查的屬性，`.` 代表 `allow` 區塊內的 `ports` |
| `operator: exists` | 屬性必須存在，否則判定未通過 |
 
```bash
checkov -d lab2 --external-checks-dir policies -c CKV2_MY_GCP_1 --compact
```
 
**結果：** `default` PASSED，`default2` FAILED，盲點被補上。
 
**YAML 格式注意：**
- 只能用空白縮排，不能用 Tab
- 冒號與清單符號 `-` 後面都要有一個空白
---
 
## 步驟 7：把安全設定內建在 Module
 
**目的：** 驗證共用 Module 的安全預設，以及遺漏時的放大效應。
 
`lab3/modules/subnet/main.tf`：
 
```hcl
variable "name" {
  type = string
}
 
variable "ip_cidr_range" {
  type = string
}
 
variable "region" {
  type = string
}
 
variable "network" {
  type = string
}
 
resource "google_compute_subnetwork" "this" {
  name          = var.name
  ip_cidr_range = var.ip_cidr_range
  region        = var.region
  network       = var.network
 
  # 安全預設：一律啟用 Flow Logs
  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
  }
 
  private_ip_google_access = true
}
```
 
`lab3/main.tf`：
 
```hcl
module "app_subnet" {
  source        = "./modules/subnet"
  name          = "app-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = "asia-east1"
  network       = "projects/demo/global/networks/vpc"
}
```
 
```bash
checkov -d lab3 --compact
```
 
**結果：** `module.app_subnet.google_compute_subnetwork.this` PASSED。
 
**再試一次：** 刪除 Module 內的 `log_config` 區塊後重新掃描：
 
```bash
checkov -d lab3 -c CKV_GCP_26 --compact
```
 
**結果：** 變成 FAILED。
 
**觀察：**
- 呼叫端完全沒寫 Flow Logs，但 Module 已內建，因此符合基準
- 呼叫端一個字都沒改，只要 Module 遺漏設定，所有使用這個 Module 的專案都會同時出現同樣的缺口
---
 
## 練習與文章段落對照
 
| 步驟 | 文章段落 |
|---|---|
| 1、2 | Missing Config 為什麼容易被忽略 |
| 1、2 | Checkov 如何發現缺漏的設定 |
| 3、4 | 檢查強度可以依環境調整 |
| 5 | Checkov 的限制：缺漏偵測依規則而異 |
| 6 | Checkov 的限制：企業規範仰賴自訂規則 |
| 7 | 將安全設定內建於 Module |
 
---
 
## 待辦
 
- [ ] 調整步驟 6 的自訂規則，避免誤判 `icmp` 等沒有連接埠的協定（提示：使用 `or:` 組合條件）
- [ ] 自訂一條公司規範，例如 `google_storage_bucket` 必須有 `labels.owner`
- [ ] 在 GitHub Actions 中設定 Checkov，每次 push 自動掃描
## 參考資料
 
- [Checkov 官方文件](https://www.checkov.io/)
- [google_compute_subnetwork（Terraform Provider）](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_subnetwork)
- [google_compute_firewall（Terraform Provider）](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_firewall)
- [CKV_GCP_2 檢查邏輯原始碼](https://github.com/bridgecrewio/checkov/blob/main/checkov/terraform/checks/resource/gcp/AbsGoogleComputeFirewallUnrestrictedIngress.py)
 