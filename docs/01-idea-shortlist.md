# Phase 1: アイデアショートリスト（product-researcher）

作成日: 2026-08-26
担当: product-researcher
更新日: 2026-08-26（**オーナーフィードバックにより全面書き直し**）

## 今回の書き直しについて

前回（習慣トラッカー系5案＋ゲーム2案）に対し、オーナーから「提案そのものに魅力を感じない」「方向性を絞らず幅広く再提案してほしい」というフィードバックを受けた。これを受けて**白紙に戻し**、以下の方針で再構築した。

- 「トラッカー・管理系ユーティリティ」への偏りを排除し、**ゲーム／エンタメ／クリエイティブ・創作ツール／ソーシャル／教育／フィットネス／生産性／AIネイティブ体験**にまたがる10案を用意した（同系統の案を2つ以上並べない）。
- スコアや実用性だけでなく、**「体験としての魅力・意外性・楽しさ」**を各案に明記することを必須項目とした。
- 前提条件（非エンジニアオーナー、SwiftUI/SpriteKit実装、予算ほぼゼロ、GitHub Actionsビルド＋Sideloadly配布、Apple標準フレームワーク限定）は変更していない。前回調査で得た一部の裏付けデータ（Widgetsmithの収益実績など）は根拠として再利用しているが、**アイデア自体は前回の7案（保証書管理・AI資格フラッシュカード・ニッチウィジェット・No-Buyトラッカー・AI週次振り返り・デイリー謎解きパズル・フルーツマージパズル）とは重複しない新規10案**にしている。

## スコアリング軸（5段階、5が最良）

1. **実装難易度**（低いほど高スコア＝実装しやすい）
2. **収益性**（サブスク/広告/買い切りの見込み）
3. **競合過多度**（競合が少ないほど高スコア）
4. **ASO余地**（キーワード・カテゴリでの発見されやすさ）

「実機のみ検証可否」は各案に定性的に明記する（スコア合計には含めない）。Apple Developer Program未登録・Sideloadly配布（実機のみ・7日で署名失効）という制約下で、**コアの体験価値をユーザー自身が確かめられるか**を評価する。AI機能（Foundation Models）を使う案は、Apple Intelligence対応端末（iPhone 15 Pro以降目安）でないと検証できない点に注意。

---

## 案1【ゲーム／探索】リアル図鑑ハンティング

**スコア: 実装難易度3 / 収益性3 / 競合過多度2 / ASO余地3 ＝ 合計11**

- **概要**: カメラをかざすと、Visionフレームワークの端末内画像分類（`VNClassifyImageRequest`、無料・オフライン・サーバー不要）が身の回りの物を認識し、「図鑑」に登録していく収集ゲーム。植物・生き物・日用品などカテゴリ別に集め、コンプリート率や希少度を可視化する。
- **想定ユーザー**: 子ども連れの家族、外出先での暇つぶしを探す層、収集要素が好きな層。
- **なぜ面白いか**: 「その場にある現実そのものが素材になる」という体験は、既存の写真アプリや図鑑アプリにはない意外性がある。散歩や外出のたびに新しい発見がゲームになり、日常の景色を見る目が変わる面白さがある。子どもとの外出時に「これ何？」を一緒に確かめる体験としても魅力的。
- **想定収益モデル**: 基本無料＋買い切りで追加図鑑テーマ（昆虫・乗り物・和菓子など）を解放。家族向けなので広告よりも一括購入・ファミリー共有向きの買い切りが適する。
- **参考競合**: Camera Hunt - Scavenger Game（60秒で対象物を探すML活用の無料ゲーム、既に存在）、Scavengar（AR宝探し作成プラットフォーム）、Snapchatのスキャベンジャーハント機能（実在物体をリアルタイム認識）。
- **根拠**:
  - *実装難易度3*: `VNClassifyImageRequest`はApple標準・無料・端末内で完結するが、一般物体分類器のため「図鑑」として意味のある分類体系（カテゴリ・希少度設計）を独自に作り込む手間がある。
  - *収益性3*: 家族向け買い切りアプリは単価が低めになりがちで、実用系案ほどの継続課金は見込みにくいと判断。
  - *競合過多度2*: WebSearchで「Camera Hunt - Scavenger Game」が既にほぼ同一コンセプト（カメラ×ML×収集）で無料配信されていることを確認。核となるメカニクス自体は先行例があり、差別化（図鑑としての継続的な収集・コンプリート要素）が必須。
  - *ASO余地3*: 英語圏では「camera hunt」「scavenger game」の直接競合が存在するが、日本語の「図鑑」「観察」を軸にしたロングテールは手薄。
- **実機のみ検証**: 完全に可能。Vision処理はすべて端末内・オフラインで完結し、家族の実機だけでコア体験（認識精度・楽しさ）を確認できる。

---

## 案2【ソーシャル／パーティゲーム】せーの！ みんなでオフラインパーティゲーム

**スコア: 実装難易度2 / 収益性3 / 競合過多度4 / ASO余地3 ＝ 合計12**

- **概要**: 1台を「お題を出す画面（テレビ代わり）」、参加者は各自のiPhoneを「コントローラー」として使うJackbox形式のパーティゲーム。インターネット不要で`MultipeerConnectivity`（Bluetooth/ローカルWi-Fi、Apple標準・無料）による端末間接続のみで完結させる。お絵描き当て・多数決クイズ・一言ボケなど、その場にいる人数で盛り上がるミニゲームを複数収録。
- **想定ユーザー**: 家族の集まり・友人の宅飲み・子どもの誕生日会など、複数人が同じ場所に集まるシーン。
- **なぜ面白いか**: Jackboxのような「画面を囲んでワイワイ盛り上がる」体験は非常に強い娯楽的魅力があるが、Jackboxはインターネット接続が前提。それをオフライン・無料で再現できれば「Wi-Fiがない実家」「電波の悪い旅行先」でも遊べるという意外性のある価値になる。単純な一問一答ではなく「全員のスマホが同時に反応する」体験は、一人用アプリにはない社会的な楽しさがある。
- **想定収益モデル**: 基本無料＋買い切りでゲームパック追加（家族利用が中心の場面なのでサブスクより一括購入が心理的に受け入れられやすい）。
- **参考競合**: 「Offline Multiplayer Games」（Bluetooth利用、チェス・チェッカー等）、「2 Player Games Offline」「2 Player Games - Offline」（いずれも1台の画面を回して遊ぶ方式で、複数端末が同時に接続するJackbox型ではない）。
- **根拠**:
  - *実装難易度2（最も難しい部類）*: `MultipeerConnectivity`によるマルチデバイス間のリアルタイム状態同期、接続断・再接続処理、ホスト画面と複数クライアント画面の同時UI設計が必要で、10案中もっとも実装が複雑と判断した。
  - *収益性3*: パーティゲームは「集まった時だけ使う」性質上、日常利用アプリほどのLTVは見込みにくいが、買い切りゲームパックの単発購入は成立しやすい。
  - *競合過多度4*: WebSearchで確認した既存のオフライン系アプリはいずれも「1台の画面を回して遊ぶ」パス&プレイ方式で、Jackbox的な「各自のスマホがコントローラーになる」体験を無料・オフラインで提供する競合は見当たらなかった。
  - *ASO余地3*: 「party games with friends」は競合が多いが、「offline party game no wifi」「オフライン 宅飲みゲーム」は手薄。
- **実機のみ検証**: 概ね可能だが注意点あり。Bluetooth/ローカルWi-Fi接続はサーバー不要でSideloadlyの実機だけで検証できる。ただし**2台以上のiPhoneに同時にSideloadlyで署名・インストールする必要があり**、7日ごとの再署名の手間が複数台分に増える点は運用上の負荷として申し送る。

---

## 案3【エンタメ／家族】よるのおはなしメーカー（AIおやすみ絵本ジェネレーター）

**スコア: 実装難易度3 / 収益性4 / 競合過多度2 / ASO余地3 ＝ 合計12**

- **概要**: 子どもの名前・好きなもの・その日あった出来事を入力すると、Foundation Models（iOS 18.1以降、Apple Intelligence対応端末で無料・端末内動作・サーバー不要）が短いオリジナルの寝る前の物語を生成し、`AVSpeechSynthesizer`（Apple標準・無料の音声合成）で読み聞かせる。
- **想定ユーザー**: 未就学〜小学校低学年の子どもを持つ親。
- **なぜ面白いか**: 「今日あったこと」がそのまま物語の主人公の冒険になるという、既製の絵本にはないパーソナライズ体験が子どもにとって特別感がある。親にとっても「今日は疲れて絵本を読む余力がない」日の代替として実用と楽しさを両立する。オンデバイスAIならではの「クラウドに子どものデータを送らない」安心感も差別化になる。
- **想定収益モデル**: 基本無料（1日1話まで）＋サブスクで無制限生成・声の種類追加・物語の保存/シリーズ化。
- **参考競合**: StoryBean、Whispero（オンデバイスAI・iOS 18.1+対応と明記）、AI Bedtime Storyteller、StoryKit、The Bedtime Story Generatorなど、同カテゴリに既に多数のアプリが存在することをWebSearchで確認。
- **根拠**:
  - *実装難易度3*: Foundation Models（無料・オンデバイス）とAVSpeechSynthesizer（無料）の組み合わせは技術的には手堅いが、キャラクター設定・年齢に応じた語彙調整・保存ライブラリUIなど作り込み要素は中程度ある。
  - *収益性4*: WebSearchで確認できただけでも8種類以上の類似アプリが存在し、すべてサブスク/IAPモデルで運営されている＝需要が実証済みのカテゴリと判断。
  - *競合過多度2*: 同一コンセプトのアプリが非常に多く、Whisperoなど「オンデバイスAI」を謳う直接競合も既に存在することを確認したため、差別化なしでは埋没するリスクが高い。
  - *ASO余地3*: 英語圏の「bedtime story generator」は飽和状態だが、日本語「AI 読み聞かせ 絵本」市場は英語圏ほど埋まっていない可能性がある（国内競合の存在は本調査で確認できず）。
- **実機のみ検証**: 部分的に可能。読み聞かせ・保存などコア体験はSideloadlyで検証できるが、AI生成部分はApple Intelligence対応端末（iPhone 15 Pro以降目安）が必要。非対応機ではテンプレート物語へのフォールバック設計が必須。

---

## 案4【エンタメ／SNS共有】わたし図鑑（カメラロール深層分析パーソナリティカード）

**スコア: 実装難易度3 / 収益性3 / 競合過多度4 / ASO余地4 ＝ 合計14**

- **概要**: 写真ライブラリ（本人の許可のもと）をVisionフレームワークで分析し、色使い・被写体傾向・撮影時間帯などから「あなたの写真の傾向」をパーソナリティ診断風にまとめ、SNSでシェアしやすいカード画像として書き出す。処理はすべて端末内で完結し、写真そのものを外部に送らない。
- **想定ユーザー**: SNSでの自己表現・診断コンテンツのシェアを好む10〜20代を中心とした層。
- **なぜ面白いか**: 「自分では気づいていない自分の癖」をカメラロールという最もパーソナルなデータから可視化するのは、通常の性格診断にはない説得力と意外性がある。TikTokで「My camera roll explains me」が話題化している通り、結果をシェアしたくなる欲求（Spotify Wrapped的な体験）が強く、口コミでの拡散が狙える。オンデバイス処理により「写真を勝手にAIに送られる」不安（Tinderの類似機能が"creepy"と批判された事例あり）を払拭できるのも差別化点。
- **想定収益モデル**: 基本無料（月1回の簡易診断）＋サブスクで詳細診断・過去の記録比較・高解像度シェアカード書き出しを解放。
- **参考競合**: Aurascan（Timehop創業者による、過去の写真から未来を占う診断アプリ）、Tinderの「写真からvibeを分析」機能（テスト中、批判もあり）、Photo Persona（ChatGPT上の診断ツール、独立アプリではない）。
- **根拠**:
  - *実装難易度3*: Vision標準APIでの画像分類・顕著性検出・色解析は無料で完結するが、結果を「面白い診断文」として自然に構成する部分（Foundation Models併用も検討）にチューニングの手間がある。
  - *収益性3*: 診断系コンテンツはバイラルでの獲得力は強いが、1人あたりの継続課金額は小さくなりやすいため中間評価とした。
  - *競合過多度4*: WebSearchで確認できた直接競合はAurascan程度で、Tinderの機能はアプリ内埋め込みでスタンドアロンアプリではない。診断系コンテンツとしては比較的空いているニッチと判断。
  - *ASO余地4*: 「photo personality test」「camera roll analysis」は現時点で確立された強豪アプリがおらず、TikTokでのトレンド発生（"My camera roll is a personality test"のMedium記事も確認）はASO面でも追い風。
- **実機のみ検証**: 概ね可能。Vision分析・カード生成はすべて端末内で完結しSideloadlyで検証できる。ただし「バズってシェアが広がるか」という本質的な収益ドライバー（拡散力）は少人数の実機テストでは検証できない点は明記する。

---

## 案5【クリエイティブ／パーソナライズ】万華鏡ジェネレーティブ壁紙メーカー

**スコア: 実装難易度3 / 収益性4 / 競合過多度4 / ASO余地4 ＝ 合計15（最高評価）**

- **概要**: CoreImage/Metalのシェーダーでリアルタイムに万華鏡・幾何学模様・パーティクルパターンを生成し、対称性・カラーパレット・動きの速さなどをスライダーで調整しながら「自分だけの模様」をデザインできるツール。完成したパターンをLive Photo/動画としてロック画面・ホーム画面の壁紙に書き出す。すべて端末内処理でサーバー不要。
- **想定ユーザー**: ホーム画面カスタマイズに関心がある層、既製テーマではなく「自分で作る」ことに満足感を覚えるクリエイティブ志向の層。
- **なぜ面白いか**: 既存の「壁紙メーカー」アプリの大半は「動画→Live Photo変換」であり、模様そのものをゼロから生成するツールではない。パラメータをいじるたびに模様が変化していく体験自体が、いわば「ジェネラティブアートの遊び場」になっており、完成品を待つのではなく作る過程そのものが楽しい。Widgetsmithのようなテーマ選択型とは異なり、「世界に一つだけの模様」を作れる満足感が差別化の核。
- **想定収益モデル**: 基本無料（プリセットパターン・広告表示なし解放は買い切り）＋サブスクで高度なパラメータ・追加カラーパレット・4K書き出しを解放。パーソナライズ・ウィジェット系はWidgetsmithの実績（RevenueCatケーススタディで月$200k規模、最盛期月$3M）がカテゴリ全体の収益ポテンシャルを裏付けている。
- **参考競合**: Live Wallpaper Maker/Converter、Video to Live Wallpapers Maker、Video Wallpaper・Lock Screenなど多数存在するが、いずれも「手持ちの動画/写真をLive Photo化する」変換ツールであり、模様をゼロから生成する「ジェネレーティブ壁紙デザインツール」は本調査では確認できなかった。
- **根拠**:
  - *実装難易度3*: CIFilter/Metalでのリアルタイム模様生成とパラメータUIは標準的なSwiftUI+CoreImageの範囲内だが、「触っていて気持ちいい」チューニングには反復調整が必要。
  - *収益性4*: WidgetsmithのRevenueCatケーススタディ（月$200k規模、最盛期月$3M）とAppstoreSpyのデータにより、パーソナライズ・ウィジェット系カテゴリの収益ポテンシャルの高さが裏付けられている。
  - *競合過多度4*: WebSearchで確認した「live wallpaper maker」系アプリはすべて動画変換ツールであり、模様を生成するジェネレーティブ設計ツールという切り口では直接競合が見当たらなかった。
  - *ASO余地4*: 「live wallpaper maker」自体は検索ボリュームが大きく一定の競合があるが、「kaleidoscope wallpaper」「generative wallpaper」は空白に近い。
- **実機のみ検証**: 完全に可能。生成・プレビュー・書き出しまですべて端末内で完結し、Sideloadlyの実機だけで価値を100%確認できる。
- **オーナー追加アイデア（2026-08-26）**: スライダー操作に加えて、**CoreMotion（加速度計・ジャイロ）で「振ると模様が変わる」「傾けると回転する」という物理的な万華鏡そのものの操作感**を実装する。案10（スイングビート）と同じ標準APIのため技術的な裏付けは既にある。「振って偶然の模様に出会う」体験と「スライダーで作り込む」体験を両立させることで、当初の懸念（触っていて気持ちいいか未知数）を「本物の万華鏡の身体的な操作感」という強い裏付けで補強できる。Phase 2の仕様策定時にこの操作方式を軸に据えることを推奨する。
- **重要な技術的制約（2026-08-26、オーナー確認）**: モーション連動は**アプリを開いている間のみ**有効。iOSはサードパーティアプリがホーム画面/ロック画面の壁紙そのものをリアルタイムに書き換え続けるAPIを公開しておらず、「壁紙として設定した状態で振ると変わる」ことは実現できない。したがって体験の主軸は「アプリ内で振って模様を探す・作るジェネレーティブアートツール」であり、壁紙設定はお気に入りの瞬間をLive Photo/静止画として書き出す副次的機能という位置づけになる。妥協案としてロック画面ウィジェット（WidgetKit）による時間経過での模様切り替え（iOS17標準万華鏡壁紙と同様の仕組み）は可能。この前提をコンセプト説明・ストア掲載文で誤解のないよう明記する必要がある。
- **音楽連動は見送り、代わりに「1日の活動データ→日替わり模様動画」モードを採用（2026-08-26、オーナー提案）**: マイクでの音楽反応モードは既存の音楽ビジュアライザー系アプリ（Vibe Flow等）と直接競合するため見送り。代わりに、iPhoneのモーションコプロセッサーが常時バックグラウンドで記録している1日分の活動データ（`CMPedometer`: 歩数・距離・登った階数、`CMMotionActivityManager`: 静止/歩行/走行/車移動の時間配分。いずれもApple標準・無料、直近7日分を後から一括取得可能でアプリ常駐は不要）をパラメータに変換し、その日1日を象徴する短い（数十秒程度の）模様変化動画を`AVAssetWriter`＋CoreImage/Metalでオフライン生成する。Wordleのような「今日の1問」的な日替わりの儀式性を持たせる。
  - 競合確認: 「個人の身体・活動データからジェネレーティブアートを作る」という発想自体は前例あり（heart/work: Apple Watchの心拍・ワークアウトデータから生成アートを作るiOSアプリ）だが、「iPhoneの1日の活動データから万華鏡模様の日替わり動画を作る」という組み合わせでの直接競合は確認できなかった。Art+Steps（歩数で既製アートを解放するアプリ）はデータから模様を生成する方式ではなく別物。
  - 利点: (1) 音楽ビジュアライザー系との競合を回避、(2) 壁紙のリアルタイム反応ができないという既知の制約と相性が良い（そもそも「毎日1本、新しい動画を生成する」モデルなので常時反応を諦めることが弱点にならない）、(3) Apple Intelligence非対応機種でも動作する（AIモデル不使用）、(4) 「今日どう動いたか」が模様として残るパーソナルな日記性・愛着形成の要素が加わる。
  - Phase 2仕様策定時は、この「日替わり活動データ模様動画」モードを主軸とし、手動の振る・傾ける操作（アプリ内での作り込み用）を副モードとして併存させる構成を軸に検討する。
  - **データ→模様マッピング設計案（2026-08-26、オーナーとの検討）**: 「直感的に納得できる」対応関係にするため、以下の2軸を重ねる設計とする。
    1. **動画の時間軸＝1日の時系列を圧縮したもの**とし、`CMMotionActivityManager`が返すタイムスタンプ付き活動区間（静止/歩行/走行/自転車/車移動）を、動画の前半=朝・中盤=昼・終盤=夜という構成でそのまま反映する。
    2. **「何をしていたか」→模様の動き方・質感**: 静止=ゆったり回転する瞑想的な模様、歩行=歩行ケイデンスに合わせた一定リズムの拍動、走行=速く激しい変形、車移動=要素が流れるようなスライド、自転車=回転運動の強調、階段（floorsAscended）=中心から外側・上方向へ広がる動き。
    3. **「いつだったか」→色のパレット**: 朝＝淡いパステル/オレンジ〜ピンク、昼＝彩度高い青〜黄、夕方＝オレンジ〜赤紫、夜＝藍〜紫の発光調。
    4. **活動量が少ない日のトーン**: 「動きが少ない＝物足りない日」ではなく「静けさの美しい模様」として肯定的に演出する（案4 No-Buyトラッカーで懸念した罪悪感を煽るトーンを避け、活動的な日もそうでない日もそれぞれ魅力のある1枚にする）。
    5. **設計の核**: 単純な「合計歩数」等の1パラメータ化ではなく、**1日の活動強度の時系列カーブそのものを模様のテンポ変化としてアニメーションに反映**することで、動画を見返すだけでその日の生活のリズムが感覚的に蘇る仕掛けを狙う。
- **競合再確認（2026-08-26、オーナー指摘を受けてWebSearchで追加調査）**: 「振る・傾けると模様が変わる万華鏡アプリ」というコンセプト自体は既に複数存在することを確認した（KaleidoBalls-Free: シェイクで新パターン生成／Kaleidoscope Real: 傾き・回転で操作、評価1.0/5・DL数3,000+程度／Real Kaleidoscope Lite: 重力・物理法則で"石"が動くリアルな物理演算／Kaleidomatic: カメラ×ピンチ・回転操作／iOS 17標準壁紙: 時間経過で自動変化する万華鏡風壁紙が全端末に標準搭載）。したがって完全にオリジナルな切り口ではない。ただし確認できた競合は軒並み小規模・低評価（Kaleidoscope Realは5点満点中1.0）であり、「発想はあるが完成度高く作られていない」空白地帯と言える。**競合過多度スコアは当初の4から3程度に下方修正するのが妥当**。差別化は「仕上がりの質」（物理演算の気持ちよさ、カラーパレットの美しさ、Live Photo書き出し品質）に懸かる。

---

## 案6【エンタメ／ゲーム・AIネイティブ】選択の迷宮（オンデバイスAI即興アドベンチャー）

**スコア: 実装難易度3 / 収益性3 / 競合過多度2 / ASO余地2 ＝ 合計10**

- **概要**: Foundation Models（オンデバイス・無料）がプレイヤーの選択に応じてリアルタイムに物語を生成し続けるテキストアドベンチャー。挿絵はAI画像生成ではなくSF Symbols＋グラデーション背景の演出で軽量に代替し、サーバー不要で完結させる。
- **想定ユーザー**: 読書・小説好き、ゲームブック世代、AIとの対話的コンテンツに関心がある層。
- **なぜ面白いか**: 「毎回結末が変わる」「二度と同じ話にならない」という無限のリプレイ性は、決められたシナリオを消費するだけの既存ゲームブックにはない魅力。オンデバイスAIのため通信不要・待ち時間が少なく、プライバシー（会話内容が外部に送信されない）を明確に訴求できるのも今の時代性に合った差別化点。
- **想定収益モデル**: 基本無料（1日の生成回数制限）＋サブスクで無制限プレイ・お気に入りシナリオの保存・キャラクター作成機能を解放。
- **参考競合**: Wabi（AIによる無限分岐アドベンチャー）、Roletopia（60本の書き下ろしストーリー＋141人のAI共演キャラ）、StoryZone（AIゲームマスター＋自動生成イラスト）。appshunter.ioの調査では「choose your own adventure」系アプリが211以上存在すると報告されている。
- **根拠**:
  - *実装難易度3*: Foundation Modelsでの物語生成自体は無料・オンデバイスで完結するが、選択の一貫性維持（矛盾のない世界観・状態管理）のプロンプト設計が難易度を押し上げる。
  - *収益性3*: Wabi・Roletopiaなど確認できた競合はいずれもクレジット制/サブスクで運営されており、カテゴリとしての収益モデルは確立しているが、後発として大きな取り分を得るのは難しいと判断。
  - *競合過多度2*: WebSearchで確認した競合（Wabi、Roletopia、StoryZone）はいずれもクラウドAI・豊富なコンテンツ量を武器にしており、これらに対して差別化できる要素（オンデバイス・日本語特化）はあるものの正面から戦うのは厳しいと判断した。
  - *ASO余地2*: appshunter.ioの記事で「choose your own adventure」系アプリが211以上存在すると確認しており、キーワード面では非常に競合が多い。
  - **審査面の補足**: 2025年11月のApp Store審査ガイドライン改定でチャットボット/サードパーティAIへの個人データ共有に開示義務が課された（TechCrunch報道で確認）が、本案はFoundation Modelsによる完全オンデバイス処理のため、この開示義務の対象外になる可能性が高く、将来の正式配信を見据えた際のリスクは低いと考えられる。
- **実機のみ検証**: 部分的に可能。物語生成の面白さの検証にはApple Intelligence対応端末が必須。対応機がない場合はコア体験そのものが確認できない点がリスク。

---

## 案7【ゲーム／育成】デスクトップの相棒（ウィジェット育成ペット）

**スコア: 実装難易度3 / 収益性4 / 競合過多度1 / ASO余地2 ＝ 合計10**

- **概要**: WidgetKit＋Live Activities＋Dynamic Islandを使い、ホーム画面・ロック画面・Dynamic Island上で育成するデジタルペット。アプリを開かなくても、ウィジェットをタップするだけで餌やり・お世話ができるTamagotchi的な体験。
- **想定ユーザー**: 90年代〜2000年代のたまごっち世代、ホーム画面をにぎやかにしたい層。
- **なぜ面白いか**: 「アプリを開いて遊ぶ」のではなく「生活のふとした瞬間（ロック画面を見た時）にペットの様子が目に入る」という、能動的な操作を最小限にした体験設計が、他のゲームにはない親しみやすさを生む。懐かしさ（ノスタルジー）と最新のiOS機能（Live Activities）を組み合わせる意外性がある。
- **想定収益モデル**: 基本無料＋コスメティックIAP（衣装・部屋のインテリア等）。類似アプリPixel Palsは月間推定70,000ダウンロード・月間推定$30,000収益（IAP $0.99〜$49.99）という実績が確認できた。
- **参考競合**: Pixel Pals Widget Pet Game、Boko: Tamagotchi Virtual Pet（Live Activities/Dynamic Island対応済み）、Remagotchi、Pixel Pets。いずれも既にLive Activities/Dynamic Islandに対応した強力な競合。
- **根拠**:
  - *実装難易度3*: WidgetKit＋Live Activitiesでのペット育成は既存アプリ多数が実現しているパターンであり技術的な前例が豊富だが、状態管理（空腹度・機嫌等）とウィジェット更新の同期は相応の作り込みが必要。
  - *収益性4*: Pixel Palsの推定月間$30,000収益（70,000ダウンロード規模）という具体的な数字を確認でき、カテゴリとしての収益実証があるため高評価とした。
  - *競合過多度1（最低）*: WebSearchで確認しただけでもPixel Pals、Boko、Remagotchi、Pixel Petsという4つの直接競合が既にLive Activities/Dynamic Island対応まで完了させた状態で存在しており、10案中もっとも競合が厳しい。
  - *ASO余地2*: 「tamagotchi widget」「virtual pet widget」は上記の既存アプリに事実上押さえられており、ブランド想起の強い先行者に対して新規参入が割り込む余地は小さい。
- **実機のみ検証**: 概ね可能。ウィジェット・Live Activitiesはすべて端末内で完結しSideloadlyで検証できるが、Dynamic Islandの完全体験にはiPhone 14 Pro以降が必要（Dynamic Island非搭載機ではLive Activitiesはロック画面のみの表示になる）。

---

## 案8【生産性／ソーシャル】その場で割り勘（サインアップ不要・即時レシート割り勘）

**スコア: 実装難易度4 / 収益性3 / 競合過多度1 / ASO余地2 ＝ 合計10**

- **概要**: レシートを撮影するとVisionKit（無料・端末内OCR）が品目・金額を自動抽出し、その場で参加者に均等/個別割り当てして合計を計算、結果をメッセージアプリの共有シートで送るだけの単発利用型アプリ。アカウント登録・友達管理なしで「その場限り」で完結させることで、Splitwiseのような「継続的な貸し借り管理」アプリとは異なる軽量な立ち位置を狙う。
- **想定ユーザー**: 飲み会・旅行など単発の集まりで一時的に割り勘したい層（継続的な家計簿的機能は求めない）。
- **なぜ面白いか**: 実用一辺倒に見えるが、「アカウント登録なしで今すぐ使える」「相手にアプリを入れさせなくていい（共有シートで結果を送るだけ）」という軽さそのものが、既存の割り勘アプリの面倒くささ（招待・アカウント作成・友達申請）に対するアンチテーゼとして新鮮に映る。会計の場の空気を壊さない「素早さ」がそのまま体験価値になる。
- **想定収益モデル**: 基本無料＋広告非表示・履歴保存のための小額買い切り（サブスクにはなじまない単発利用アプリと判断）。
- **参考競合**: Splitwise（3,400万ダウンロード・広告＋Proサブスクモデル、$20M資金調達実績あり）、Obe、Tab、SplitIt、OneSplitなど、レシートOCR×割り勘の組み合わせは既に多数存在。市場規模は2025年時点で$612M、年成長率7.34%（360iResearch調べ）。
- **根拠**:
  - *実装難易度4*: VisionKitの標準OCR機能と単純な配分計算のみで完結し、サーバー・アカウント管理が不要なため10案の中でも実装しやすい部類。
  - *収益性3*: 市場規模自体は$612M（2025年、360iResearch）と大きいが、単発利用アプリの性質上サブスクへの転換率は低く、買い切り中心のため中間評価とした。
  - *競合過多度1（最低）*: Splitwise（3,400万ダウンロード）を筆頭に、Obe・Tab・SplitIt・OneSplitとレシートOCR×割り勘という組み合わせの直接競合が非常に多いことを確認した。
  - *ASO余地2*: 「split bill」「receipt scanner split」はSplitwiseという強いブランドが上位を占めており、新規参入の余地は小さい。
- **実機のみ検証**: 完全に可能。OCR・計算・共有まですべて端末内で完結し、オーナー自身の実際の飲み会などですぐに価値検証ができる。

---

## 案9【教育／キッズ】なぞり道場（ゲーム化された漢字・書き取り練習）

**スコア: 実装難易度3 / 収益性3 / 競合過多度3 / ASO余地3 ＝ 合計12**

- **概要**: PencilKit（指でもApple Pencilでも入力可）で漢字をなぞり、書き順・形の正確さを幾何学的にスコアリングしてゲーム感覚で練習できるアプリ。学年別の漢字リスト、連続正解でのコンボ演出、キャラクターの成長要素などで「勉強させられている感」を薄めるゲーミフィケーションを重視する。
- **想定ユーザー**: 小学生の子どもを持つ日本の親、家庭学習アプリを探している層。
- **なぜ面白いか**: 既存の漢字学習アプリの多くは「日本語を学ぶ海外ユーザー向け」の実用的なUIで、国内の子ども向けに"ゲームとして遊びたくなる"体験設計がされたものは少ない。なぞる感触・正確さのフィードバック・キャラクター育成を組み合わせることで、「勉強」ではなく「遊びの延長で気づいたら漢字が書けるようになっていた」という体験を狙える。
- **想定収益モデル**: 基本無料（学年の一部を無料開放）＋サブスクで全学年・全漢字を解放。教育系は保護者の課金心理的抵抗が比較的低いカテゴリ。
- **参考競合**: Skritter: Write Japanese、Write It! Japanese、Kanji Teacher、Learn Kanji: 1st Grade Writingなど。多くは日本語学習中の海外ユーザー向けに設計されている。
- **根拠**:
  - *実装難易度3*: PencilKitでの入力取得自体は容易だが、書き順・形状の一致度を判定するロジック（幾何学的なパスマッチング）の精度作り込みに手間がかかる。
  - *収益性3*: 教育系アプリは課金への心理的抵抗が低いカテゴリだが、無料の学習サービス（学校配布教材等）との競合もあり中間評価とした。
  - *競合過多度3*: 確認できた競合（Skritter、Write It! Japanese、Kanji Teacher等）は実績があるが、いずれも英語圏の「日本語学習者」向け設計であり、日本国内の子ども向けゲーミフィケーションに特化したアプリは本調査では確認できず、隙間があると判断した。
  - *ASO余地3*: 英語圏の「kanji writing practice」はSkritter等に押さえられているが、日本語の「漢字 書き取り 子供 アプリ」ロングテールは競合状況を本調査で十分に確認できておらず中間評価とした。
- **実機のみ検証**: 完全に可能。PencilKitは指でも操作可能なためApple Pencilがなくても検証でき、判定ロジック・ゲーミフィケーション演出をSideloadlyだけで確認できる。

---

## 案10【フィットネス／ゲーム】スイングビート（モーション連動リズムゲーム）

**スコア: 実装難易度3 / 収益性3 / 競合過多度4 / ASO余地4 ＝ 合計14**

- **概要**: CoreMotion（加速度計・ジャイロ、Apple標準・無料）を使い、音楽のビートに合わせてiPhoneそのものを振る・回す・止めるといった身体動作でスコアを競うリズムゲーム。タップ操作中心の既存リズムゲームとは異なり、フィットネス的な軽い運動要素を組み込む。
- **想定ユーザー**: 体を動かしながら遊びたい層、リズムゲーム好き、軽い運動を楽しく取り入れたい層。
- **なぜ面白いか**: 画面をタップするだけのリズムゲームが飽和する中、「スマホ自体を振って操作する」という身体性を伴う操作は、プレイしている本人だけでなく傍から見ても楽しい・意外性のある体験になる（パーティーの余興的な魅力もある）。運動不足解消の実用性とゲームとしての爽快感を両立できる点が強み。
- **想定収益モデル**: 基本無料＋広告（インタースティシャル）＋楽曲パックの買い切り/サブスク。
- **参考競合**: Haptic Hustle（円を描く手の動きでボールを操作、加速度計活用）、FunFit（前面カメラでの姿勢トラッキング、モーション方式は異なる）、Active Arcade（カメラベースの全身運動ゲーム）。純粋な「加速度計でスマホを振る」リズムゲームの直接競合は確認できなかった。
- **根拠**:
  - *実装難易度3*: CoreMotionでのセンサー値取得自体は標準APIで容易だが、「振った動きが気持ちよく判定される」タイミング調整・誤検知防止のチューニングに反復作業が必要。
  - *収益性3*: リズムゲームジャンルは歴史的に楽曲IAP・広告で一定の収益実績があるカテゴリだが、モーション操作という未検証の切り口のため中間評価とした。
  - *競合過多度4*: WebSearchで確認した近縁アプリ（Haptic Hustle、FunFit、Active Arcade）はいずれも操作方式が異なり（円運動操作・カメラでの姿勢認識）、「加速度計でスマホ本体を振る」形式の直接競合は見当たらなかった。
  - *ASO余地4*: 「motion rhythm game」「swing game」は「tap rhythm game」ほど埋まっておらず、キーワード面での空白地帯と判断。
  - **安全面の補足**: スマホを振る操作は落下・破損リスクを伴うため、ストラップ着用の注意喚起UIが実質的に必須。App Store審査ガイドライン上の明確な禁止事項ではないが、UXとしての安全設計に配慮が必要。
- **実機のみ検証**: 完全に可能。CoreMotionはすべて端末内で完結し、Sideloadlyの実機で「操作していて楽しいか」というコア体験を直接確認できる。ただし広告収益そのものの検証は少人数の実機テストでは不可能（前回調査のゲーム系案と同様の構造的制約）。

---

## 総合評価

| # | ジャンル | 案名 | 概要（1行） | 実装難易度 | 収益性 | 競合過多度 | ASO余地 | 合計 |
|---|---|---|---|---|---|---|---|---|
| 1 | ゲーム／探索 | リアル図鑑ハンティング | カメラで実物を認識して集める収集ゲーム | 3 | 3 | 2 | 3 | 11 |
| 2 | ソーシャル／パーティ | せーの！オフラインパーティゲーム | 各自のiPhoneがコントローラーになるJackbox型 | 2 | 3 | 4 | 3 | 12 |
| 3 | エンタメ／家族 | よるのおはなしメーカー | AIが子ども向け寝る前物語を即興生成＋読み聞かせ | 3 | 4 | 2 | 3 | 12 |
| 4 | エンタメ／SNS共有 | わたし図鑑 | カメラロールをAI診断しシェア画像化 | 3 | 3 | 4 | 4 | **14** |
| 5 | クリエイティブ | 万華鏡ジェネレーティブ壁紙メーカー | 自分だけの模様を作ってロック画面壁紙に | 3 | 4 | 4 | 4 | **15（最高）** |
| 6 | エンタメ／AIゲーム | 選択の迷宮 | オンデバイスAIが物語を即興生成するアドベンチャー | 3 | 3 | 2 | 2 | 10 |
| 7 | ゲーム／育成 | デスクトップの相棒 | ウィジェット上で育てるたまごっち的ペット | 3 | 4 | 1 | 2 | 10 |
| 8 | 生産性／ソーシャル | その場で割り勘 | 登録不要・撮って即割り勘の軽量ツール | 4 | 3 | 1 | 2 | 10 |
| 9 | 教育／キッズ | なぞり道場 | ゲーム化された漢字書き取り練習 | 3 | 3 | 3 | 3 | 12 |
| 10 | フィットネス／ゲーム | スイングビート | スマホを振って遊ぶモーションリズムゲーム | 3 | 3 | 4 | 4 | **14** |

**総合順位（合計スコア順）**: 5(15) > 4=10(14) > 2=3=9(12) > 1(11) > 6=7=8(10)

## 特に「意外性」「面白さ」でオーナーに刺さりそうな案（ピックアップ）

前回の反省を踏まえ、スコアの高さだけでなく「体験としての驚き・楽しさ」を基準に3案を挙げる。

1. **案5: 万華鏡ジェネレーティブ壁紙メーカー（合計15・最高スコア）** — スコアも最高評価かつ、「既製テーマを選ぶ」のではなく「自分でゼロから模様を作る」という創作体験そのものが売りになる案。実装難易度・収益性・競合過多度・ASO余地のバランスが最も良く、実機のみで100%価値検証できる点も強み。
2. **案4: わたし図鑑（カメラロール深層分析、合計14）** — 「自分のカメラロールが性格診断になる」という意外性が強く、TikTok等で自然発生的にバズっている現象（"My camera roll is a personality test"）に乗れる点が魅力。オンデバイス処理によるプライバシー訴求も今の時流に合う。
3. **案2: せーの！オフラインパーティゲーム（合計12）** — スコア単体では中位だが、「Wi-Fiがなくても、各自のスマホがコントローラーになってJackboxのように盛り上がれる」という体験は他の案にない社会的・意外性のある楽しさがある。実装難易度は10案中最も高い（複数端末同時通信）ため難易度は高いが、当たれば強い差別化になる。
4. （次点）**案10: スイングビート（合計14）** — 「スマホを振って遊ぶ」という身体性のある操作は、タップ中心のリズムゲームが飽和する中で意外性があり、競合過多度・ASO余地ともに好スコア。安全面（ストラップ着用）の配慮は必要。

## 申し送り事項

- 前回同様、`ListAgents`/`SendMessage`によるaso-marketerとの直接対話は本環境では機能しない（CLAUDE.mdに記載の既知の制約）。本ドキュメントのASO余地スコアはproduct-researcher自身のWebSearch調査に基づく暫定評価であり、オーケストレーター側での別途ASOレビューでのクロスチェックを推奨する。
- 案3・案6（AI系）は、オーナー・家族の実機がApple Intelligence対応機種（iPhone 15 Pro以降目安、対応OS・言語設定）かどうかで検証可否が変わる。事前確認を推奨する。
- 案2（パーティゲーム）は複数端末への同時Sideloadlyインストールが必要になり、7日ごとの再署名の運用負荷が他案より高い点は選定時に考慮が必要。
- 案7・案8は市場自体は大きい（Pixel Pals月$30k規模、割り勘市場$612M）ものの、いずれも強力な先行者（Boko等・Splitwise）が既に同じ土俵を占めており、10案中もっとも「後発として勝ちにくい」部類である点を明記する。

## 出典

- [Camera Hunt - Scavenger Game - App Store](https://apps.apple.com/us/app/camera-hunt-scavenger-game/id1434485987)
- [Scavengar – Easy AR Creation - App Store](https://apps.apple.com/us/app/scavengar-easy-ar-creation/id1438349207)
- [Snapchat Turns Real World into AR Scavenger Hunt - Next Reality](https://mobile-ar.reality.news/news/snapchat-turns-real-world-into-ar-scavenger-hunt-with-nearly-instant-object-recognition-0230749/)
- [Offline Multiplayer Games - App Store](https://apps.apple.com/us/app/offline-multiplayer-games/id6753841580)
- [2 Player Games Offline - 1234 - App Store](https://apps.apple.com/app/id6756060767)
- [2 Player Games - Offline - App Store](https://apps.apple.com/us/app/-/id6743223202)
- [25 Free Jackbox Party Game Alternatives - CBR](https://www.cbr.com/jackbox-free-alternative-party-games/)
- [The Bedtime Story Generator - App Store](https://apps.apple.com/us/app/the-bedtime-story-generator/id6740924426)
- [AI Bedtime Storyteller - Kids - App Store](https://apps.apple.com/us/app/ai-bedtime-storyteller-kids/id6737245753)
- [StoryKit: AI Bedtime Stories - App Store](https://apps.apple.com/lc/app/storykit-ai-bedtime-stories/id6761138926)
- [AI Bedtime Stories - StoryBean - App Store](https://apps.apple.com/us/app/ai-bedtime-stories-storybean/id6755163292)
- [Whispero - Bedtime Stories - App Store](https://apps.apple.com/app/id6752776496)
- [My camera roll is a personality test - Medium (JournalSense)](https://medium.com/journalsense/my-camera-roll-is-a-personality-test-a94c8fb679fe)
- [Aurascan Photo Analysis - App Store](https://apps.apple.com/us/app/aurascan-photo-analysis/id6747202760)
- [Tinder's AI will analyze your camera roll to discover your "vibe" - PetaPixel](https://petapixel.com/2026/03/20/tinder-may-use-ai-to-scan-your-camera-roll/)
- [This creepy new Tinder feature scans your camera roll - The Tab](https://thetab.com/2026/03/30/this-creepy-new-tinder-feature-scans-your-camera-roll-to-find-matches-and-its-terrifying)
- [Photo Persona - YesChat](https://www.yeschat.ai/gpts-ZxX1wpfQ-Photo-Persona)
- [Timehop - Wikipedia](https://en.wikipedia.org/wiki/Timehop)
- [Live Wallpaper Maker/Converter - App Store](https://apps.apple.com/us/app/live-wallpaper-maker-converter/id1169344289)
- [Video to Live Wallpapers Maker - App Store](https://apps.apple.com/us/app/video-to-live-wallpapers-maker/id1397834699)
- [Video Wallpaper · Lock Screen - App Store](https://apps.apple.com/us/app/video-wallpaper-lock-screen/id1497777142)
- [Widgetsmith Case Study | RevenueCat](https://www.revenuecat.com/customers/widgetsmith)
- [Widgetsmith App Trends 2025 - AppstoreSpy](https://appstorespy.com/android-google-play/com.Widgetsmith.widget-trends-revenue-statistics-downloads-ratings)
- [Free AI Choose Your Own Adventure Story Mini-App - Wabi](https://wabi.ai/apps/choose-your-own-adventure)
- [Best AI Interactive Story Apps to Play in 2026 - Roletopia](https://www.roletopia.ai/en/blog/best-ai-interactive-story-apps-2026)
- [211+ Best Choose Your Own Adventure Apps & Games for iPhone (2026) - appshunter.io](https://appshunter.io/ios/topics/choose-your-own-adventure)
- [Apple's new App Review Guidelines clamp down on apps sharing personal data with 'third-party AI' - TechCrunch](https://techcrunch.com/2025/11/13/apples-new-app-review-guidelines-clamp-down-on-apps-sharing-personal-data-with-third-party-ai/)
- [Pixel Pals Widget Pet Game - paywall/revenue data - Adapty](https://adapty.io/paywall-library/pixel-pals-widget-pet-game/)
- [Boko: Tamagotchi Virtual Pet - App Store](https://apps.apple.com/gh/app/boko-tamagotchi-virtual-pet/id6759446145)
- [Remagotchi - App Store](https://apps.apple.com/us/app/remagotchi/id6741424611)
- [iPhone Pet Widget Guide - AIdorable Blog](https://www.aidorable.ai/blog/iphone-pet-widget)
- [Obe - Split Group Bills & IOU - App Store](https://apps.apple.com/us/app/obe-split-group-bills-iou/id6739432176)
- [The 7 best bill splitting apps of 2026, ranked by use case - Splitty](https://splittyapp.com/learn/best-bill-splitting-apps/)
- [Split - Receipt Scanner - App Store](https://apps.apple.com/id/app/split-receipt-scanner/id6743058849)
- [Splitwise - App Store](https://apps.apple.com/us/app/splitwise/id458023433)
- [Splitwise - Wikipedia](https://en.wikipedia.org/wiki/Splitwise)
- [Kanji Draw App - App Store](https://apps.apple.com/us/app/kanji-draw/id719401529)
- [Write It! Japanese - App Store](https://apps.apple.com/us/app/write-it-japanese/id1268225663)
- [Skritter: Write Japanese - App Store](https://apps.apple.com/us/app/skritter-write-japanese/id1370893674)
- [Kanji Teacher - Learn Japanese - App Store](https://apps.apple.com/us/app/kanji-teacher-learn-japanese/id1048445761)
- [Learn Kanji: 1st Grade Writing App - App Store](https://apps.apple.com/us/app/learn-kanji-1st-grade-writing/id1462606964)
- [Rhythm Swing - Music Drills App - App Store](https://apps.apple.com/us/app/rhythm-swing-fun-rhythm-drills-for-kids/id1007346233)
- [Haptic Hustle - App Store](https://apps.apple.com/us/app/haptic-hustle/id1530287164)
- [FunFit: At-Home Workout Games App - App Store](https://apps.apple.com/us/app/funfit-at-home-workout-games/id1606417343)
- [Active Arcade - App Store](https://apps.apple.com/ca/app/active-arcade/id1553158383)
