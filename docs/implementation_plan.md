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

### Phase A0: 設定管理の再設計（中央集権 + テスト安定化）
**A0-1. ConfigProvider Behavior を定義**
- 内容: `Axon.App.ConfigProvider` を定義し、UseCase/Webが依存する唯一の窓口にする
  - `get_config/0`（現在のConfigを返す）
  - `subscribe/0`（変更通知を受け取れるようにする。内部がPubSubでもコールバックでも良い）
  - （任意）`reload/0`（明示リロード。Setup画面の「再読み込み」で使用）
- 完了条件（Tests）: 設定取得が「実装詳細（プロセス名/トピック）」に依存しないことを結合テストで確認

**A0-2. Production実装: ConfigStore（GenServer）**
- 内容: `ConfigStore` を `Axon.Application` の supervision tree に常駐させ、メモリキャッシュ＋変更通知を提供
  - 初期ロード: `LoadConfig.load/1`
  - 変更検知: ファイル監視（既存のfile_system等）またはポーリング（最小）
  - 通知: Phoenix.PubSub の固定 topic（例: `"config"`）で `{:config_updated, version}` を broadcast
- 重要: name は固定（Productionは単一インスタンス）。テストは Static 実装へ差し替える

**A0-3. Test実装: StaticConfigProvider（プロセス不要）**
- 内容: テストでは `StaticConfigProvider` を `Application.put_env(:axon, :config_provider, ...)` で注入
  - `get_config/0` は固定の `%LoadConfig.Config{}` を返す
  - `subscribe/0` は no-op（またはテストプロセスへ直接 send するだけ）
- 完了条件（Tests）: ExUnit asyncでも `:already_started` が起きない

**A0-4. プロビジョニングの分離（ProvisionProfiles）**
- 内容: 初回コピーを `ProfilesPath.resolve/1` から分離し、起動直後に一度だけ実行
  - 例: `Axon.App.Setup.ProvisionProfiles.ensure_present/1`
- 完了条件（Tests）: resolve/loadを複数回呼んでも副作用（ファイル生成）が繰り返されない

**A0-5. LiveView/TapMacroの利用モデルを統一**
- 内容: LiveView/TapMacro は `ConfigProvider` だけを見る
  - LiveViewは mountで `get_config/0`、connected時に `subscribe/0` し、通知を受けたら再取得
  - Timerによる定期 `LoadConfig.load/0` を撤廃（I/Oとレースの温床）
- 完了条件（Tests）: 設定変更通知→再取得が `assert_receive` で決定的に検証できる

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

## 6.1 依存性Do/Don't（実装チェックリスト）
Clean Architecture の依存方向を崩すと、テスト不安定・競合・レースの温床になるため、実装レビューで必ず確認する。

### Do（やる）
- UseCase/Domain は「抽象（Behavior/Port）」に依存させる（例: `ConfigProvider`）
- DIは「Behavior実装モジュール」を注入する（`Application.get_env/3` などで切替）
- 通知は固定Topic＋「通知が来たら再取得」モデルにする（LiveViewは状態差分を直接持ち回らない）
- プロビジョニング（初回ファイル生成）は起動直後に1回だけのUseCaseとして分離する
- テストは決定性を最優先し、原則プロセス無しのProvider（Static）で検証する（async耐性）

### Don't（やらない）
- LiveView/UseCaseが `GenServer` の `name:`（名前付きプロセス）や `whereis` を前提にする
- `profiles.yaml` を「設定取得のたびに」ディスクから読み直す（I/O増＋レース増）
- URL/クエリでモジュール名・プロセス名を渡してDIする（LiveViewライフサイクルと変換で破綻しやすい）
- 動的Topic（テストごとに変わるtopic名等）を増やして購読管理を複雑化する
- タイマーで定期再ロードして“なんとなく同期”させる（本質的な境界問題を隠すだけ）

## 7. 次に書くべきドキュメント（任意）
- `docs/error_codes.md`: `macro_ack.reason` / `macro_result.error_code` の一覧（テストが依存するため優先度高）
- `docs/config_reference.md`: profiles.yaml の完全スキーマ、例、移行方針
