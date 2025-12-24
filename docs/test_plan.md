# Test Plan (Requirements-driven)

本書は要求仕様（docs/architecture.md）から逆算して作るテスト項目一覧である。
実装前に合意し、実装は本テスト項目を満たすことを完了条件とする。

## 1. 前提
- UI/Controlは Phoenix LiveView over WebSockets
- イベントは `tap_macro`（payload: `profile`, `button_id`, `request_id`）
- 応答は `macro_ack`（受理/拒否）と `macro_result`（実行結果）
- 実行モデルは「単一実行（直列）」、`panic` は最優先割り込み
- IP制限は HTTP + WebSocket に適用し、loopback（`127.0.0.1` / `::1`）は許可（USB/ADB向け）
- 設定不備は「エラー画面表示→再設定フロー」（プロセスは落とさない）

機械可読なエラーコード/理由は `docs/error_codes.md` を正とする。

## 2. テストレベル
- Unit（Elixir Domain/UseCase）: ExUnit
- Web Integration（Phoenix）: Plug.Test / Phoenix.ConnTest / Phoenix.LiveViewTest
- Contract（Elixir↔NIF）: 期待する型・エラー分類の契約テスト（非Windowsはスタブ）
- Unit（Rust core）: `cargo test`（変換/バリデーション/生成物）
- Windows Smoke（Rust adapters）: 実機/CIのWindowsで限定実行（副作用を最小化）

## 2.1 優先度（P0/P1）
- P0: セキュリティ・設定・実行（直列/busy/panic）・ACK/RESULT・ログ
- P1: セットアップ補助（FW/NIC/mDNS）・運用補助

## 2.2 自動化ポリシー
- P0は原則すべて自動化（ExUnit + LiveViewTest）。実時間sleepを避ける。
- Windows固有の副作用が強い箇所（SendInput等）は、変換/境界をUnitで固め、実機スモークは最小限に留める。

## 3. 受け入れ基準（Definition of Done）
- 主要フロー（設定OK→実行OK、設定不備→再設定、IP不正→拒否、busy→拒否、panic→解放）が結合テストで再現できる
- `profiles.yaml` の不正入力に対し、クラッシュせずエラー画面へ到達できる
- 監査ログ（macro開始/終了、成功/失敗、duration）が出る

※ACK/RESULT の reason/error_code は `docs/error_codes.md` に一致すること。

## 4. テストマトリクス（要件→テスト項目）

### 4.1 Config / profiles.yaml
- AXON-CONF-001: `profiles.yaml` が読み込める（version=1、profiles配列）
- AXON-CONF-002: `version` が欠落/未知値の場合はエラー画面へ遷移（HTTP 200で表示）
- AXON-CONF-003: `profiles` が空/欠落の場合はエラー画面へ遷移
- AXON-CONF-004: buttonの `id` 重複を検出し、該当箇所を示すエラーを返す
- AXON-CONF-005: actionが `down|up|tap|wait|panic` 以外ならエラー
- AXON-CONF-006: `wait` に `key` が含まれる場合はエラー（曖昧さ排除。構造が壊れている扱い）
- AXON-CONF-007: `wait.value` が負数/非数/上限超過ならエラー（0..10_000）
- AXON-CONF-008: sequence長が上限（例: 256）を超える場合はエラー
- AXON-CONF-009: `AXON_PROFILES_PATH` が不正/ファイル不存在の場合はエラー画面へ
- AXON-CONF-010: パス解決の優先順位が仕様通り（env→priv→user）

### 4.2 Key同期（Rust→Elixir）
- AXON-KEY-001: `priv/keycodes.json`（生成物）が読める
- AXON-KEY-002: `profiles.yaml` に未知キーが含まれる場合、エラー画面に profile/button/sequence index を表示
- AXON-KEY-003: 生成物とコミット済みファイルの差分チェック（CI想定）でズレを検知できる

### 4.3 SetupPlug / エラー画面
- AXON-SETUP-001: 未設定状態では `/` など全リクエストが `/setup` にリダイレクトされる
- AXON-SETUP-002: 設定不備は `/setup` のエラー画面に表示され、再設定導線（ファイルパス案内/再読み込み）がある
- AXON-SETUP-003: 設定OKになると通常画面へ遷移できる

### 4.4 Security（IP制限）
- AXON-SEC-001: private IPv4（例: 192.168.0.0/16）からHTTPアクセスは許可
- AXON-SEC-002: public IPv4（例: 8.8.8.8）相当はHTTPで拒否（403）
- AXON-SEC-003: loopback（127.0.0.1 / ::1）は許可（USB/ADB向け）
- AXON-SEC-004: WebSocket(LiveView) 接続でも同様の判定で拒否/許可される
- AXON-SEC-005: 許可レンジ設定変更が反映される（設定値で制御）

### 4.5 LiveView event（tap_macro/ack/result）
- AXON-LV-001: `tap_macro` を送ると、即時に `macro_ack(accepted)` が返る（通常時）
- AXON-LV-002: 不正payload（missing field等）は `macro_ack(rejected, invalid_request)`
- AXON-LV-003: 未設定状態では `macro_ack(rejected, not_configured)`
- AXON-LV-004: マクロ不存在は `macro_ack(rejected, not_found)`
- AXON-LV-005: Engine未利用可能は `macro_ack(rejected, engine_unavailable)`
- AXON-LV-006: 実行完了で `macro_result(ok)` が返る
- AXON-LV-007: 実行失敗（NIF error等）で `macro_result(error, error_code, message)`（error_codeは `docs/error_codes.md` に一致）

### 4.6 実行モデル（直列 / busy / panic / 連打）
- AXON-EXEC-001: 2つの `tap_macro` を並列に送ると、2つ目は `busy` で拒否される
- AXON-EXEC-002: 同一クライアントから100ms未満の連打は `busy` 相当で拒否される
- AXON-EXEC-003: `panic` は実行中マクロを中断し、直ちに `macro_result(panic)` になる
- AXON-EXEC-004: `panic` 実行後、次のマクロ要求は仕様通り（MVP: 復帰まで拒否）
- AXON-EXEC-005: サーバ停止シグナル時に panic が必ず呼ばれる（統合テスト/最小スモーク）

### 4.7 :wait の扱い
- AXON-WAIT-001: wait=0 は許可され、順序が保持される
- AXON-WAIT-002: wait=10_000 は許可される（ただし結合テストでは仮想時間/短縮で検証）
- AXON-WAIT-003: 合計waitが上限（例: 30秒）を超えると拒否（仕様通り）

### 4.8 WebSocket Timeout（3秒の意味）
- AXON-WS-001: `macro_result` が3秒以内に返らない場合、クライアント側のタイムアウト判定に必要な情報が不足しない（ACKは即時）
- AXON-WS-002: 長いマクロ（>3秒想定）では誤検知が起きうるため、閾値変更が可能（設定値で制御）

### 4.9 ログ（監査）
- AXON-LOG-001: macro開始ログが出る（profile/button_id/request_id）
- AXON-LOG-002: macro終了ログが出る（result, duration_ms）
- AXON-LOG-003: error時も終了ログが出る（result=error）

## 5. Rust側（NIF）テスト項目

### 5.1 core（副作用なし）
- AXON-RUST-CORE-001: `Action` 列→`SendInput`向け構造への変換が境界条件で落ちない
- AXON-RUST-CORE-002: 最大アクション数超過を拒否
- AXON-RUST-CORE-003: wait範囲/合計上限を拒否
- AXON-RUST-CORE-004: `keycodes.json` 生成が決定的（安定）である

### 5.2 Windows adapters（限定スモーク）
- AXON-RUST-WIN-001: `send_input` が呼べる（危険なため入力内容は最小、またはモック可能にする）
- AXON-RUST-WIN-002: `run_privileged_command` は拒否時を判定できる（ユーザーがキャンセルしたケース）
- AXON-RUST-WIN-003: `get_nic_capabilities` が失敗時に分類されたエラーを返す
- AXON-RUST-WIN-004: `start_mdns_broadcast` が開始/停止できる

## 6. 備考（テスト実装上の推奨）
- `:wait` を含む結合テストは、実時間スリープを避けるために UseCase に「Clock（Port）」を注入して仮想時間で検証する
- LiveViewテストは `handle_event` の戻り/イベントpushを検証し、`macro_result` の非同期送信は `assert_receive` 等で確認する

## 7. テスト実装の前提を固定する（重要）
- reason/error_code は `docs/error_codes.md` を唯一の正とし、テストは文字列一致で検証する
- HTTPの拒否ステータス、setupのredirect/200挙動は `docs/error_codes.md` の通り
