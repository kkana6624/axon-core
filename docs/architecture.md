# Section 1: System Overview & Architecture

## 1.1 目的
Android端末を操作端末とし、Windows PC上のターゲットアプリに対して低遅延・高信頼なマクロ（キー入力等）を送信する。

## 1.2 アーキテクチャ図


## 1.3 構成要素
- **Client (Android):** Kotlin + WebView (Thin Client)
- **Backend (Windows):** Elixir 1.15+ / Phoenix 1.7 (Business Logic & UI Delivery)
- **Engine (Native):** Rust 1.70+ / Rustler (Windows API Bridge)

## 1.4 通信スタック
- **UI/Control:** Phoenix LiveView over WebSockets
- **Discovery:** mDNS (Multicast DNS) over UDP 5353
- **Low-Level:** Win32 API (SendInput)

# Section 2: Backend Server (Elixir/Phoenix)

## 2.1 主要コンポーネント
- **ConfigManager:** - `profiles.yaml` を読み込み、Ecto Schemaでバリデーション。
    - 不正なキーコードが存在する場合は起動時にFail-fast。
- **MacroChannel:** - Androidからの `tap_macro` イベントを受信。
    - シーケンス（down -> wait -> up）を非同期に制御。
- **SetupPlug:** - 未設定時、全リクエストを `/setup`（ウィザード）へ強制リダイレクト。

## 2.2 データ型定義 (Macro Sequence)
マクロは以下の構造で管理する。
- `action`: :down | :up | :tap | :wait | :panic
- `key`: :vk_a | :vk_lshift | ... (Rustler Enumと完全同期)
- `value`: Integer (waitアクション時のミリ秒)

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

## 5.3 セキュリティ
- サーバー側で `RemoteAddress` を検証し、プライベートIPレンジ以外からの接続を拒否。

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
- **UAC Denial:** UACが拒否された場合、手動設定用のPowerShellコマンドを画面にコピー可能にする。