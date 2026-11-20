# 序章 BGM 需求与 Suno 提示词（A+B+C，共 35 首）

用途：在 Suno 里生成《英雄传Ⅱ》序章全部配乐。纯器乐、中国传统乐器为主。生成不限次数，**只有下载计次**（Pro 每月 20 次），所以分两个月批次，先挑好再下载。

## 当前只做这 9 首（马匪块，用户 2026-11-20 定）
标题、紫霞镇、酒馆、酒馆伏击、紫霞林、普通战斗、马匪头子 Boss、胜利、失败，即下面 T01、T02、T03、T04、T05、T06、T07、T14、T15。其余曲目（紫霞派、三火、山庄等）先不做，等对应剧情做出来再生成。

## 通用规则

**每条 Style 提示词前面都加这段前缀：**
`instrumental, no vocals, cinematic Chinese wuxia game soundtrack, HD-2D RPG, traditional Chinese instruments with light orchestra,`

**Exclude Styles（排除）栏统一填：**
`vocals, singing, lyrics, choir, rap, EDM drop, electric guitar solo`
（循环曲再加：`fade-out ending`）

**Lyrics 栏**：填 `[Instrumental]`，或直接打开 Instrumental 开关。

**要点**
- 循环曲目标 90 到 150 秒，保持稳定速度、不要大高潮收尾，我的工具会做无缝循环。
- 一次性曲（jingle、过场）按“目标时长”生成，过长的我可以裁。
- 同一首多生成 3 到 5 版再挑，选“旋律最好记”的，不要选“最华丽”的。
- 下载格式选 WAV（没有就 MP3）。
- 文件导入：`py -3 godot/tools/process_music.py <下载文件> <导入名> --loop`（一次性曲用 `--once`），把文件放进 Downloads 告诉我即可。

## 主题动机（leitmotif）：让音乐讲故事

| 动机 | 感觉 | 出现的曲子 |
|---|---|---|
| **紫殇主题 Z** | 明亮五声音阶、四小节的好记旋律，热血诙谐 | T08 原版 → T09 闪光 → T10 夜晚变慢 → T26 压抑小调 → T30 扭曲圆舞曲 → T32 破碎低沉 → T34 纯净告别 |
| **任逍遥主题** | 轻快流动的笛子加古琴，少年逍遥 | T01 标题、T20、T35 |
| **东方阳主题 D**（全文通用） | 帝王、高涨、辉煌的庄严旋律；**每次提到东方阳时都用这条旋律的不同强度版本** | 马匪头子战（收敛版，不外露霸气）→ 以后各处传说 → 揭露真身（完整版，霸气侧漏天下） |
| **三火** | 低沉不协和 | T16、T17、T18 |
| **东方凯** | 冷峻精准、军乐鼓点 | T24 |

做法：先生成 T08，选出最喜欢的一版；之后 Z 的其他版本用 Suno 的 **Extend / Cover**（可以用你自己生成的这首作为输入）保持旋律，改风格得到变奏。Suno 不保证旋律一致，生成几版挑最接近的。

## 批次一（第一个月，T01 到 T19，共 19 首）：标题、紫霞镇、马匪块、紫霞派、三火

| # | 导入名 | 场景 | 循环 | 目标时长 |
|---|---|---|---|---|
| T01 | title | 标题 | 是 | 120 s |
| T02 | victory_jingle | 胜利 | 否 | 10 s |
| T03 | defeat_jingle | 失败 | 否 | 10 s |
| T04 | town | 紫霞镇 | 是 | 120 s |
| T05 | tavern | 酒馆内景 | 是 | 120 s |
| T06 | tavern_brawl | 酒馆伏击 | 是 | 90 s |
| T07 | forest | 紫霞林 | 是 | 120 s |
| T08 | zixia_daily | 紫霞派日常（紫殇主题） | 是 | 120 s |
| T09 | zixia_theme_sting | 紫殇闪光 | 否 | 12 s |
| T10 | zixia_night | 紫霞派夜晚 | 是 | 120 s |
| T11 | birthday | 紫霞生日、家人温情 | 是 | 100 s |
| T12 | searching | 寻找紫霞 | 是 | 90 s |
| T13 | tiger_king | 猛虎王遭遇与紫殇赶到 | 否 | 120 s |
| T14 | battle_normal | 普通战斗 | 是 | 100 s |
| T15 | battle_boss | 马匪头子 Boss | 是 | 110 s |
| T16 | sanhuo_arrival | 三火上门 | 是 | 90 s |
| T17 | tragedy | 灭门 | 否 | 90 s |
| T18 | sanhuo_duel | 三火战 | 是 | 100 s |
| T19 | cliff_fall | 坠崖与悲痛 | 否 | 90 s |

### 提示词（前缀已省略，使用时在最前面加上通用前缀）

**T01 title**（标题）
`slow majestic opening, guzheng arpeggios, solo erhu melody, bamboo flute answering, soft string pad, nostalgic and hopeful with a trace of sorrow, carefree young wanderer feeling, 80 BPM, D minor lifting to D major, no drums until the middle, builds gently`

**T02 victory_jingle**（胜利，10 秒）
`short victory fanfare, bright guzheng glissando, dizi flute flourish, small taiko hit, cheerful and proud, 10 seconds, clean ending, no loop`

**T03 defeat_jingle**（失败，10 秒）
`short sorrowful defeat sting, single erhu sigh, low gong, soft guqin notes fading, 10 seconds, no loop`

**T04 town**（紫霞镇）
`relaxed peaceful mountain village morning, pipa plucking, light dizi flute, gentle erhu, small wooden percussion, warm and nostalgic, slow stroll feel, 96 BPM, G major, steady groove, no big climax, loopable`

**T05 tavern**（酒馆内景）
`cozy lively tavern, erhu and pipa duet, hand drums, wood blocks, folk dance feel, slightly tipsy swing, friendly and warm, 112 BPM, A major, loopable`

**T06 tavern_brawl**（酒馆伏击）
`sudden tense ambush in a tavern, low taiko pulses, plucked pipa tremolo, suspenseful strings, rising tension, menacing yet slightly comedic bandits, 140 BPM, E minor, loopable`

**T07 forest**（紫霞林，轻松版；旧的 A 小调版本偏悲伤，已弃用）
`light-hearted bamboo forest exploration, bright dizi flute melody, playful pizzicato strings, plucked pipa, gentle guzheng ripples, soft wooden percussion, birdsong feel, sunny and curious adventurous stroll, relaxed and cheerful, 100 BPM, G major, steady easy groove, no sad melody, no minor key, loopable`

Suno 的 Exclude styles 填：`sad, melancholic, minor key, funeral, dramatic, heavy drums, dark, tense, slow ballad`

小贴士：如果生成出来仍偏忧伤，把 `G major` 换成 `D major`，把 `100 BPM` 提到 `108 BPM`，并在歌词框里写 `[Instrumental]`。

**T08 zixia_daily**（紫殇主题 Z，原版）
`bright playful heroic comedy theme, dizi flute lead melody, pizzicato strings, light marimba, bouncy hand percussion, cheerful hot-blooded mentor energy, a catchy memorable 4-bar pentatonic hook repeated and varied, 126 BPM, D major, loopable`

**T09 zixia_theme_sting**（闪光，12 秒）
`short heroic comedic fanfare, sparkling chime shimmer, suona and dizi, triumphant hit, big shiny ending like a smiling flash, 12 seconds, cheerful, no loop`

**T10 zixia_night**（紫霞派夜晚）
`peaceful night in a sect courtyard, gentle guqin, soft dizi, slow warm strings, cricket ambience, tender and nostalgic, calm before the storm, 64 BPM, F major, loopable`

**T11 birthday**（生日、家人温情）
`tender family warmth, music-box-like pipa plucks, warm erhu, soft flute, gentle waltz feel in 3/4, heartfelt and slightly funny, smiling through tears, 90 BPM, C major, loopable`

**T12 searching**（寻找紫霞）
`wistful urgent search at dusk, rhythmic guzheng ostinato, anxious dizi motif, soft taiko heartbeat, rising worry, 100 BPM, B minor, loopable`

**T13 tiger_king**（猛虎王遭遇，一首 2 分钟的叙事曲）
`dangerous encounter in a wasteland, low drums and growling bass, tense erhu, scrambling pipa, then a heroic turning point with big taiko and rising strings, relief and triumph, 132 BPM, D minor lifting to D major, one 2 minute piece with a clean ending, no loop`

**T14 battle_normal**（普通战斗）
`driving Chinese martial arts battle, fast taiko, guzheng runs, ostinato strings, sharp dizi stabs, tight rhythm, energetic, 150 BPM, E minor, no break, loopable`

**T15 battle_boss**（马匪头子战：**他其实是东方阳，所以这首是"东方阳主题"的收敛版**）

做法：先在 Suno 里生成**完整版东方阳主题作为旋律种子**（只在 Suno 里挑选，不需要下载），选定最好的一版后，用 Cover / Extend 得到下面这首收敛版，只下载收敛版。完整版以后揭露真身时再下载。

*种子：完整版东方阳主题（先不下载）*
`majestic imperial anthem, radiant and triumphant, full orchestra with horns and trumpets, grand taiko, bronze bells, sweeping guzheng, soaring erhu melody, noble and overwhelming, the feeling of an emperor commanding the world, slow powerful march, big dynamic builds, 100 BPM, D major, loopable`

*T15：收敛版（下载这首）*
`restrained regal theme hidden beneath a rowdy bandit battle, rough taiko and wood percussion, raspy erhu, muted horns quietly stating a noble melody then retreating, dignity under a disguise, controlled power never fully unleashed, tense yet slightly playful, 124 BPM, D major with minor color, loopable`

**T16 sanhuo_arrival**（三火上门）
`oppressive menacing arrival of a powerful old master, low drones, slow heavy taiko hits, dissonant strings, scraping erhu, ominous guqin, tension without resolution, 70 BPM, C# minor, loopable`

**T17 tragedy**（灭门）
`tragic chaotic slaughter, frantic dissonant strings, pounding taiko, screaming erhu, crashing gongs, despair, no heroic feeling, builds relentlessly, ends abruptly, 160 BPM, A minor, no loop`

**T18 sanhuo_duel**（三火战）
`desperate duel against an overwhelming enemy, heavy taiko, pulsing low strings, dissonant sustained tones, sudden silences, a small defiant flute motif, 118 BPM, F# minor, loopable`

**T19 cliff_fall**（坠崖与悲痛）
`tragic aftermath, solo guqin and erhu lament, sparse plucks, long reverb, grief and shock, very slow, 50 BPM, A minor, ends fading, no loop`

## 批次二（第二个月，T20 到 T35，共 16 首）：五年后、英雄大会、御剑山庄、紫殇之死

| # | 导入名 | 场景 | 循环 | 目标时长 |
|---|---|---|---|---|
| T20 | years_pass | 养伤五年 | 是 | 120 s |
| T21 | escort_road | 镖局押镖 | 是 | 120 s |
| T22 | licangtian_theme | 厉苍天遭遇战 | 是 | 100 s |
| T23 | hero_tournament | 少年英雄大会 | 是 | 110 s |
| T24 | dongfang_kai_duel | 东方凯擂台 | 是 | 100 s |
| T25 | yujian_oppressive | 御剑山庄日常 | 是 | 120 s |
| T26 | ziyang_night_talk | 紫殇夜谈 | 是 | 120 s |
| T27 | rage | 愤怒 | 是 | 90 s |
| T28 | prison | 家法堂囚禁 | 是 | 90 s |
| T29 | centennial_banquet | 百年庄庆 | 是 | 110 s |
| T30 | ziyang_corrupt | 紫殇黑化登场 | 是 | 110 s |
| T31 | ziyang_boss_phase1 | 紫殇战一阶段 | 是 | 110 s |
| T32 | ziyang_boss_phase2 | 紫殇战二阶段（怪物） | 是 | 110 s |
| T33 | forge_mountain | 铸剑后山 | 是 | 100 s |
| T34 | ziyang_death | 紫殇之死 | 否 | 90 s |
| T35 | prologue_end | 序章终章 | 否 | 80 s |

**T20 years_pass**
`solitary years of recovery in the mountains, slow guqin, flowing dizi flute, soft wind, hope growing gradually, time passing montage, 72 BPM, D major, loopable`

**T21 escort_road**
`adventurous journey on dusty roads, steady walking rhythm on hand drums, pipa and dizi, optimistic, wide open landscape, 108 BPM, G major, loopable`

**T22 licangtian_theme**
`rugged powerful bandit warrior, heavy drums, low horn-like drones, rough erhu, stomping rhythm, brute strength with a hint of honor, 128 BPM, D minor, loopable`

**T23 hero_tournament**
`grand festive martial arts tournament, bright suona, fast taiko, lively gongs, crowd energy, fanfare feel, 138 BPM, D major, loopable`

**T24 dongfang_kai_duel**
`elegant cold swordsman duel, sharp guzheng, precise plucked strings, military snare rhythm, noble and unbeatable, 144 BPM, B minor, loopable`

**T25 yujian_oppressive**
`oppressive feudal mansion, very slow, cold guqin notes, long low drones, sparse pipa, aristocratic stiffness, suffocating silence between notes, 58 BPM, F minor, loopable`

**T26 ziyang_night_talk**（紫殇主题 Z 的压抑小调版，建议用 T08 做 Extend/Cover）
`bittersweet night conversation, the cheerful hero theme slowed down in minor, solo dizi and guqin, warm but heavy, hopeful words under sorrow, 66 BPM, D minor, loopable`

**T27 rage**
`rising fury, pounding taiko, aggressive erhu, tense strings, controlled anger about to explode, 148 BPM, E minor, loopable, ends hard`

**T28 prison**
`bleak prison cell, a single sustained low erhu line, dripping reverb, cold wind, hopeless stillness, 48 BPM, C minor, loopable`

**T29 centennial_banquet**
`festive grand banquet that feels hollow, bright suona and gongs, polite court music, an unsettling off-key undertone, slow-building unease, 100 BPM, G major sliding to G minor, loopable`

**T30 ziyang_corrupt**（紫殇主题 Z 扭曲圆舞曲，建议用 T08 做 Cover）
`seductive dark waltz, a twisted version of a cheerful hero theme, sliding erhu glissandos, detuned pipa, eerie violet atmosphere, ghostly shimmer, drunken elegance, 3/4 waltz, 96 BPM, D minor, loopable`

**T31 ziyang_boss_phase1**
`tragic villain boss battle, extremely fast guzheng and strings, dizi melody twisted into minor, crashing taiko, wild and sorrowful, 168 BPM, D minor, loopable`

**T32 ziyang_boss_phase2**
`monstrous transformed boss, slow crushing taiko, distorted erhu wail, low sustained string drone, broken fragments of a hero theme in the bass, heartbeat pulse, 90 BPM, D minor, loopable`

**T33 forge_mountain**
`ticking tension in a molten forge, hammer on anvil rhythm, bubbling fire ambience, urgent strings, race against time, 124 BPM, A minor, loopable`

**T34 ziyang_death**（紫殇主题 Z 的纯净告别）
`tender farewell, the cheerful hero theme returns pure and gentle on solo dizi and guqin, tears and smiles, slow, ends softly, 70 BPM, D major, no loop`

**T35 prologue_end**
`resolute new beginning after loss, solo guqin then a full arrangement with determination, dawn feeling, 84 BPM, D major, ends warmly, no loop`

## 优先级与取舍
- **如果额度紧**：批次一里先下 T01、T04、T05、T06、T07、T08、T09、T14、T15、T02、T03（11 首，马匪块和紫霞镇就够用了），再补 T16 到 T19。
- 批次二可以等你把山庄篇的地图摆出来再生成，到时候可能要调整。
- 选曲标准：**旋律好记、情绪对**，比“制作多华丽”更重要；紫殇主题（T08）值得多花时间挑，它后面要变奏六次。
