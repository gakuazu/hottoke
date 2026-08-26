# Phase 1b: ASOレビュー（aso-marketer）

作成日: 2026-08-26
担当: aso-marketer
対象: `docs/01-idea-shortlist.md`（product-researcher作成、案1〜5）

## 前提・スタンス

- 現段階ではApp Store正式公開は未定で、まず家族向けにSideloadlyで無料実機配布して価値検証する方針と理解している。したがって本レビューは「今すぐASO対策が必要」という話ではなく、**将来的に正式公開する場合に見込める発見性・成長余地が、どのアイデアを優先すべきかの判断材料になるか**という観点での評価。
- オーナーは非エンジニア・予算ほぼゼロなので、有料ASOツール（AppTweak、Sensor Tower等）は使わずWebSearchで拾える範囲の実データ（レビュー数・評価・売上推定・キーワード検索量の目安）で裏付けを取った。数値は二次情報源（RevenueCat、Sensor Tower記事、各種ブログ）経由であり厳密な一次データではない点に留意。
- 評価軸: (a) 狙えるキーワードの検索ボリューム感、(b) そのキーワードでの競合の強さ・新規アプリが上位に入れる現実性、(c) タイトル/サブタイトル案、(d) 市場性・ASO観点での総合評価（筋の良し悪し）。

---

## 案1: 保証書・レシート管理アプリ（Warranty Keeper）

**狙えるキーワード**: `warranty tracker` / `receipt scanner` / `warranty organizer` / 日本語なら `保証書 管理` `レシート 管理` `保証期限`

**競合状況（WebSearch裏付け）**:
- App Store内に類似アプリが多数存在: Docly、Warrantify、SnapRegisters Warranty Tracker、Warranty Tracker and Keeper、Warranty Receipt Tracker、Warrantly、Receipt Safe: Warranty Trackerなど。
- 重要な発見: このほとんどが「まだ十分なレビュー数がなく評価が表示されない」状態（WarrantlyもDoclyも同様）。つまり**支配的な1位アプリが存在しない代わりに、市場自体の絶対規模も小さい**ことを示唆している。
- 隣接する広義の「スキャナー」カテゴリ（Genius Scan、Adobe Scan、CamScanner等）はレビュー数が桁違いに多く、そちらに真正面から出ると勝ち目はない。ただし「保証書管理」という狭いサブカテゴリに絞れば、その巨人たちと直接キーワード競合しない。

**タイトル/サブタイトル案**:
- EN: `Warranty Keeper: Receipt & Warranty Tracker` / サブタイトル `Track warranties, scan receipts, get reminders`
- JP: `保証書管理 - Warranty Keeper` / サブタイトル `レシート撮影で保証期限を自動管理`

**ランキング現実性**: 新規アプリでも「warranty tracker」の完全一致・部分一致キーワードでカテゴリ内トップ10〜20入りは現実的（競合が弱いため）。ただし検索母数自体が小さく、上位表示できても得られるインストール数は多くない見込み。

**総合評価**: **中程度〜やや良い**。競合が弱いのでASO的には「刺さりやすい」が、天井が低い（誰も大きく抜け出していない=市場が本質的にニッチ）。継続利用率の低さ（撮る習慣化しにくい）というプロダクト側のリスクと合わせると、ASOだけで大きく伸ばせる案ではない。堅実だが上振れは期待しにくい。

---

## 案2: 資格試験・語学向けAIフラッシュカードアプリ（JLPT特化）

**狙えるキーワード**: `JLPT vocabulary` / `JLPT N3 words` / `JLPT flashcards` / 日本語 `日本語能力試験 単語` `JLPT 単語帳`

**競合状況（WebSearch裏付け）**:
- 汎用フラッシュカードの巨人（Quizlet: 月間アクティブ6,000万人規模、Anki: AnkiMobile単体で月間$700k規模の売上推定）は圧倒的だが、**「JLPT」という特化キーワードそのものでは戦っていない**（ブランド名や汎用「flashcards」語で強いだけ）。
- JLPT特化アプリ（RAKU JLPT Vocabulary、JLPT Plus、JLPT word、JLPT Jg Plusなど）は複数存在するが、いずれも「レビュー数が少なく評価未表示」レベルの小規模プレイヤーで、明確な1強がいない。
- つまり「JLPT」という長尾キーワードは**検索する人はいる（試験特化アプリが何個も出ている＝需要の存在証拠）が、上位を取っている実力者がまだいない**という、ASO的には理想に近い状況。

**タイトル/サブタイトル案**:
- EN: `JLPT Vocab: N5-N1 Flashcards` / サブタイトル `Spaced repetition for the Japanese exam`
- JP: `JLPT単語帳 - N1〜N5攻略` / サブタイトル `間隔反復で試験によく出る単語を効率暗記`

**ランキング現実性**: 「JLPT vocabulary」「JLPT N3」等の複合キーワードでカテゴリ内・キーワード検索結果の上位（5〜10位以内）は新規アプリでも十分狙える。Quizlet/Ankiの汎用ブランド力とは正面衝突しない棲み分けが成立している。

**総合評価**: **良い**。案の中で最もASOの教科書的セオリー（大手が獲っていない特化ロングテールキーワードを取る）に合致している。ただしAI差別化部分（Foundation Models）はキーワードとして誰も検索しないため、ASO上の武器にはならない点は認識しておく必要がある（あくまで「JLPT特化」というポジショニングそのものがASOの武器）。

---

## 案3: ニッチ系ウィジェット/ロック画面カスタマイズアプリ

**狙えるキーワード**: `widget` / `lock screen widget` / 狭いテーマ名（例: `和柄 ウィジェット` `レトロ フィルム ウィジェット`）

**競合状況（WebSearch裏付け）**:
- 「widget」単体の検索ボリュームは月間3.3万〜20万件規模と推定される非常に大きいキーワード。しかしWidgetsmithが**6,500万ダウンロード・評価130万件・評価4.7、月間$200k規模の売上**という圧倒的な一強状態でこのキーワードを完全に押さえている。
- Lock Screen 26、LockWidgetなど他のウィジェットアプリも存在するが、いずれもWidgetsmithの背中は見えない規模。
- 「和柄」「フィルム風」等の極めて狭いテーマ名で差別化しても、そのテーマ名自体がApp Store内でほぼ検索されない（検索ボリュームが計測下限以下の可能性が高い）ため、**ASO＝App Store内検索経由の発見性にはほぼ頼れない**。

**タイトル/サブタイトル案**:
- 広い「widget」語をタイトルに含めても上位表示は望み薄。むしろ `和柄ウィジェット` `フィルム風ロック画面` のような固有テーマ名をブランド名に組み込み、Instagram/Pinterest/小紅書的な美意識コミュニティでの外部バイラルに発見性を依存する設計にせざるを得ない。

**ランキング現実性**: 主要キーワードでの上位表示は事実上不可能。ニッチキーワードは競合が無い代わりに検索需要そのものがほぼ無い。

**総合評価**: **悪い（ASO観点では）**。収益ポテンシャルの天井はカテゴリとして実証済み（Widgetsmithの実績）だが、それは「App Store内検索で見つけてもらう」型のASOでは再現できない。SNS発の審美系バイラルという別のマーケティングチャネルに依存する前提でないと成立せず、予算ゼロ・非エンジニア・個人開発という体制ではそのバイラル獲得も難易度が高い。ASOだけを見れば5案中最も筋が悪い。

---

## 案4: 「買わない」チャレンジ・衝動買い防止アプリ（No-Buyトラッカー）

**狙えるキーワード**: `no buy` / `no spend challenge` / `no spend tracker` / `impulse buying` / 日本語 `買わないチャレンジ` `節約チャレンジ` `衝動買い 防止`

**競合状況（WebSearch裏付け）**:
- 直近1〜2年で立ち上がったばかりの新興カテゴリで、NoBuy - No Spend Challenge、Stop Impulse Buying（評価4.28・レビュー75件）、Quit Impulse Buying、Euna、Buy or Bye、Why Buy、mallow、NoSpendなど**類似アプリが急増しているが、いずれも小規模（レビュー数が少数か未表示）で1強不在**。
- 隣接する行動変容系カテゴリの実績値として、I Am Sober（禁酒ストリークアプリ）は**米国App Store単体で約12,000件のレビュー・評価4.8**、月$9.99/年$39.99のサブスクで月間$200k規模の収益と推定されており、「ストリーク記録＋行動変容」という型がサブスクとして機能することを裏付けている。
- つまりNo-Buyトラッカーは、①競合が弱く上位表示が狙いやすい、②トレンドで検索需要が伸びている最中、③隣接カテゴリで収益モデルの実証がある、という3条件が揃っている。

**タイトル/サブタイトル案**:
- EN: `No Buy: Impulse Spending Tracker` / サブタイトル `Streaks, cooldown timer & no-spend challenge`
- JP: `NoBuy - 買わないチャレンジ` / サブタイトル `連続記録と衝動買い防止タイマー`

**ランキング現実性**: 「no spend challenge」「no buy tracker」等の複合キーワードで新規アプリがトップ5〜10入りする現実性は高い。カテゴリがまだ固まっておらず、先行者優位を取りやすいタイミング。

**総合評価**: **良い（5案中最有力）**。ASOの観点だけでなく、TikTok発の「no-buyチャレンジ」トレンドという外部流入経路もあり、ASOと外部バイラルの両輪が期待できる点が案2（JLPT）より優位。ただし「機能がシンプルで模倣されやすい」というリスクは事実で、今後半年〜1年でカテゴリが寡占化する可能性があるため、動くなら早いほうが良い。

---

## 案5（参考枠）: AI週次振り返りコーチ

**狙えるキーワード**: `journal` / `diary` / `weekly review` / `goal journal` / 日本語 `振り返り` `日記`

**競合状況（WebSearch裏付け）**:
- 最大の障壁はApple純正「ジャーナル」アプリで、**評価4.8・レビュー数はおよそ10万件規模**、iOS標準搭載（無料・端末プリインストール相当の配布力）かつiOS 26でiPad/Mac対応・音声メモ自動文字起こしと機能強化を継続中。
- Day Oneも「journal」「diary」カテゴリの評判の高い定番アプリとして扱われ、Sensor Tower推定で月間$400k規模の売上と報じられている。Journey、Reflectly、Stoicも同様に定番化済み。
- 「journal」「diary」という主要キーワードは、OS標準アプリ＋複数の実績ある有料アプリで完全に埋まっており、新規アプリが割り込む余地はほぼない。「週次振り返り」のような差別化キーワードに逃げても、その語自体の検索ボリュームがほぼ無いと推測される。

**総合評価**: **悪い**。product-researcher側も参考枠として優先度を下げているが、ASO観点でも同じ結論になる。OS標準アプリと同じ検索意図（journal/diary）で戦う構造そのものが不利で、5案中最もASOが機能しにくい。

---

## 総合評価まとめ

| 案 | 主要キーワードの競合強度 | 新規アプリの上位表示現実性 | 検索需要の大きさ | ASO総合評価 |
|---|---|---|---|---|
| 1. 保証書・レシート管理 | 弱い（1強不在） | 高い | 小さい（市場自体がニッチ） | 中〜やや良い |
| 2. JLPT特化フラッシュカード | 弱い（特化語では1強不在、汎用語はQuizlet/Ankiが強いが棲み分け可） | 高い | 中（試験特化のロングテール） | 良い |
| 3. ニッチウィジェット | 主要語は激強（Widgetsmith一強）、ニッチ語は無風 | 主要語はほぼ不可能、ニッチ語は需要ゼロに近い | 主要語は巨大だが取れない／ニッチ語はほぼ無い | 悪い |
| 4. No-Buyトラッカー | 弱い（新興カテゴリ、1強不在） | 高い | 中〜伸びつつある（トレンド） | **良い（最有力）** |
| 5. AI週次振り返りコーチ | 極めて強い（Apple純正＋Day One等） | 低い | 主要語は巨大だがOS標準に阻まれる | 悪い |

### ASO観点で最も有望な案: 案4（No-Buyトラッカー）

理由:
1. 競合アプリの大半がまだレビュー数の少ない新興プレイヤーで、明確な1強が存在しない＝新規アプリでも上位表示を狙いやすい。
2. 隣接する行動変容系カテゴリ（I Am Sober: 米国レビュー約12,000件・評価4.8・月$200k規模）で、ストリーク記録型サブスクという収益モデルが実証済み。
3. TikTok発の「no-buyチャレンジ」というトレンドがApp Store外の検索流入・SNS流入も後押しする、ASOと外部バイラルの両輪が効く数少ない案。

次点は案2（JLPT特化フラッシュカード）。ASOのセオリー（大手が取っていない特化ロングテールキーワードを取る）に最も忠実な案で、案4と並んで「良い」評価だが、対象ユーザー母数（JLPT受験者という狭い属性）が案4（節約・買い物という誰もが持つ習慣）より小さく、トレンド性による外部流入の後押しも弱いため、僅差で案4を上位とした。

案3（ウィジェット）と案5（振り返りコーチ）はASO観点では明確に筋が悪い。案3は「検索されて見つかる」型のASOがそもそも機能せず外部バイラル前提の別ゲームになる点、案5はOS標準アプリと検索意図が完全に衝突する点が致命的。

## 出典

- [SnapRegisters Warranty Tracker - App Store](https://apps.apple.com/us/app/snapregisters-warranty-tracker/id6757603213)
- [Warrantify - Warranty Tracker - App Store](https://apps.apple.com/us/app/warrantify-warranty-tracker/id6749649028)
- [Warranty Tracker and Keeper - App Store](https://apps.apple.com/us/app/warranty-tracker-and-keeper/id6449024145)
- [Receipt Safe: Warranty Tracker - App Store](https://apps.apple.com/us/app/receipt-safe-warranty-tracker/id6755928701)
- [Docly - Warranty Tracker - App Store](https://apps.apple.com/my/app/docly-warranty-tracker/id6756065053)
- [Warrantly - Warranty Tracker - App Store](https://apps.apple.com/us/app/warrantly-warranty-tracker/id6758876669)
- [RAKU JLPT Vocabulary - App Store](https://apps.apple.com/ca/app/raku-jlpt-vocabulary/id6754219736)
- [JLPT Plus: Japanese Vocabulary - App Store](https://apps.apple.com/us/app/jlpt-plus-japanese-vocabulary/id6744651554)
- [JLPT word, Japanese Vocabulary - App Store](https://apps.apple.com/us/app/jlpt-word-japanese-vocabulary/id1491139259)
- [Anki vs Quizlet: Free Flashcards vs $35.99 Paywall - LearnClash](https://learnclash.com/blog/anki-vs-quizlet)
- [Widgetsmith - App Store](https://apps.apple.com/us/app/widgetsmith/id1523682319)
- [Widgetsmith - Sensor Tower Overview](https://app.sensortower.com/overview/1523682319?country=us)
- [20 Best iPhone Widgets in 2026 - refurb.me](https://www.refurb.me/blog/best-widgets-for-iphone)
- [NoBuy - No Spend Challenge - App Store](https://apps.apple.com/sk/app/nobuy-no-spend-challenge/id6760857076)
- [Stop Impulse Buying | Budget - App Store](https://apps.apple.com/us/app/stop-impulse-buying-budget/id6475173011)
- [mallow - no buy tracker - App Store](https://apps.apple.com/is/app/mallow-no-buy-tracker/id6738301938)
- [NoSpend - Save Money Challenge App - App Store](https://apps.apple.com/us/app/nospend-save-money-challenge/id6760283408)
- [I Am Sober - App Store](https://apps.apple.com/us/app/i-am-sober/id672904239)
- [I Am Sober App Review 2026 - Choosing Therapy](https://www.choosingtherapy.com/i-am-sober-app-review/)
- [Day One: Daily Journal & Diary - Sensor Tower Overview](https://app.sensortower.com/overview/1044867788?country=US)
- [Is the Apple Journal App Safe? An App Review for Parents - Bark](https://www.bark.us/app-reviews/apps/journal-app-review/)
- [Journey - Diary, Journal - App Store](https://apps.apple.com/us/app/journey-diary-journal/id1300202543)
