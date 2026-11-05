# 歌词来源与覆盖

2026-11-03 的公开文档调研及少量固定曲目验证；2026-11-04 补充并行加载、缓存复用及 lrcmux 接入。重点是能让桌面歌词同步的时间轴，而非搜索结果数量。以下“免费”指查询无需付费或 API key，不代表获得歌词内容的重新分发授权。安装包不捆绑第三方歌词。

## 候选来源

2026-11-05 本地修复：LRCLIB 的精确结果只有纯文本时继续搜索；网易、QQ、酷狗也继续更宽的查询，每轮最多尝试四个尚未查询的候选。时间轴优先于纯文本，来源并发数及单源超时保持原有限制。

匹配忽略 Remaster、Album Version 等发行标注，专辑仅参与排序；同一歌手及主唱身份仍需匹配，Live、Remix、Acoustic、Radio Edit 等录音版本仍区分。曲长容差为 2%，最少 3 秒、最多 6 秒。缓存跨播放器复用时沿用这些规则，支持合辑及不同专辑名称，保留原始到期时间。

| 来源 | 内容与接入 | 本次结论 |
| --- | --- | --- |
| [LRCLIB](https://lrclib.net/docs) | 社区歌词库，提供普通及同步歌词，公开 API | 已接入；与 QQ 一起优先并行查询，不能保证每首独立音乐都有记录 |
| 网易、QQ Music、[酷狗](https://www.kugou.com) | 不同服务的歌曲及同步歌词目录；社区项目采用直接端点，无需本 app 使用账号 | 网易、QQ 已有回退；v0.2.1 新增酷狗。社区接入例可见 [LyricsKit](https://github.com/ddddxxx/LyricsKit)，本 app 独立实现适配，端点可用性无官方承诺 |
| [Unison](https://lyrics-api-docs.boidu.dev/unison) | 独立社区同步歌词库，支持 LRC、TTML、普通文本；公开读取无需 key、无需登录 | 三首样本按输入标题、英文歌手和曲长查询均返回 404；可作为后续增量候选，尚未接入 |
| [Karalyr](https://www.karalyr.com/docs) | 社区逐字同步库，提供 LRCLIB 兼容 API；文档声明免费、无 key、非商业 | 三首样本请求均返回 403，当前环境无法验证覆盖，尚未接入 |
| [lrcmux](https://lrcmux.dev/) | 免费无 key 的聚合 API，整合酷狗、YouTube Music、Deezer 等上游；提供 [公开接口定义](https://api.lrcmux.dev/openapi.json) | v0.5.0 本地版本已接入；使用 `/get?level=line&strict=true` 保留实际曲目和上游来源，将毫秒时间轴转为 LRC，并沿用录音校验。不是新的独立歌词库 |
| [lyrics.ovh](https://github.com/NTag/lyrics.ovh/blob/main/apiary.apib) | 免费公开查询，响应提供普通歌词文本 | 缺少同步时间轴，不能直接补足双行实时歌词，尚未接入 |

网易、QQ、酷狗可能因地区、访问限制、流量或服务调整而不可用。应用仅尝试公开匿名接口，遵守限流，不读取登录 Cookie，不处理验证码。聚合服务也依赖上游，服务数量不等于独立歌词数量。

## 《愛情的大壞蛋》为什么没有歌词

- Spotify 艺名为 `Amazing Show`，QQ 目录艺名为 `美秀集团`
- QQ 返回同名曲目、`美秀集团同名专辑`、187 秒，包含 38 条可解析的时间戳行
- 旧版只认识少量艺名对照，未包含这一组；歌手身份校验把正确结果排除了
- 同一旧版诊断程序改用中文艺名即可成功，验证了这是匹配问题
- 艺人的 [官方 MV 标题](https://www.youtube.com/watch?v=mRma6NkHwWU) 同时使用“美秀集團 Amazing Show”，据此补充明确对照，保留版本及 ±2 秒曲长校验

未识别的艺名仍可能漏匹配。优先采用来源提供的别名及有依据的艺名对照，不因为标题相同就接收翻唱、片段或 Remix。

## 固定样本验证

| 输入 | 来源 | 结果 |
| --- | --- | --- |
| 愛情的大壞蛋 / Amazing Show / 187 秒 | QQ | 修复前无匹配，补充艺名后命中中文艺名对应记录，38 条时间戳行 |
| 愛情的大壞蛋 / Amazing Show / 187 秒 | 酷狗 | 原生 app 命中美秀集团、187 秒、38 条时间戳行 |
| 一夜一夜一夜 / Crowd Lu / 247 秒 | 酷狗 | 原生 app 命中卢广仲、247 秒、53 条时间戳行 |
| Galaxies / Laura Veirs / 216 秒 | QQ | 已通过原生 app 验证同步歌词；酷狗本次未返回候选 |

上述结果只说明固定曲目在验证时的情况，不代表总体覆盖率。时间戳行数也不等于歌词质量评分。酷狗查询保留服务兼容的参数顺序及表单编码；验证会检查原生 URLSession 的实际结果，而不只依据其他工具的响应。

新增同步歌词沿用现有本地缓存及有限重试。缓存仅保存在用户设备，不发布到仓库或其他歌词库。

## v0.5.2 加载、缓存与匹配

- 默认按 LRCLIB、QQ、lrcmux、酷狗、网易的次序调度，每首最多同时运行两个来源，首份合格同步歌词返回后取消剩余请求
- 每个来源的搜索、下载和重试共用 4 秒预算；暂时故障退避 20 秒，HTTP 限流遵守服务端 Retry-After
- 缓存按录音元数据和曲长查找，可跨 Spotify / Apple Music 复用；保留歌手、专辑、版本和 ±2 秒曲长校验，兼容旧格式及其原始到期时间
- 来源只返回普通文本时继续查找同步歌词；不能把服务错误或无时间轴等同于曲库不存在
- 来源优先返回真实曲目信息；lrcmux 保留实际上游名称，不用请求参数伪造匹配元数据
- 离线回归覆盖并发上限、慢源取消、超时、切歌取消、退避、跨播放器缓存、旧缓存、聚合源和错误录音拒绝

## 本土艺名与查询用名

补充以下有第一方依据的艺名对应，支持繁简变化与合作歌手集合。匹配仍要求同一录音，不能仅凭标题相同接受翻唱、Live 或其他版本。

- `Shallow Levée / 淺堤`：[官方网站](https://shallowlevee.com/) 与 [StreetVoice](https://streetvoice.com/shallowlevee/)
- `I'mdifficult / 我是機車少女`：[官方 Linktree](https://linktr.ee/imdifficult) 与 [发行方](https://www.bigromanticrecords.com/single-post/imdifficult)
- `puppiebelly / burger.cue / 汉堡黄`：[Apple Music《BURGER POP》艺人采访](https://music.apple.com/us/album/burger-pop/1722758517)
- `Whys Young / Yoon Jiyoung / 윤지영`：[官方 Linktree](https://linktr.ee/WhysYoung)；中文目录别名依具体录音的合作歌手、专辑、曲长与发行方记录交叉核对，不用模型直接推测音译

本土服务的免费范围、同步格式与接入限制见 [台湾、日本本土歌词服务调研](regional-lyrics-services-2026-11-04.md)。免费网页或消费者 App 不自动等于可供第三方调用的同步 API。

个人歌单、原始本地测试记录及缓存不随源码或安装包发布。历史少量固定样本只代表当时结果，不代表当前整个曲库的覆盖率。
