# 設定管理リファクタリングの状況報告と課題分析

## 1. 目的（ゴール）
**「設定管理の中央集権化（Single Source of Truthの確立）」**
各画面（LiveView）や実行エンジン（TapMacro）が個別に `profiles.yaml` をディスクから読み込む現状を改善し、
「設定取得を1箇所へ集約」した上で、Productionではメモリキャッシュ（ConfigStore）を持てる構造にする。

（補足：現行コードでは `Axon.App.LoadConfig.load/0` が各所から直接呼ばれ、
`Axon.Adapters.Config.ProfilesPath.resolve/1` が初回コピー（プロビジョニング）まで内包しています。）

目指す効果は以下です。
- マクロ実行時のディスクI/O排除によるレスポンス向上。
- PC/スマホ全画面での設定変更のリアルタイム同期。
- アプリ起動時の確実な初期設定ファイル生成（プロビジョニング）。

## 1.1 現状（2025-12-31時点の実装コンテキスト）
- 設定ロード: `Axon.App.LoadConfig.load/0`（YAML読込・検証）
- パス解決＋初回コピー: `Axon.Adapters.Config.ProfilesPath.resolve/1`（`provision: true` がデフォルト）
- 参照箇所:
    - LiveView（Dashboard/Macro/Setup）で都度 `LoadConfig.load/0`
    - TapMacroでも `config_loader.load/0`（DIで差し替え可能だが、責務境界が曖昧）
- 更新同期:
    - SetupLive/DashboardLive はタイマーで定期的に再ロードしており、I/O増加とレースの温床になっている

## 2. 実施したアクション
1.  **`ConfigStore` (GenServer) の実装**: ファイルの監視、メモリ保持、PubSubによる変更通知。
2.  **`TapMacro` のリファクタリング**: `ConfigStore` のキャッシュを参照するように変更。
3.  **UI（MacroLive, DashboardLive, SetupLive）の変更**: 購読モデル（PubSub）への移行。
4.  **DI（依存性注入）の試行**: テスト環境用の `_test_store` パラメータ等の導入。

※この試行は、テスト安定性と境界の明確さを満たせず現時点では実装停止。

## 3. 失敗の原因分析

### A. テスト環境におけるプロセスの競合
`ConfigStore` を名前付きプロセスとしたため、`ExUnit` での並列実行時に `:already_started` エラーが発生しました。これを避けるために動的な名前を導入した結果、PubSubのトピック管理が複雑化し、テストの安定性が著しく低下しました。

根本原因: テストが「プロセスの存在」と「その名前」に依存していたこと。
本来は UseCase/LiveView が「設定はどこから来るか（プロセス/監視/キャッシュ）」を知らないべきでした。

### B. LiveViewのライフサイクルとDIの不整合
テストコードから LiveView へ「どのプロセスを参照するか」を伝える DI の仕組み（クエリパラメータ等）が、Elixirのモジュール名（アトム ↔ 文字列）の変換不備により、実行時エラーや意図しないリダイレクトを多発させました。

根本原因: DI対象が「モジュール（Behavior実装）」ではなく「プロセス名/文字列（ルーティング起点）」だったこと。
LiveViewはマウント/リダイレクト/接続確立の順序が絡むため、文字列→アトム変換やURL経由DIは不安定になりやすいです。

### C. 非同期チェーンによるレースコンディション
「ファイル更新 -> 検知 -> 通知 -> UI更新」の連鎖が非同期であるため、同期的なテストコードで状態をアサートするのが困難になり、タイムアウトが多発しました。

根本原因: テストが「いつ通知されるか」に依存しており、観測点（同期ポイント）が設計されていなかったこと。

### D. アーキテクチャ境界の曖昧化
「設定データの取得」というドメイン要求が、`ConfigStore` という「特定のプロセスの実装詳細（Adapter層）」に強く依存してしまい、テスト時にモジュールを分離できなくなりました。

根本原因: 「取得」と「キャッシュ/監視/通知」を同一APIで露出させ、依存方向が逆転したこと。

## 4. 再設計の方針（クリーンな復旧案）

現在の複雑化した同期ロジックを整理し、Behaviorベースの抽象化に移行します。

1.  **Behavior（インターフェース）の定義**:
    - `Axon.App.ConfigProvider` Behavior を定義。
    - `get_config()` と `subscribe()` をインターフェースとして固定。
2.  **実装の分離**:
    - **Production**: `ConfigStore` (GenServer) が Behavior を実装。
    - **Test**: `StaticConfigProvider` (モジュールスタブ) が Behavior を実装。テスト時にプロセスを起動する必要をなくす。
3.  **プロビジョニングの独立**:
    - ファイル生成（初回コピー）をロード処理から完全に分離し、`Application.start` 直後に一度だけ実行する独立した UseCase とします。
4.  **同期モデルの単純化**:
    - UI側は「通知が来たら再取得する」という単純な購読モデルを維持しつつ、DIの対象を「プロセス名」ではなく「Behaviorの実装モジュール」に統一します。

## 5. 明確な修正方針（実装可能な手順）
本リポジトリの現状（`LoadConfig` / `ProfilesPath` / 各LiveViewの直接ロード）から、最小の分割で復旧する。

### 方針1: 依存点を「ConfigProvider」へ一本化する
- TapMacro/LiveView/SetupPlug は `LoadConfig` を直接呼ばない
- 参照は `Application.get_env(:axon, :config_provider, Axon.App.ConfigStore)` のように「モジュール」で切り替える
- URL/クエリ/文字列でのDI（プロセス名注入）は採用しない

### 方針2: プロビジョニングを `ProfilesPath.resolve/1` から剥がす
- `ProfilesPath.resolve/1` は「パス解決のみ」（副作用なし）に寄せる
- 初回コピーは `ProvisionProfiles.ensure_present/1`（UseCase）を `Application.start` 後に1回だけ

### 方針3: 変更通知は固定Topic＋再取得モデル
- Topicは固定（例: `"config"`）
- 通知ペイロードは最小（例: `{:config_updated, ref}`）
- LiveViewは通知を受けたら `get_config/0` で再取得（ローカルstateを直接差分更新しない）

### 方針4: テストは「プロセスを立てない」ことを第一にする
- asyncテストでは `StaticConfigProvider` を使い、`get_config/0` が即時決定的に返る
- 変更通知が必要なテストは、Providerが `send(test_pid, ...)` できる形にする（PubSub依存を減らす）

### 受け入れ基準（Doneの定義）
- TapMacroのpreflightがディスクI/Oを行わない（Productionでキャッシュ経由）
- LiveViewが定期タイマーで `LoadConfig.load/0` を叩かない（通知ベース）
- ExUnit asyncで `:already_started` が発生しない（StaticProvider）
- SetupPlug/SetupLiveの「未設定→/setup誘導」が変わらず動く

---
作成日: 2025-12-31
ステータス: 計画中（実装停止）
