# HOTTOKE — 収益化iPhoneアプリ開発組織

## プロジェクトの目的

このリポジトリは、単発のアプリ実装ではなく「アイデア出し→検証→設計→実装→審査提出→運用改善」を継続的に回す、役割分担されたAIエージェント体制の拠点である。ユーザー（gakuazu@gmail.com）はコードを書かない非エンジニアであり、各フェーズの意思決定者（CEO役）として承認・選択を行う。実作業は `.claude/agents/` に定義された各ロールのサブエージェントに委譲する。

## 組織構成

| ロール | ファイル | 責任範囲 |
|---|---|---|
| product-researcher | `.claude/agents/product-researcher.md` | 市場調査・競合分析・アイデア創出とスコアリング |
| ux-designer | `.claude/agents/ux-designer.md` | 画面構成・ワイヤーフレーム |
| ios-engineer | `.claude/agents/ios-engineer.md` | SwiftUI実装、Xcodeプロジェクトの構築・保守 |
| qa-tester | `.claude/agents/qa-tester.md` | テスト計画、動作検証、リリース前チェック |
| aso-marketer | `.claude/agents/aso-marketer.md` | App Store掲載文・ASO・ローンチ後の改善提案 |
| ops-support | `.claude/agents/ops-support.md` | 運用フェーズでの定期監視・改善提案（`/loop`または`schedule`で定期実行） |

## エージェント間の対話（レビューループ）

品質を上げるため、エージェント同士の相互レビューを工程に組み込む。ユーザーが逐一介在するのはフェーズの節目（承認ゲート）のみとし、フェーズ内部の相互チェックはエージェント間の連携に任せる。

**判明した制約（2026-08-26時点）**: 当初は`SendMessage`/`ListAgents`でサブエージェント同士が直接対話する設計だったが、実際に動かしたところ、Agentツールで起動した非fork型サブエージェント（product-researcher, aso-marketer等）からは`ListAgents`ツール自体が存在せず、`SendMessage`も相手に届かないことを確認した（"No agent named 'aso-marketer' is reachable"）。これらのツールはオーケストレーター（ユーザーとの対話セッション本体）だけが使え、個別に起動したサブエージェント同士では使えない。

そのため実際の運用は**ファイル経由の非同期ハンドオフ + オーケストレーターによる仲介**で行う:

1. エージェントAが成果物を `docs/` に書き出す
2. オーケストレーターがエージェントBを起動し、Aの成果物ファイルを読ませてレビュー・追加分析させ、Bも `docs/` に書き出す
3. 両者の内容が食い違う／統合が必要な場合は、オーケストレーターが両方を読んで矛盾点を洗い出し、必要なら**同じエージェントIDに`SendMessage`で追加指示を送り再開させる**（オーケストレーター視点では特定のサブエージェントを継続できるため、これは機能する）、または新しいエージェントに両方の成果物を渡して統合版を作らせる

- **ios-engineer ⇄ qa-tester**: 機能実装後、オーケストレーターがqa-testerを起動してios-engineerの変更差分をレビューさせ、指摘を`docs/`に書き出す。指摘があればオーケストレーターがios-engineerに伝えて修正させる。
- **ux-designer ⇄ ios-engineer**: ワイヤーフレーム確定前に、オーケストレーターがios-engineerに実装可否を確認させ、結果をux-designerに伝える。
- **product-researcher ⇄ aso-marketer**: 市場性とASO観点を別々に分析させた上で、オーケストレーターが両方の`docs/`ファイルを読んで統合・矛盾解消する。

最大2往復を目安に収束させ、それでも解決しない・判断が割れる問題は必ずユーザーに報告する。各エージェント定義（`.claude/agents/*.md`）内の「エージェント間対話」の記述は将来ツール制約が変わった場合の理想形として残しつつ、実運用は上記の仲介フローで行う。

## 運用ルール（承認ゲート）

1. 各フェーズの成果物は必ずユーザーの承認を得てから次フェーズに進む。エージェントが勝手にフェーズを跨いで進めない。
2. 予算を伴う判断（Apple Developer Program登録、有料API/サービスの利用など）は必ず事前にユーザーに確認する。デフォルトは無料枠・無料ツールのみで完結させる方針。
3. App Storeへの提出・公開など後戻りしにくい操作は、必ずユーザーの明示的な許可を得てから行う。
4. 成果物は `docs/` 配下に連番でMarkdownとして残し、意思決定の経緯を追跡できるようにする。

## フェーズロードマップ

- Phase 0: セットアップ（本ファイル・サブエージェント定義・チェックリストの整備）— 完了
- Phase 1: アイデア創出・検証（product-researcher）
- Phase 2: 仕様・デザイン（product-researcher + ux-designer）
- Phase 3: 実装（ios-engineer）
- Phase 4: QA（qa-tester）
- Phase 5: 申請・公開（ios-engineer + aso-marketer）
- Phase 6: 運用（ops-support、定期実行）

詳細は `/Users/morita/.claude/plans/iphone-ai-fluffy-rain.md` の承認済みプランを参照。

## 開発時の前提

- ユーザーはSwiftコードをレビューできないため、実装内容・変更点は平易な言葉で都度説明すること。
- **ビルド環境は決定済み**: ユーザーのMacはmacOSが古く、ローカルでXcodeが動かせない。そのため**ビルドはローカルではなくGitHub Actions（macOSランナー）上で行う**。このセッションのBashツールでも`xcodebuild`やシミュレータは使えない前提で作業する。
  - リポジトリ: GitHub `gakuazu/hottoke`（非公開）。`gh` CLIで`gakuazu`として認証済み
  - コード変更はcommit・pushし、GitHub Actionsのワークフロー実行結果（`gh run list` / `gh run view`）でビルド・テストの成否を確認する。これがローカル`xcodebuild`の代替になる
  - ワークフロー（`.github/workflows/`）はPhase 3でXcodeプロジェクトを作成する際にios-engineerが追加する
- **配布方針は決定済み（`docs/00-setup-checklist.md`参照）**: Apple Developer Programには登録せず、**GitHub Actionsが生成した署名なしIPAを、ユーザーが自分のPC/MacのSideloadly（無料Apple IDで署名するサイドロードツール）で本人・家族のiPhoneにインストールする**運用とする。
  - Xcodeのビルド設定はコード署名なし（`CODE_SIGNING_ALLOWED=NO`等）でIPAを生成し、署名はSideloadly側の無料Apple IDに任せる
  - 署名は7日で失効するため、7日以内にSideloadlyで再インストールが必要（TestFlightのような遠隔配布はできない）
  - 課金機能はXcodeの「StoreKit Configuration」ファイルによるローカルテストで代替し、実サンドボックスは使わない
  - 一般公開・収益化に進む際は改めてApple Developer Program登録（$99/年）をユーザーに確認する
