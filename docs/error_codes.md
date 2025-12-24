# Error Codes / Reasons (Frozen for Tests)

本書はテストが依存する「機械可読なコード」を固定する。
実装は本書に合わせ、追加/変更は必ず docs/test_plan.md の更新とセットで行う。

## 1. LiveView event

### 1.1 `macro_ack.reason`（rejected時）
- `busy`: 実行中、または連打抑制により受付不可
- `not_configured`: セットアップ未完了、または設定エラー状態
- `invalid_request`: payload不備（必須フィールド欠落、型不正）
- `not_found`: `profile` / `button_id` が見つからない
- `engine_unavailable`: NIF未ロード、非Windows、またはEngine起動不可
- `forbidden`: IP制限等で操作が許可されない

### 1.2 `macro_result.status`
- `ok`
- `error`
- `canceled`
- `panic`

### 1.3 `macro_result.error_code`（status=error時）
- `E_CONFIG_INVALID`: 設定（profiles.yaml/キー同期）不備
- `E_MACRO_NOT_FOUND`: マクロが見つからない
- `E_ENGINE_UNAVAILABLE`: Engine未利用可能
- `E_ENGINE_FAILURE`: Engine実行失敗（SendInput等）
- `E_TIMEOUT`: 実行タイムアウト（将来導入時）
- `E_FORBIDDEN`: 権限/IP制限違反
- `E_INTERNAL`: 想定外例外

## 2. HTTP / WebSocket

### 2.1 IP制限（RemoteAddress）
- HTTP: 拒否は `403` を基本
- WebSocket(LiveView): 接続拒否（接続確立しない）を基本

### 2.2 Setup
- SetupPlug により、未設定時は `302` で `/setup` へ誘導
- `/setup` 自体は `200` でエラー詳細を表示
