# Section 1: System Overview & Architecture

## 1.1 目的
Android端末を操作端末とし、Windows PC上のターゲットアプリに対して低遅延・高信頼なマクロ（キー入力等）を送信する。

## 1.2 アーキテクチャ図


## 1.3 構成要素
- **Client (Android):** Kotlin + WebView (Thin Client)
- **Backend (Windows):** Elixir 1.15+ / Phoenix 1.8 (Business Logic & UI Delivery)
- **Engine (Native):** Rust 1.70+ / Rustler (Windows API Bridge)

## 1.4 通信スタック
- **UI/Control:** Phoenix LiveView over WebSockets
- **Discovery:** mDNS (Multicast DNS) over UDP 5353
- **Low-Level:** Win32 API (SendInput)

# Section 2: Backend Server (Elixir/Phoenix)

## 2.1 主要コンポーネント
- **ConfigManager:** - `profiles.yaml` を読み込み、Ecto Schemaでバリデーション。
    - 不正なキーコードが存在する場合は、エラー画面を表示し再設定フローへ誘導する（プロセスを落とさない）。
    - 入力上限（Boundary Check）をElixir側でもバリデーションする。
- **MacroChannel:** - Androidからの `tap_macro` イベントを受信。
    - 実装は Phoenix LiveView の `handle_event/3` をデファクトとして採用する（※「Channel」は論理名）。
    - シーケンス（down -> wait -> up）を非同期に制御。
- **SetupPlug:** - 未設定時、全リクエストを `/setup`（ウィザード）へ強制リダイレクト。

## 2.2 データ型定義 (Macro Sequence)
マクロは以下の構造で管理する。
- `action`: :down | :up | :tap | :wait | :panic
- `key`: :vk_a | :vk_lshift | ... (Rustler Enumと完全同期)
- `value`: Integer (waitアクション時のミリ秒)

## 2.3 LiveViewイベント仕様（提案）
### `tap_macro`
Android(WebView) から LiveView に送るイベント。

- event: `"tap_macro"`
- payload（最小MVP）:
  - `"profile"`: String（例: `"Development"`）
  - `"button_id"`: String（例: `"save_all"`）
  - `"request_id"`: String（UUID推奨。重複排除・相関ID用）

### 応答イベント（サーバ -> クライアント）
接続品質表示や3秒ルールのため、受理(ACK) と 実行結果(RESULT) を分ける。

- `"macro_ack"`:
  - `"request_id"`
  - `"status"`: `"accepted" | "rejected"`
  - `"reason"`: `"busy" | "not_configured" | "invalid_request" | "not_found" | "engine_unavailable"`（rejected時）
- `"macro_result"`:
  - `"request_id"`
  - `"status"`: `"ok" | "error" | "canceled" | "panic"`
  - `"error_code"`: String（error時、機械可読）
  - `"message"`: String（error時、表示用）

## 2.4 マクロ実行モデル（推奨）
低遅延・高信頼（スタックキー防止）を優先し、MVPはシンプルにする。

- 実行は原則「単一実行（グローバル直列）」
  - 同時実行は許可しない
  - 実行中に `tap_macro` が来た場合は `macro_ack: rejected, reason: busy`
- `:panic` は最優先の割り込み
  - 実行中のマクロを中断し、直ちに Engine の panic（全キー解放）を実行
  - 以後のリクエストは正常復帰まで拒否 or キュー破棄（MVPでは拒否を推奨）
- 連打対策
  - 同一クライアントからの `tap_macro` は最低間隔（例: 100ms）を設け、超過は `busy` 相当で拒否
- 例外/切断時
  - サーバ終了シグナル受信時、必ず panic を実行
  - WebSocket切断検知時も、必要に応じて panic を実行（安全優先）

## 2.5 `:wait` 仕様（推奨）
- 単位: ms
- 許容範囲: `0..10_000` ms（MVP）
  - 0msは許可（連続入力として扱う）
- 最小分解能: 1msで受け付けるが、Windowsの実際のスリープ精度は環境依存（概ね数ms〜15ms程度に丸められ得る）
- 合計時間の上限（推奨）: 30秒

## 2.6 ログ（要件反映）
誰が実行したかは不要。どのマクロをいつ実行し成功/失敗したかを残す。

- `macro_exec_started`: `timestamp`, `profile`, `button_id`, `request_id`
- `macro_exec_finished`: `timestamp`, `profile`, `button_id`, `request_id`, `result(ok|error|canceled|panic)`, `duration_ms`

# Section 3: Native Engine (Rust/Rustler)

## 3.1 厳格な型安全マッピング
`windows-rs` の定数と1対1で対応する `NifUnitEnum` を実装。

## 3.2 具備すべき関数 (NIFs)
1. `send_input(actions: Vec<Action>)`: 仮想入力の発行。
2. `get_nic_capabilities()`: NICの並立性（Station + P2P）を `WlanQueryInterface` で取得。
3. `run_privileged_command(cmd: String)`: `ShellExecuteExW` を `runas` で叩きUAC昇格を実行。
4. `start_mdns_broadcast(name: String, port: u16)`: `mdns-sd` によるサービス広報。

## 3.3 安全対策
- **Panic Mechanism:** すべての物理キーを解放する `key_up` シーケンスをネイティブ層で保持。
- **Boundary Check:** 入力バッファのオーバーフロー防止。

# Section 4: Android Client (Kotlin Wrapper)

## 4.1 WebView 実装要件
- **JavaScript Interface:** LiveViewからの `vibrate` 通知を受け取り、`Vibrator` APIを叩く。
- **Error Handling:** `onReceivedError` をフックし、接続失敗時に再ディスカバリ画面を表示。

## 4.2 ネイティブ制御
- **Power Management:** `FLAG_KEEP_SCREEN_ON` による常時点灯。
- **NsdManager:** - `_awme-macro._tcp` サービスをスキャン。
    - 解決されたIP:Portへ自動的にWebViewを遷移させる。

## 4.3 ネットワーク接続優先順位
1. USB (ADB port forwarding: 4000)
2. Wi-Fi Direct (P2P Group Ownerへの接続)
3. Local LAN (mDNS解決)

# Section 5: Infrastructure & Security

## 5.1 Windows Firewall 自動設定 (Setup Wizard)
ウィザード経由で実行されるPowerShellスクリプトの要件：
- **Name:** "AWME_Macro_Engine"
- **Protocol:** UDP/5353 (In), TCP/4000 (In)
- **Profile:** Private のみ許可
- **Scope:** LocalSubnet のみ許可

## 5.2 ネットワーク診断 (Pre-flight Check)

- NICごとに `Station + P2P` の同時実行可否をフラグで明示。
- 現在のネットワークプロファイルが「パブリック」な場合は警告を表示。
- ネットワークプロファイル判定は環境/権限により誤判定する可能性があるため、UIに注意書きを明記する。

## 5.3 セキュリティ
- サーバー側で `RemoteAddress` を検証し、プライベートIPレンジ以外からの接続を拒否。
  - HTTPリクエストだけでなく WebSocket(LiveView) 接続にも適用する。
  - USB(ADB port forwarding/reverse) 利用を考慮し、Loopback（`127.0.0.1` / `::1`）は許可する（推奨）。
  - 許可レンジは設定可能にし、将来の運用で調整できるようにする。

# Section 6: Macro Grammar & Key Mapping

## 6.1 キーコード・エイリアス表 (MVP範囲)
| 定数名 | 文字列表現 | OS定数 (Win32) |
| :--- | :--- | :--- |
| :vk_a | "VK_A" | 0x41 |
| :vk_lcontrol | "VK_LCTRL" | 0xA2 |
| :vk_return | "VK_ENTER" | 0x0D |
| ... | ... | ... |

## 6.2 YAML記述仕様
```yaml
version: 1
profiles:
  - name: "Development"
    buttons:
      - id: "save_all"
        label: "Save All"
        sequence:
          - { action: "down", key: "VK_LCTRL" }
          - { action: "down", key: "VK_LSHIFT" }
          - { action: "tap",  key: "VK_S" }
          - { action: "up",   key: "VK_LSHIFT" }
          - { action: "up",   key: "VK_LCTRL" }
```

## 6.3 Rustler Enum同期（推奨）
「Rust側のキー定義」を唯一の正とし、Elixir側のキーリストは生成して同期する。

- 推奨: Rustビルド時に `priv/keycodes.json`（または `.yaml`）を生成し、Elixirはそれを読み込んで `Key` の一覧/バリデーションを構築
- CIで「生成物とコミット済みファイルの差分が無い」ことをチェックし、ズレを検出する
- MVPのキー表にないキーが `profiles.yaml` に含まれる場合
  - 起動後にエラー画面を表示し、該当箇所（profile/button/sequence index）を示して再設定を促す

## 6.4 `profiles.yaml` の配置と互換性（推奨）
- バージョニング
  - トップレベルに `version` を必須とし、後方互換が必要な場合はサーバ側でマイグレーション関数を用意する
- パス解決（優先順）
  1. 環境変数 `AXON_PROFILES_PATH`
  2. アプリ同梱のデフォルト（例: `priv/profiles.yaml`）
  3. ユーザー編集用の外部ファイル（Windows想定: `%LOCALAPPDATA%/Axon/profiles.yaml` 等）

# Section 7: Lifecycle & Operations

## 7.1 起動プロセス
1. 実行ファイル（またはmix phx.server）を起動。
2. 設定ファイル読み込み。不備があればブラウザでエラー表示。
3. NICを選択し、FW設定（必要時）を実行。
4. mDNS広報開始。

## 7.2 終了・クリーンアップ
- 終了シグナル受信時、Rust側で `panic` 命令（全キー解放）を実行。
- mDNSの `Unregister` を実行。

## 7.3 トラブルシューティング
- **WebSocket Timeout:** Android側で3秒以上反応がない場合、接続インジケータを赤転。
  - 推奨: 3秒判定は `macro_result`（実行完了）を基準とする。ただし長いマクロでは誤検知が増えるため、必要に応じて閾値を引き上げる。
  - 代替案（将来）: 接続健全性(ACK/heartbeat) と 実行完了(result) を別インジケータに分離する。
- **UAC Denial:** UACが拒否された場合、手動設定用のPowerShellコマンドを画面にコピー可能にする。

# Section 8: Clean Architecture & Testing Strategy

## 8.1 クリーンアーキテクチャ方針
本プロジェクトはクリーンアーキテクチャを採用し、依存方向を「外側 → 内側」に固定する。

- 内側（Domain/UseCase）は Phoenix/Rustler/Windows API に依存しない
- 外側（Web/Infra/Native）は内側に依存してよい
- 例外（妥協）: Phoenix LiveView のイベント受信はFrameworkに属するため、UseCase呼び出しの薄いアダプタ層として実装する

## 8.2 Elixir側のレイヤ案
### Entities（Domain）
- `Macro`, `Action`, `Key`, `Profile`, `Button` などの純粋データと不変条件

### UseCases（Application）
- `LoadConfig`（設定ロード/検証）
- `ExecuteMacro`（直列実行・panic・連打抑制・ログ）
- `GetNicCapabilities` / `SetupFirewall` / `StartMdns`（セットアップ）

### Interface Adapters
- `ConfigGateway`（YAML読み書き、パス解決）
- `EngineGateway`（Rustler/NIF呼び出しのポート実装）
- `Security`（RemoteAddress判定ユーティリティ、Plug/Socketで使用）
- `Presenter`（エラー画面表示用の整形）

### Frameworks & Drivers
- Phoenix（Router/Plug/LiveView）
- Logger/Telemetry

## 8.3 Rust側のレイヤ案
### Core（Domain/UseCase）
- `Action`/`Key` の型、入力変換、バウンダリチェック、`keycodes.json` 生成
- Windows API への直接依存を避け、トレイト（Port）で抽象化

### Adapters（Windows）
- `SendInput` 実装
- `WlanQueryInterface` 実装
- `ShellExecuteExW` 実装
- `mdns-sd` 実装

### Framework（Rustler NIF）
- NIFのエントリポイント・型変換（Erlang term ↔ Rust型）

## 8.4 テスト戦略（要件起点）
要件から先にテスト項目を定義し、実装が後追いで満たす。

- Domain/UseCase: 単体テスト（副作用なし、決定的）
- Adapter: 契約テスト（境界の型/エラー分類）
- Web: LiveView/Plug 結合テスト（イベント→ACK/RESULT、IP制限、SetupPlug）
- Native: 純Rust単体テスト + Windows限定スモーク（副作用を最小化）

具体的なテスト項目は `docs/test_plan.md` にまとめる。

実装タスクとテスト項目の紐づけ（トレーサビリティ）は `docs/implementation_plan.md` にまとめる。