# Phase 0: セットアップチェックリスト

## ビルド・配布方針（決定済み）

ユーザーのMacはmacOSが古く、ローカルでXcodeが動かない。そのため以下の構成で進める。

- **ビルド**: GitHub Actions（`macos-latest`ランナー）でXcodeビルドを実行する。ローカルでの`xcodebuild`・シミュレータ実行は行わない
- **リポジトリ**: GitHub `gakuazu/hottoke`（非公開リポジトリ）
- **配布**: GitHub Actionsでコード署名なしのIPAを生成 → ユーザーが自分のPC/MacでSideloadly（無料Apple IDで署名するサイドロードツール）を使い、本人・家族のiPhoneにインストールする
- **Apple Developer Program**（年間$99）: 当面登録しない。一般公開・TestFlight配布・課金の実サンドボックス検証が必要になった段階で改めて検討する

## ユーザー側で対応が必要な項目

- [x] **GitHub**: `gakuazu`として`gh` CLI認証済み。リポジトリ`hottoke`（非公開）を作成しpushする
- [ ] **Sideloadlyのインストール**: https://sideloadly.io/ から無料でダウンロード（Windows/Mac対応）。実機（本人・家族のiPhone）を繋ぐPC/Macに入れる
- [ ] **Apple ID**: Sideloadlyでの署名に使う。既存のもので可
- [ ] **実機インストールの運用**: 7日ごとに署名が失効するため、7日以内にSideloadlyで再インストールする。初回は各端末で「設定 → 一般 → VPNとデバイス管理」から開発者を信頼する操作が必要
- [ ] （将来、課金機能や外部配布が必要になった時点で）Apple Developer Program登録・App Store Connectでのアプリ登録は、その段階でユーザーが行う（審査提出はユーザーの明示的許可が必須）

## このリポジトリ側で完了した項目（Phase 0）

- [x] `CLAUDE.md` — 組織の役割定義・運用ルール・ビルド/配布方針
- [x] `.claude/agents/product-researcher.md`
- [x] `.claude/agents/ux-designer.md`
- [x] `.claude/agents/ios-engineer.md`
- [x] `.claude/agents/qa-tester.md`
- [x] `.claude/agents/aso-marketer.md`
- [x] `.claude/agents/ops-support.md`
- [x] `docs/` ディレクトリ
- [ ] git init・GitHubリポジトリ作成・初回push
- [ ] `.github/workflows/`のビルドワークフロー（Phase 3でXcodeプロジェクト作成時にios-engineerが追加）

## 次のアクション

Apple Developer Programの方針、ビルド・配布方針とも決定済みなので、Phase 1（アイデア創出・検証）としてproduct-researcherエージェントを起動できる。アイデアのスコアリング軸には「GitHub Actionsビルド + Sideloadly配布だけで価値検証できるか」も含める。
