# 3本目アプリ案: 自由発想によるボールドアイデア

作成日: 2026-09-13
担当: product-researcher

## 経緯

2本目「かおゲー（KaoPlay）」は、企画レビュー（自由発想→選別→軽い競合確認、「一人で完結するか」のフィルタ）を通過し実装・実機バグ修正まで完了したが、オーナーが実機で実際にプレイした結果「あんまり面白くない」と判定し、2026-09-13に保留となった（`docs/15-app2-shelved-decision.md`）。これにより、**「企画書レベルの斬新さ・差別化」は「実際に触った時の面白さ（プレイフィール）」を保証しない**という教訓が得られた。

本ドキュメントは、オーナーの希望（完全に新しい案、過去案との非重複、表情認識・ARKit顔トラッキング系の回避）を踏まえ、3本目アプリの案をゼロから検討したものである。以下のファイルを全て確認し、既出のテーマ・中核メカニクスと重複しないことを確認した。

- `docs/01-idea-shortlist.md`（案1〜10）
- `docs/01c-bold-ideas.md`（案1〜7）
- `docs/05-next-idea-shortlist.md`（案A〜F）
- `docs/06-bold-ideas-round2.md`（案1〜6）
- `docs/10-app2-differentiation-ideas.md`（①〜⑤、かおゲー差別化ラウンド2）
- `docs/11-app2-differentiation-round3.md`（①〜⑤、かおゲー差別化ラウンド3）
- `docs/15-app2-shelved-decision.md`（保留決定の経緯）

## 進め方（確立済みの逆順アプローチ）

1. **自由発想**: 実装難易度・収益性・競合を横に置き、iPhone特有のハードウェア/センサー（カメラ、マイク、加速度計・ジャイロ、気圧計、近接センサー、磁気センサー、NFC、Taptic Engine/ハプティクス、LiDAR等）を起点に18案をラフに出した。
2. **選別**: 「一人で完結」「プレイフィールが想像しやすい」「SwiftUI(+SpriteKit)で実装可能」「予算ゼロ・Sideloadly配布で検証可能」「既出案と重複しない」の5条件で絞り込んだ。
3. **軽い競合確認**: 絞った案についてWebSearchで酷似競合を確認した。**この過程で、想定以上に多くの案に既存の酷似アプリが見つかった**（App Storeは15年以上の歴史があり、センサー起点の一発ネタ的アイデアはすでに一通り試されている、という実感を得た）。結果、最終案は4案に絞られている。

---

## ステップ1: 自由発想で出した18案（参考記録）

1. てまわしランタン（ジャイロの回転運動で発電する手回しランタン/ラジオ）
2. かくれんぼセンサー（近接センサーで「覗かれた瞬間」に隠れる反射神経ゲーム）
3. 傾けて描く、ひとり砂の庭（デバイスの傾きで玉を転がし砂紋を描く創作ツール）
4. ハプティック・シモン（振動パターンだけを記憶して再現するゲーム）
5. スティーディハンド（手をできるだけ静止させ続ける持久ゲーム）
6. ジャイロスピナー（回して勢いをつけるアクションゲーム）
7. セーフクラッキング（回転とハプティクスの"クリック感"で金庫を開ける）
8. 触覚迷路（視覚情報なし、振動の強弱だけで壁を避けて進む迷路）
9. 磁場トレジャーハント（磁気センサーで家の中に隠した金属を探す）
10. 心拍シンクロ瞑想（加速度センサーで胸に当てた心拍を検出し同期させる）
11. 指点字ハプティクス学習（振動パターンで点字を教える）
12. 一人じゃんけんバトル（カメラの手の形検出でAIと対戦）
13. 影絵トレイルアート（人物シルエットの動きの軌跡を光の絵として残す）
14. 石段のぼり育成ゲーム（気圧センサーで実際に階段を上ると進む登山ゲーム）
15. フォーカス狩り（カメラのピント合わせの鮮明度を競う距離感ゲーム）
16. 手回しオルゴール（回転速度とリズムでオルゴールの音色を操る）
17. 重力クランク（デバイスの向き反転で重力方向が変わるパズル）
18. 気圧予報あてっこ（気圧トレンドの変化だけから翌日の天気を予想する日課ゲーム）

---

## ステップ2〜3: 選別と競合確認

### 採用した4案（詳細はステップ4参照）

- #1 てまわしランタン
- #2 かくれんぼセンサー
- #3 傾けて描く、ひとり砂の庭
- #15 フォーカス狩り

### 競合確認で除外した案とその理由

| # | 案名 | 除外理由（WebSearchで確認した直接競合） |
|---|---|---|
| 4 | ハプティック・シモン | **Apptics – Vibration Memory Game**が「振動パターンを記憶して再現するSimon Says型ゲーム」という、ほぼ同一コンセプトで既に存在する。 |
| 5 | スティーディハンド | Hold Steady、Balancing Act For Steady Hand、SteadyHand、BlockSteady、BuzzWire: Steady Handなど、この方向性だけで5個以上の直接競合が既に存在し、ジャンルとして飽和している。加えて「静止・抑制を保つ」ことを核にする点が、かおゲーで不評だった「無表情チャレンジ」の持久/抑制系メカニクスと質的に近く、実プレイでの面白さに懸念がある。 |
| 6 | ジャイロスピナー | GyroHero、Gyro Racerなど、汎用のジャイロスコープ操作アーケードゲームが既に複数存在。 |
| 7 | セーフクラッキング | **The Impossible Safe – Crack It**（ハプティクスで"クリック感"を探る）、**un:safe – pop the lock**、**Gyro Lockdown**（まさにジャイロで回転させてハプティクスで感じ取る金庫破り）など、直接一致する競合が多数存在。 |
| 8 | 触覚迷路 | **Dark Maze: Blind Escape**、**Haptic Maze**が「視覚なし・振動だけで壁を避けて進む迷路」というほぼ同一コンセプトで既に存在する。 |
| 9 | 磁場トレジャーハント | 「金属探知機」系アプリはappshunter.io調べで217種以上確認されるほど飽和したジャンル。ハプティクスでの近接フィードバックも既存アプリの標準機能。 |
| 10 | 心拍シンクロ瞑想 | 加速度センサーで胸の上の心拍（体振動心電図/SCG）を検出する技術自体は**HeartScan**等で既に商用化されている。加えて、実際の心拍を測定・表示する体験は健康関連の主張としてApp Store審査ガイドライン1.4.1のリスクがあり（`docs/11`のきろくミラー案と同様の懸念）、リスクとリターンのバランスが悪いと判断。 |
| 11 | 指点字ハプティクス学習 | **VibraBraille**が「振動で点字パターンを表現し学習する」というほぼ同一コンセプトで既に存在する。 |
| 12 | 一人じゃんけんバトル | **AI Rock Paper Scissors**（Core MLでの手の形検出×AI対戦）、**Rock Paper Scissors 3D & AR**（リアルタイム手認識×AI対戦）がいずれも直接一致する競合として既に存在する。 |
| 13 | 影絵トレイルアート | **Motion Snapshot**、**Trace: Motion Art**、**Motionline**など、人物/動きの軌跡を抽出して光の軌跡アートに変換するアプリが既に複数存在する。 |
| 14 | 石段のぼり育成ゲーム | **To Scale – Climbing Game**、**Ascend – Floor Counter**、**StairClimbs**など、実際の階段上り（気圧センサー/HealthKit由来の階数）をゲーム的な進行に変換するアプリが既に複数存在する。 |
| 16 | 手回しオルゴール | #1「てまわしランタン」と回転クランクという中核メカニクスが重複するため、1本のドキュメント内では統合せず#1のみ採用。 |
| 17 | 重力クランク | デバイスの傾き・向きで重力方向が変わるパズルは、既存の「傾けて操作するアクションゲーム」ジャンル（tilt maze全般）に実質的に包含され、独自性を主張しづらいと判断し詳細検討前に除外。 |
| 18 | 気圧予報あてっこ | 競合は確認できなかったが、「気圧のトレンドを見て翌日の天気を予想する」という受動的な当てっこは、操作している瞬間の身体的な気持ちよさ（プレイフィール）が他の採用案より弱く、選別基準「プレイフィールが想像しやすい」を優先して見送った。 |

(#2「かくれんぼセンサー」「#3 傾けて描く、ひとり砂の庭」「#15 フォーカス狩り」は後述のとおり競合確認をクリアしたため採用した。)

---

## ステップ4: 最終4案の詳細

## 案1: てまわしランタン（Wind-Up Lantern）

**スコア: 実装難易度4 / 収益性3 / 競合過多度5 / ASO余地4 ＝ 合計16**

- **概要**: `CMMotionManager`のジャイロスコープ（回転速度、Apple標準・無料・完全オンデバイス）を使い、iPhoneを手の中で輪を描くように回す（クランクを回す動作）ことで、画面内のランタン・壊れたラジオ・蓄音機といった「手回し発電デバイス」にエネルギーを送り込む短いシナリオ/ステージ集。回す速さと一定のリズムを保つことでエネルギーが蓄積し、暗い夜道を照らす、ラジオから音楽が流れ出す、といった小さな達成が得られる。止めると灯が徐々に消えるため「回し続ける」という持続的な身体動作がゲームの核になる。
- **なぜ面白いか（操作していて気持ちいいポイント）**: 実際に手回し充電ライトやオルゴールを回した経験のある人なら分かる「手応えのある抵抗感→一定ペースで回すと安定して明かりが灯る」という物理的な満足感をデジタルで再現する。腕をくるくる回す動きそのものが普段のスマホ操作にない身体性を持ち、画面の明るさ・音の滑らかさ・Hapticsの振動パターンが回転の安定度にリアルタイムに追従することで、「うまく回せている」という手応えが視覚・聴覚・触覚の三重フィードバックで返ってくる。速すぎると過負荷で軋む音が鳴るなど、回し方そのものにチューニングの奥深さを持たせられる。
- **想定収益モデル**: 基本無料（最初のランタンのみ）＋買い切りで追加シナリオ（ラジオ局・オルゴール・暖炉等のテーマ）を解放。正直な評価として、単一メカニクスの広がりには限界があり、長期の継続課金力は中程度と見るのが妥当。
- **実装難易度**: 低〜中。`rotationRate`の取得自体はApple標準APIで即座に使えるが、「気持ちよく回せている」と感じる閾値・減衰カーブの調整に反復作業が必要。SpriteKit/Core Animationでの光量・パーティクル表現、CoreHapticsでの回転連動フィードバックが主な実装コスト。
- **競合確認の結果**: 「gyroscope game」「hand crank game app」等でWebSearchしたが、GyroHero・Gyro Racer等の既存ジャイロゲームはいずれも「傾ける/振る/回す」を単発コマンド入力として使うアーケード型で、持続的な回転動作でエネルギーを蓄積する発電機シミュレーターという組み合わせの直接競合は見当たらなかった。

---

## 案2: かくれんぼセンサー（Don't Get Caught）

**スコア: 実装難易度5 / 収益性2 / 競合過多度5 / ASO余地3 ＝ 合計15**

- **概要**: 近接センサー（画面上部、Apple標準・無料、`UIDevice.current.proximityMonitoringEnabled`で取得可能）を使う、一人用のリアルタイム反射神経ゲーム。画面内の「何か」（鬼・モンスター・先生などテーマは複数用意）が不定期に「こちらを見る」合図（音・Hapticsの予告）を出す。合図が鳴った瞬間、プレイヤーは素早くiPhone上部のセンサーを手や頬で覆って「隠れる」。反応が遅れる、または安全な時間帯に覆いっぱなしにしていると減点される。ラウンドを重ねるごとに合図のタイミングが読みにくくなっていく。
- **なぜ面白いか（操作していて気持ちいいポイント）**: スマホを手で素早く覆う、という普段絶対にしない「とっさの動き」が核。合図が鳴った瞬間に体がビクッと反応し、間に合った時の「ヒヤッとした後の安堵」という感情の振れ幅がそのまま遊びの快感になる。これは単純なタップ反応ゲームにはない身体的な緊張と解放のリズムで、「だるまさんがころんだ」を一人で・センサーを鬼にして再現する発想。正解/失敗が物理的な手の動き（センサーのON/OFF）で判定されるため、画面を見続けなくてもプレイできる軽さもある。
- **想定収益モデル**: 基本無料＋テーマパック（モンスター・先生・幽霊など）の買い切り、または広告（インタースティシャル）。反射神経ゲームはリトライ性が高く短時間セッションを何度も回しやすいが、単価・LTVは低めと正直に評価する。
- **実装難易度**: 低。`proximityMonitoringEnabled`・`UIDevice.proximityStateDidChangeNotification`はApple標準APIで取得自体は数行で完結する。タイミング設計（合図の予告フレーム数、覆うまでの許容時間）のゲームバランス調整が主な作業。センサーが画面最上部のごく小さい範囲にしかないため、普段の持ち方で誤って覆ってしまう誤操作への配慮も必要。
- **競合確認の結果**: 「proximity sensor game」「cover screen hide game」等でWebSearchしたが、既存の近接センサー活用アプリはすべて「画面の自動消灯/操作ロック」を目的とした実用ユーティリティ（Auto Proximity Detection等）であり、近接センサーを反射神経ゲームの入力に使う消費者向けゲームは見当たらなかった。

---

## 案3: フォーカス狩り（Focus Hunt）

**スコア: 実装難易度3 / 収益性3 / 競合過多度5 / ASO余地3 ＝ 合計14**

- **概要**: 背面カメラのライブ映像に対し、画面中央のターゲット（身の回りの物・観葉植物・ペット等）をできるだけシャープなピントに合わせることを競う、写真撮影の「ピントを合わせる」行為そのものをゲーム化したミニゲーム。カメラ映像の鮮明度を、Apple標準のAccelerate/vImageフレームワーク（無料・端末内、Laplacian分散等の古典的な画像処理指標）でリアルタイムにスコア化し、制限時間内にプレイヤーが身体（iPhone）を前後に動かしてベストフォーカスの距離を探る。外部ライブラリ・機械学習モデル不要。
- **なぜ面白いか（操作していて気持ちいいポイント）**: スマホゲームの大半は画面内のタップ・スワイプ操作で完結するが、本案は「実際に自分の身体をカメラのレンズのように動かす」という物理的な距離調整がそのままスコアに反映される。対象に近づきすぎ/遠すぎるとぼやけ、ちょうどいい距離でパチッと合焦した瞬間の視覚的な快感（カメラ好きなら知っている「ピントが合う瞬間」の気持ちよさ）をそのままゲームの報酬にする。対象は身の回りの何でもよく、プレイ場所によって難易度・景色が変わる発見性もある。
- **想定収益モデル**: 基本無料＋お題テーマパック（マクロ撮影チャレンジ、遠距離チャレンジ等）の買い切り。正直な評価として、一般層への訴求力は中程度だが、ベストフォーカス写真を保存・共有できる機能を付ければ写真好き・カメラ好き層には強く刺さる可能性がある。
- **実装難易度**: 中。`AVCaptureSession`でのライブカメラ映像取得自体は標準APIだが、フレームごとの鮮明度スコア算出（Laplacian分散等、Accelerate/vImageで実装）には画像処理の実装経験が必要。リアルタイム処理のパフォーマンスチューニングも必要。
- **競合確認の結果**: 「camera focus distance game」「blur detection game app」等でWebSearchしたが、見つかったのは写真編集のボケ効果アプリ（Photo Focus、Vivid Focus）やピント計算ツール（Hyperfocal Calculator）など静止画の後処理・撮影準備用の実用ツールのみで、リアルタイムのピント合わせ精度を競うゲームとしての直接競合は見当たらなかった。

---

## 案4: 傾けて描く、ひとり砂の庭（Tilt Sand Garden）

**スコア: 実装難易度3 / 収益性4 / 競合過多度2 / ASO余地3 ＝ 合計12**

- **概要**: CoreMotionのデバイス姿勢（重力ベクトル、Apple標準・無料）を使い、iPhoneを傾けることで画面内の小さな玉（パチンコ玉のような質感）を転がし、玉が通った軌跡だけが砂の上に「砂紋」として残っていく、一人用の創作・瞑想ツール。玉は直接タップできず、傾きの物理シミュレーション（慣性・摩擦）を通じてのみ動かせる間接操作が特徴。完成した砂紋パターンは画像として保存・共有できる。
- **なぜ面白いか（操作していて気持ちいいポイント）**: 既存の砂庭アプリの多くは指でなぞって直接砂を掻く「直接操作」型だが、本案は玉の動きに物理的な「間（ラグ）」があるため、思った通りにまっすぐ線を引けない・勢いがつきすぎて行き過ぎるといった、アナログの本物の卓上砂庭おもちゃ（傾けて動かすタイプ）に近い「じれったさ」と「うまく制御できた時の達成感」が交互に訪れる。手首の微妙な傾きの加減に模様が反応する繊細な操作感が、単純な指ドラッグにはない身体性を生む。
- **想定収益モデル**: 基本無料（砂の色・玉1種）＋サブスクもしくは買い切りで砂の質感・玉のバリエーション・BGMテーマを追加。パーソナライズ/癒やし系ツールはWidgetsmith等の実績からも一定の収益ポテンシャルがあるジャンルだが、既存の砂庭アプリとカテゴリが重なるため差別化なしでは埋没するリスクがある。
- **実装難易度**: 中。`CMMotionManager`の`deviceMotion`（姿勢・重力ベクトル）取得自体は標準APIだが、玉の物理シミュレーション（SpriteKitの物理エンジン等）と、軌跡を砂の表現として残す描画（Core Image/Metal、またはSwiftUIのCanvas）の組み合わせにチューニングの手間がかかる。
- **競合確認の結果（正直な評価・要注意）**: WebSearchで確認した限り、「Sand Garden」「Zen Sand: Relaxing Garden」は指で直接なぞって砂を掻くタイプで本案とは操作方式が異なるが、**「Zen Garden」（App Store ID 6448643145）は「iPhoneを傾けて玉を穴に導く」というゲームメカニクスが本案の操作方式と一致する**ことを確認した。ただしこちらは「穴に玉を入れてクリアするパズルゲーム」であり、本案の「自由に模様を描く創作・瞑想ツール（ゴールなし）」とは体験の目的が異なる。**4案の中で唯一、操作方式そのものに直接競合が存在するため、採用する場合は「ゴールのない自由創作」という方向性を仕様段階で明確に打ち出す必要がある。**

---

## 総合評価

| # | 案名 | ひとこと | 実装難易度 | 収益性 | 競合過多度 | ASO余地 | 合計 |
|---|---|---|---|---|---|---|---|
| 1 | てまわしランタン | ジャイロでクランクを回し発電する身体的な手触り | 4 | 3 | 5 | 4 | **16** |
| 2 | かくれんぼセンサー | 近接センサーを覆って隠れる反射神経ゲーム | 5 | 2 | 5 | 3 | **15** |
| 3 | フォーカス狩り | 身体の距離移動でカメラのピントを合わせる | 3 | 3 | 5 | 3 | 14 |
| 4 | 砂の庭 | 傾きで玉を転がし砂紋を描く創作・瞑想ツール | 3 | 4 | 2 | 3 | 12 |

**総合順位（合計スコア順）**: 1(16) > 2(15) > 3(14) > 4(12)

## 特にプレイフィールの面白さが想像しやすい案（ピックアップ）

1. **案1: てまわしランタン** — スコア最高評価。「手回し発電機を実際に回す」という物理的な手応えが、視覚（灯りの強さ）・聴覚（音の滑らかさ）・触覚（Hapticsの振動）の三重フィードバックで返ってくる設計のため、数秒触った瞬間の「回せている感」が最も具体的に想像できる。競合も見当たらず、実装難易度も4案中最も低い。
2. **案2: かくれんぼセンサー** — 「合図が鳴った瞬間にパッとセンサーを覆う」というとっさの身体反応と、間に合った時の安堵感という感情の振れ幅が、タップ中心のゲームにはない緊張と解放のリズムを生む。実装も非常に軽量で、競合も見当たらない。

## 申し送り事項

- 本ドキュメント作成時点で`ListAgents`ツールは本セッション（product-researcherサブエージェント）に提供されておらず、`CLAUDE.md`記載の既知の制約どおりaso-marketerへの直接の問い合わせは行えない。市場性（本ドキュメント）とASO観点（検索されやすさ・カテゴリ適性）のクロスチェックは、オーケストレーターがaso-marketerを起動し本ファイルを読ませる仲介フローに委ねることを推奨する。
- 案2（かくれんぼセンサー）・案3（フォーカス狩り）は収益性の正直な評価がやや低め（反射神経ゲーム/ニッチな写真好き層向け）である点を選定時に考慮されたい。
- 案4（砂の庭）は4案中唯一、操作方式（傾けて玉を動かす）そのものに直接競合（Zen Garden）が存在するため、選定する場合は「ゴールのない自由創作」という方向性の差別化が前提になる。
- 今回の競合確認では、想定した18案の半数以上（10案）に既存の酷似アプリが見つかった。これはApp Storeの成熟度の高さ（センサー起点の一発ネタ的アイデアはほぼ一通り試されている）を示しており、今後のアイデア出しでは「競合が少ないこと」よりも「競合があっても実行品質で差別化できるか」を重視する判断も選択肢になりうる。

## 出典

- [Vibration Memory Game: Apptics - App Store](https://apps.apple.com/au/app/vibration-memory-game-apptics/id6740833075)
- [Hold Steady - App Store](https://apps.apple.com/us/app/hold-steady/id1595872964)
- [Balancing Act For Steady Hand - App Store](https://apps.apple.com/us/app/balancing-act-for-steady-hand/id768424794)
- [SteadyHand - steadyhandtest.com](https://steadyhandtest.com/)
- [BlockSteady - App Store](https://apps.apple.com/ca/app/blocksteady/id1441532033)
- [BuzzWire: Steady Hand - App Store](https://apps.apple.com/app/id1589917437)
- [GyroHero: Gyroscope Game - App Store](https://apps.apple.com/iq/app/gyrohero-gyroscope-game/id6532621812)
- [Gyro Racer: A Gyroscope Game App - App Store](https://apps.apple.com/us/app/gyro-racer-a-gyroscope-game/id6444010277)
- [The Impossible Safe – Crack it - App Store](https://apps.apple.com/us/app/the-impossible-safe-crack-it/id1573468310)
- [un:safe - pop the lock - App Store](https://apps.apple.com/us/app/un-safe-pop-the-lock/id1582291621)
- [Gyro Lockpicking - itch.io](https://moksh-gupta.itch.io/gyro-lockpicking)
- [Unlock it: Safe Cracker Puzzle - App Store](https://apps.apple.com/lc/app/unlock-it-safe-cracker-puzzle/id6738165926)
- [Dark Maze: Blind Escape - App Store](https://apps.apple.com/us/app/dark-maze-blind-escape/id6449601128)
- [Haptic Maze](https://uoa-eresearch.github.io/haptic/)
- [217+ Best Metal Detector Apps for iPhone (2026) - appshunter.io](https://appshunter.io/ios/topics/metal-detector)
- [Metal Detector° - App Store](https://apps.apple.com/us/app/metal-detector/id6450298843)
- [Accuracy of the Instantaneous Breathing and Heart Rates Estimated by Smartphone Inertial Units - PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC11859794/)
- [HeartScan: Heart Rate Monitor - heartscan.app](https://heartscan.app/)
- [VibraBraille - App Store](https://apps.apple.com/us/app/vibrabraille/id6754166495)
- [AI Rock Paper Scissors App - App Store](https://apps.apple.com/us/app/ai-rock-paper-scissors/id6738329126)
- [Rock Paper Scissors 3D & AR - App Store](https://apps.apple.com/us/app/rock-paper-scissors-3d-ar/id6747378699)
- [Motion Snapshot - App Store](https://apps.apple.com/us/app/motion-snapshot/id6738301692)
- [Trace: Motion Art - App Store](https://apps.apple.com/us/app/trace-motion-art/id6791380211)
- [Motionline - App Store](https://apps.apple.com/us/app/motionline/id6759052131)
- [To Scale – Climbing Game - App Store](https://apps.apple.com/us/app/to-scale-climbing-game/id6762200185)
- [Ascend — Floor Counter - App Store](https://apps.apple.com/us/app/ascend-floor-counter/id1493411512)
- [StairClimbs - App Store](https://apps.apple.com/gb/app/stairclimbs/id1084264756)
- [Auto Proximity Detection - App Store](https://apps.apple.com/us/app/auto-proximity-detection/id909858532)
- [Photo Focus: Blur Effects - App Store](https://apps.apple.com/fm/app/photo-focus-blur-effects/id1063223648)
- [Vivid Focus: Photo Lens Blur - App Store](https://apps.apple.com/us/app/vivid-focus-photo-lens-blur/id6446104942)
- [Sand Garden - App Store](https://apps.apple.com/au/app/sand-garden/id343283376)
- [Zen Sand: Relaxing Garden - App Store](https://apps.apple.com/za/app/zen-sand-relaxing-garden/id6764150850)
- [Zen Garden - App Store (tilt-to-hole puzzle)](https://apps.apple.com/bb/app/zen-garden/id6448643145)
- [Red/Green Light - App Store](https://apps.apple.com/us/app/red-green-light/id1591583332)
- [Red Light Green Light Pro - App Store](https://apps.apple.com/ae/app/red-light-green-light-pro/id1589204209)
