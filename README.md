# lambda-promtail for CloudTrail

CloudTrailログをS3からLokiに転送するためのTerraform構成です。

## アーキテクチャ

```
CloudTrail → S3バケット → S3イベント通知 → SQS → Lambda → Loki
```

## 前提条件

- Terraform >= 1.6
- AWS CLI設定済み
- CloudTrailログが保存されているS3バケット

## 使い方

### 1. 設定ファイルの作成

```bash
cp terraform.tfvars.example terraform.tfvars
```

### 2. terraform.tfvarsを編集

```hcl
aws_region    = "ap-northeast-1"
write_address = "https://your-loki-url/loki/api/v1/push"
cloudtrail_bucket_name = "your-cloudtrail-bucket-name"

# 認証が必要な場合
username = "your-username"
password = "your-password"
```

### 3. lambda-promtail.zipのダウンロード

```bash
curl -L -o lambda-promtail.zip \
  "https://grafanalabs-cf-templates.s3.amazonaws.com/lambda-promtail/lambda-promtail.zip"
```

### 4. デプロイ

```bash
terraform init
terraform plan
terraform apply
```

---

## Grafana/Lokiでのクエリ方法

```logql
{__aws_log_type="s3_cloudtrail"}
```

---

## GrafanaでのTransformations設定

CloudTrailログをテーブル形式で見やすく表示するには、GrafanaのTransformationsを使用します。

### 1. Extract fields（フィールド抽出）

ログ行のJSONからフィールドを抽出します。

| 設定項目 | 値 |
|----------|-----|
| Source | `labels` |
| Format | `JSON` |
| Replace all fields | `ON` |
| Keep time | `OFF` |

### 2. Organize fields by name（フィールド整理）

抽出したフィールドの順序変更・リネーム・非表示を設定します。

| 設定項目 | 値 |
|----------|-----|
| Field order | `Manual` |

#### 推奨するフィールドのリネーム

| 元のフィールド名 | リネーム後 |
|------------------|-----------|
| `eventTime` | イベント時間 |
| `eventName` | イベント名 |
| `eventID` | イベントID |
| `eventSource` | イベントソース |
| `eventType` | イベントタイプ |
| `awsRegion` | リージョン |
| `sourceIPAddress` | ソースIP |
| `errorCode` | エラーコード |
| `errorMessage` | エラーメッセージ |
| `readOnly` | 読み取り専用 |
| `userIdentity_sessionContext_sessionIssuer_userName` | ユーザー名 |
| `userIdentity_accessKeyId` | アクセスキー |

不要なフィールドは目のアイコンをクリックして非表示にできます。

### 設定手順

1. **パネルを作成**: Visualization を `Table` に設定
2. **クエリを入力**: `{__aws_log_type="s3_cloudtrail"} | json`
3. **Transform タブを開く**
4. **Add transformation → Extract fields** を追加
   - Source: `labels`
   - Format: `JSON`
   - Replace all fields: ON
   - Keep time: OFF
5. **Add transformation → Organize fields by name** を追加
   - Field order: Manual
   - 必要なフィールドを上部にドラッグ
   - フィールド名を日本語にリネーム
   - 不要なフィールドを非表示

---

## 削除

```bash
terraform destroy
```
