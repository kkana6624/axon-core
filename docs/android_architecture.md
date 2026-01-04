# Android Client Architecture (Thin Client + WebView)

本書はサーバ側設計（`docs/architecture.md`）を前提に、Android専用アプリ（Kotlin + WebView）の設計を定義する。
MVPは「サーバが配信するLiveView UIをWebViewで表示し、接続・ディスカバリ・最小のネイティブ連携（バイブ等）だけを担う」thin client とする。

---

## 1. 目的 / スコープ

### 1.1 目的
- Android端末から、Windows PC 上の Axon Backend（Phoenix LiveView）に接続し、低遅延でマクロ操作を行う。
- 接続の確立・再接続・エラー表示・ディスカバリをAndroid側で安定化し、UI本体はサーバ配信（LiveView）で一元管理する。

### 1.2 スコープ（MVP）
- サーバの発見（優先順位: USB/ADB → Wi‑Fi Direct → LAN mDNS）
- WebViewでのUI表示（`http://<host>:4000/`）
- WebViewの接続失敗/切断時のリカバリ（再探索・再接続導線）
- JavaScript Interface による最小ネイティブ機能
  - `vibrate` 通知を受けて `Vibrator` API を実行
- 画面は必要最小限（ディスカバリ、接続中、WebView、エラー）

### 1.3 非スコープ（MVPではやらない）
- Android側にマクロ定義やプロフィールを保持すること（Single Source of Truthはサーバの `profiles.yaml`）
- Android側でPhoenixイベントを独自実装すること（WebView内のLiveViewが実行する）
- ユーザー管理、端末識別、履歴同期

---

## 2. 前提・整合性（サーバ設計との対応）

- UI/Control は Phoenix LiveView over WebSockets（WebView内）
- Discovery は mDNS（`_awme-macro._tcp`）を利用（LAN）
- 3秒ルール（接続品質）はサーバの `macro_ack` / `macro_result` を基準に設計されている
  - ただしMVPのAndroidネイティブ層は ACK/RESULT を直接扱わず、LiveView UI に委譲する
- Androidは USB(ADB port forwarding: 4000) を最優先として使える（開発/運用の簡便性）

---

## 3. ユースケース（MVP）

1. ユーザーがアプリ起動
2. アプリが接続先を解決（USB → Wi‑Fi Direct → mDNS）
3. 解決できたらWebViewを起動して `http://<resolved-host>:4000/` を開く
4. LiveView UI が表示され、ユーザーはボタン操作（`tap_macro` 等）を行う
5. 接続失敗/切断が起きた場合、アプリは「再接続」または「再探索」へ戻す

---

## 4. 画面（最小）

### 4.1 Discovery画面
- 状態表示: 「探索中」/「候補が見つかった」/「見つからない」
- 操作:
  - 自動探索開始（起動直後）
  - 手動リトライ
  - （任意・開発用）手入力でホスト/ポート指定

### 4.2 Connecting画面
- 解決した host:port に対して到達性を軽くチェック（HTTP GET など）
- 成功したらWebView画面へ遷移
- 失敗したらエラー画面へ

### 4.3 WebView画面
- サーバ配信UI（LiveView）を表示
- 端末は `FLAG_KEEP_SCREEN_ON` でスリープしない
- WebView内エラー（`onReceivedError` 等）で切断検知→エラー画面へ

### 4.4 Error画面
- 失敗理由（例: 解決不能 / 接続不可 / タイムアウト / 証明書エラー等）を最小限表示
- 操作:
  - 再接続（同じ host:port で再試行）
  - 再探索（Discovery画面へ戻る）

---

## 5. モジュール設計（推奨）

MVPでも責務を分離し、テスト容易性と事故率を下げる。

### 5.1 `discovery`（接続先解決）
- `EndpointResolver`（インターフェース）
  - `suspend fun resolve(): ResolvedEndpoint?`
- 実装（優先順で試す）
  1. `AdbEndpointResolver`
     - 前提: 利用者がPC側で `adb forward tcp:4000 tcp:4000` 等を設定
     - 解決結果: `127.0.0.1:4000`
  2. `WifiDirectEndpointResolver`
     - Wi‑Fi Directのグループ情報/接続先IP解決（将来拡張。MVPではスタブ可）
  3. `MdnsEndpointResolver`
     - `NsdManager` で `_awme-macro._tcp` を探索→解決→`InetAddress` と port を取得

### 5.2 `webview`（WebViewホスト）
- `AxonWebViewClient`
  - URLロード制限（許可する host:port のみ）
  - `onReceivedError` / `onReceivedHttpError` / `onReceivedSslError` を握り、状態をUIへ通知
- `AxonWebChromeClient`
  - コンソールログ（debugビルドのみ）

### 5.3 `bridge`（JS Interface）
- `AxonNativeBridge`
  - `@JavascriptInterface fun vibrate(ms: Int)`
- Web側は `window.AxonNative.vibrate(20)` のように呼び出す（命名は固定）

### 5.4 `app`（画面・状態管理）
- 推奨: Single Activity + 複数Fragment（またはCompose）
- 状態: `DiscoveryState` / `ConnectionState` / `WebViewState`
- ViewModelは `EndpointResolver` と `ReachabilityChecker` を利用

---

## 6. 通信・ディスカバリ詳細

### 6.1 mDNS
- Service Type: `_awme-macro._tcp`
- Name: サーバ側で設定（例: PC名/任意名）
- ポート: `4000`（Phoenix）

### 6.2 ADB（USB）
- 接続先は `127.0.0.1:4000`
- Androidアプリ側は「ADBが設定済みか」を厳密には判定しづらいので、
  - まず `127.0.0.1:4000` を試し、失敗したら次手段へフォールバック

### 6.3 到達性チェック（Connectingで実施）
- 例: `GET http://<host>:<port>/` を短いタイムアウトで1回だけ試す
- 成功条件は「HTTPレスポンスが返る」程度でよい（200/302/403等の詳細はサーバ側で管理）

---

## 7. エラー処理ポリシー

### 7.1 WebViewロード・接続
- `onReceivedError`（DNS/接続断/タイムアウト）
  - Error画面へ遷移し「再接続/再探索」を提示
- `onReceivedSslError`
  - MVPでは原則拒否（`handler.cancel()`）
  - 例外で許可する運用を入れる場合は、設計上明示し、ユーザー操作を必須にする

### 7.2 画面遷移の原則
- 一度でも WebView の致命的エラーを検知したら、WebViewは破棄して作り直す（状態が壊れやすいため）
- 「再接続」は同一 endpoint を再試行、「再探索」は resolver を最初から実行

---

## 8. セキュリティ（Android側）

サーバ側は RemoteAddress 制限を実装する（`docs/architecture.md` 参照）。Android側は以下で事故を減らす。

- WebViewのロード先は「解決済み endpoint のみ」に制限し、任意URLへの遷移を抑止する
- WebView設定（推奨）
  - `setAllowFileAccess(false)`
  - `setAllowContentAccess(false)`
  - `setJavaScriptEnabled(true)`（LiveViewのため必要）
  - Mixed contentは原則禁止（将来HTTPS化する場合の足枷になる）
- `JavascriptInterface` は最小関数のみ公開し、入力は境界チェックする（例: `ms` の範囲）

---

## 9. 権限・要件

- mDNS（NsdManager）利用に必要なネットワーク権限を付与
  - `INTERNET`
  - `ACCESS_NETWORK_STATE`
  - Androidバージョンにより mDNS/ローカルネットワーク周りの要件が変動するため、実装時にターゲットSDKに合わせて精査する
- バイブ
  - `VIBRATE`（APIレベルにより不要/制限の可能性あり）
- スクリーン常時点灯
  - `FLAG_KEEP_SCREEN_ON`

---

## 10. テスト方針（Android側）

- Unit
  - `EndpointResolver` の優先順位（USB失敗→mDNSへ）
  - URL許可判定（許可host以外を拒否）
- Instrumentation（最小）
  - WebViewが指定URLを開ける
  - `AxonNativeBridge.vibrate` が呼べる（モックで検証）

---

## 11. 実装タスク（MVP提案）

1. Discovery（mDNS）: `_awme-macro._tcp` の探索/解決
2. Connecting: reachability check とタイムアウト設計
3. WebView host: エラー検知→Error画面遷移
4. JS bridge: `vibrate(ms)` のみ
5. URL制限・WebView設定のハードニング

---

## 付録A: Web↔Native ブリッジ仕様（MVP）

### A.1 JSから呼ぶAPI
- オブジェクト: `window.AxonNative`
- 関数:
  - `vibrate(ms: number)`

### A.2 バリデーション
- `ms` は `0..1000` を許容（上限はMVPの安全弁。必要ならサーバUI側で調整）

---

## 付録B: 将来拡張の余地（設計メモ）

- 端末情報の通知（例: OS/アプリバージョン）
- 接続品質のネイティブ表示（LiveViewの指標を補助）
- 証明書ピンニング/HTTPS
