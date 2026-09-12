# Phase 1→2 移行決定: 2本目のアプリ「表情操作プレイグラウンド」

作成日: 2026-09-12
決定者: オーナー

## 決定事項

2本目に開発するアプリとして、`docs/06-bold-ideas-round2.md` 案1「顔だけで遊ぶミニゲーム集（表情操作プレイグラウンド）」を選定する。

- ARKit（`ARFaceTrackingConfiguration`、TrueDepthカメラ、Apple標準・無料・オンデバイス）が検出する表情ブレンドシェイプ（笑顔・驚き・ウインク・眉上げ等）をそのままゲームの操作入力にするミニゲーム集。
- TrueDepthカメラ搭載機（iPhone X以降、Face ID対応機）限定。

## 進め方

- 現在実装中の1本目「カレイド日記」（`docs/02-spec.md`〜`docs/04-build-log.md`、Phase 3実装中）とは**並行**で進める。1本目の実装を止めない。
- Phase 2（仕様・デザイン）をこれから開始する。product-researcherが仕様書（`docs/08-app2-spec.md`想定）を作成し、オーナー承認後にux-designerが画面構成・ワイヤーフレームを作成する。

## 経緯

- `docs/01-idea-shortlist.md`・`docs/05-next-idea-shortlist.md`の競合調査起点の提案は2度とも「イマイチ」と却下された。
- `docs/01c-bold-ideas.md`の逆順アプローチ（自由発想→選別→軽い競合確認）を踏襲した`docs/06-bold-ideas-round2.md`の6案から、オーナーが案1を選定した。
