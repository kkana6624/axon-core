# Implementation Plan (Clean Architecture + Traceability)

本書は Clean Architecture のレイヤ構成に基づき、実装タスクをフェーズ分割し、
各タスクが満たすべきテスト項目（docs/test_plan.md のID）に紐づける。

## 0. ゴール
- Elixir(Phoenix LiveView) が `tap_macro` を受け、ACK/RESULT を返し、直列実行で Engine(NIF) を安全に叩く
- 設定不備はクラッシュせずエラー画面→再設定フロー
- HTTP + WebSocket に RemoteAddress 制限
- 監査ログ（macro開始/終了、成功/失敗、duration）

## 1. 依存方向（再掲）
- Domain/UseCase は Phoenix/Rustler/Windows API に依存しない
- Adapter/Framework が Domain/UseCase を呼ぶ

## 2. Elixir モジュール配置案（例）

### 2.1 Entities（Domain）
- `Axon.Domain.Macro`
- `Axon.Domain.Action`
- `Axon.Domain.Key`
- `Axon.Domain.Profile`

### 2.2 UseCases（Application）
- `Axon.App.LoadConfig`
- `Axon.App.ExecuteMacro`
- `Axon.App.Setup.GetNicCapabilities`
- `Axon.App.Setup.SetupFirewall`
- `Axon.App.Setup.StartMdns`

### 2.3 Interface Adapters
- `Axon.Adapters.Config.YamlConfigGateway`
- `Axon.Adapters.Engine.RustlerGateway`
- `Axon.Adapters.Security.RemoteAddress`
- `Axon.Adapters.Presentation.SetupPresenter`

### 2.4 Frameworks & Drivers
- `AxonWeb.SetupLive`（setup画面）
- `AxonWeb.MacroLive`（操作UI/イベント受信）
- `AxonWeb.Plugs.SetupPlug`
- `AxonWeb.Plugs.RemoteAddressPlug`（HTTP）
- `AxonWeb.SocketGuards.RemoteAddress`（WS）

※実際の命名/ファイル配置は既存 `AxonWeb` の慣例に合わせて調整する。

## 3. Rust（Engine）配置案（例）

- `native/axon_engine/`
  - `src/core/`（Domain/UseCase: 変換・バリデーション・keycodes生成）
  - `src/windows/`（Adapters: SendInput/Wlan/ShellExecute/mdns）
  - `src/nif/`（Rustler NIF: term変換・公開関数）

## 4. フェーズ別タスク（MVP順）

### Phase A: 設定・型・バリデーション（副作用なし）
**A1. Domain型 + Ectoスキーマ（embedded）**
- 内容: Macro/Action/Key/Profile/Button の型と不変条件、Ecto changeset
- 完了条件（Tests）: AXON-CONF-001, 003, 004, 005, 007, 008

**A2. YAML読込 + パス解決**
- 内容: `AXON_PROFILES_PATH` 優先、同梱/ユーザー領域フォールバック
- 完了条件（Tests）: AXON-CONF-009, 010

**A3. Key同期（生成物読込）**
- 内容: `priv/keycodes.json` から許可キー一覧をロードして検証
- 完了条件（Tests）: AXON-KEY-001, 002

### Phase B: 安全（Security/Setupの骨格）
**B1. SetupPlug + ルーティング + エラー画面（最小）**
- 内容: 未設定/設定エラー時に `/setup` へ誘導し、エラー詳細を表示
- 完了条件（Tests）: AXON-SETUP-001, 002, 003

**B2. RemoteAddress 制限（HTTP + WebSocket）**
- 内容: private/loopback許可、public拒否、設定で調整可能
- 完了条件（Tests）: AXON-SEC-001..005

### Phase C: 実行パイプライン（NIFはスタブでも可）
**C1. マクロ実行ランナー（直列化）**
- 内容: 単一実行、busy拒否、request_id相関、ログ出力、Clock注入
- 完了条件（Tests）: AXON-EXEC-001, AXON-WAIT-001..003, AXON-LOG-001..003

**C2. LiveViewイベント（tap_macro/ack/result）**
- 内容: payload検証→ACK→非同期RESULT
- 完了条件（Tests）: AXON-LV-001..007, AXON-WS-001

**C3. 連打抑制 + panic割り込み**
- 内容: rate limit、panic即時、以後の受付方針（MVP: 復帰まで拒否）
- 完了条件（Tests）: AXON-EXEC-002..004

### Phase D: セットアップ機能（FW/NIC/mDNS）
**D1. FW設定（UAC/コピー対応）**
- 内容: `run_privileged_command` 失敗時に手動コマンドを提示
- 完了条件（Tests）: （Web側の画面/分岐を結合テストで確認。Rust側は AXON-RUST-WIN-002）

**D2. NIC診断 + mDNS開始**
- 内容: `get_nic_capabilities` 表示、`start_mdns_broadcast` 開始/停止
- 完了条件（Tests）: AXON-RUST-WIN-003, 004（Rust側）

## 5. Rustフェーズ（Elixirと並行可能）

### Rust-A: core（変換・バリデーション・生成物）
- 完了条件（Tests）: AXON-RUST-CORE-001..004

### Rust-B: Windows adapters（SendInput等）
- 完了条件（Tests）: AXON-RUST-WIN-001..004

### Rust-C: NIF公開API（契約）
- 完了条件（Tests）: AXON-LV-007（engine_unavailableの扱い含む）, AXON-EXEC-003（panic）

## 6. 重要な決定事項（実装前に固定）
- busy時は拒否（キューなし）
- 3秒タイムアウトは `macro_result` 基準（ACKは即時）
- loopback許可（USB/ADB向け）
- `:wait` は 0..10_000ms、合計30秒（MVP）

## 7. 次に書くべきドキュメント（任意）
- `docs/error_codes.md`: `macro_ack.reason` / `macro_result.error_code` の一覧（テストが依存するため優先度高）
- `docs/config_reference.md`: profiles.yaml の完全スキーマ、例、移行方針
