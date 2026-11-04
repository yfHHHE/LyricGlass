# 台湾、日本本土歌词服务调研

调研日期：2026-11-04，Asia/Singapore。目标是给 LyricGlass 增加**可读取、可匹配到同一录音的同步时间轴**，不是增加能看到歌词文字的网站数。本次只读官方文档、服务第一方页面、官方源码及论文；不登录、不申请账号、不使用凭据，不上传音频或歌词，不保存歌词正文。

## 结论

**本次范围内，没有找到可以直接作为 LyricGlass 通用回退源接入的、本土官方免费匿名同步歌词读取 API。** 这不是断言台湾或日本不存在这种服务，也不是断言这些曲库没有同步歌词。

- **台湾最值得保留的线索是 StreetVoice**：官方明确支持创作者提交 LRC，浏览器和 App 均能按时间戳滚动。它有真实的原始同步数据，但本次未找到对第三方开放的读取契约或复用授权，也未在下面的目标歌曲检查中取得可新增覆盖的 LRC。[StreetVoice 动态歌词说明](https://guide.streetvoice.com/tip-lrclyric/)、[服务条款](https://streetvoice.com/legal/terms/)
- **日本最接近“免费、有真实时间轴、官方开发入口”的是 AIST 的 TextAlive App API**：提供 phrase、word、char 的毫秒起止时间；需要开发者注册取得 app token，只能使用具备相应权利或许可的内容，商用需事先咨询。它适合限定曲目的研究或专门体验，不能据此承诺任意 Spotify 曲目覆盖。[API 入口](https://developer.textalive.jp/)、[歌词对象与时间字段](https://developer.textalive.jp/app/song/)、[开发者规则](https://developer.textalive.jp/terms/)
- **PetitLyrics / SyncPower 有真正的日本同步歌词数据库与对外 API 业务**，但官网免费播放器与商业数据接口是两件事。本次没有查到可自助获取的免费读取 key、公开读取规范或免费配额；价格、macOS 使用范围和 Spotify 外部播放配合均待对方确认。[SyncPower 官网](https://syncpower.jp/ja)、[PetitLyrics 免费 App 说明](https://petitlyrics.com/contents/app_list)、[歌词使用 FAQ](https://petitlyrics.com/contents/help.html)

研究子任务中，本土新服务**可新增同步覆盖的已验证数为 0**，未改动适配器或匹配规则。主任务随后完成艺名修复：原歌单 43/50 → 47/50，日本 8 首样本每版两轮均 16/16；这些结果来自现有来源，不能算作本土新 API 的新增覆盖。完整取证及测速见[主任务报告](lyrics-sources.md)。

## 免费阅览、读取接口和时间轴要分开看

“未找到”均指本次已核对的公开材料，不表示服务内部没有接口。收费未公开时写“待确认”，不把商务咨询自动等同于收费，也不把免费网页等同于可复制的歌词 API。

| 服务 | 免费阅览 / 消费端 | 对外读取入口 | 原始同步时间轴 | key、申请、收费与范围 | 对 LyricGlass 的判断 |
| --- | --- | --- | --- | --- | --- |
| **KKBOX（台湾）** | 官方年报证实产品内动态歌词；本轮未单独确证当前匿名免费阅览范围 | 官方 Open API / SDK 需要 client ID、secret、access token，已查文档主打歌曲、艺人、专辑、歌单等元数据 | 2023 年报明确是歌词文字＋时间戳；但已查官方 `KKTrackInfo` 和 `TrackFetcher` 没有歌词或时间轴字段 | SDK 文档较旧；开发者入口本轮未完整读到，当前注册、价格、伙伴歌词接口均未确认 | **可作元数据证据；不是已证实的同步读取源**。[官方 SDK](https://kkbox.github.io/OpenAPI-Swift/)、[TrackInfo 字段](https://kkbox.github.io/OpenAPI-Swift/Structs/KKTrackInfo.html)、[TrackFetcher](https://kkbox.github.io/OpenAPI-JavaScript/class/src/api/TrackFetcher.js~TrackFetcher.html)、[2023 年报 PDF 第 99 页](https://ir.kkcompany.com/files/uploads/%E5%85%AC%E9%96%8B%E8%AA%AA%E6%98%8E%E6%9B%B8/2023%20Annual%20Report%2020240607_Final.pdf#page=99) |
| **StreetVoice 街声（台湾）** | 本次公开艺人目录及两首歌曲页均匿名 HTTP 200；官方说明浏览器、App 支持 LRC | 未找到公开、稳定、供第三方复用的歌词读取 API 文档 | **有**：创作者填写 LRC；本次实际检查的两首页初始 HTML 未包含 LRC 时间戳，不能据此判断动态请求中也没有 | 发表作品需创作者账户；普通阅览已匿名验证；条款第 13、15 节限制未经许可的内容复用，未提供免费第三方数据许可 | **研究候选；先取得公开契约和使用范围，再考虑适配**。[LRC 说明](https://guide.streetvoice.com/tip-lrclyric/)、[歌曲信息说明](https://guide.streetvoice.com/tip-songinfo/)、[条款](https://streetvoice.com/legal/terms/) |
| **Omusic 全音乐（台湾）** | 当前官网是公司与合作介绍，本轮未发现可供匿名阅览的 Omusic 歌词目录 | 官网只给合作洽询入口，未发现公开歌词 API 文档 | 未确认 | 官网页面说明目前合作品牌为台湾 LINE MUSIC；技术、内容合作须咨询，读取价格未公布 | **只能研究 / 洽询，不能因旧品牌知名度直接列为可接入源**。[当前官网](https://www.omusic.com.tw/) |
| **LINE MUSIC 台湾（补充本土服务）** | 公开单曲页具有曲目、艺人、专辑及歌词栏目 | 本轮未找到公开同步歌词读取 API 契约 | 公开网页的文字栏目不证明有可读取时间轴，本轮未取得 | 与 Omusic 合作关系有官方公司页佐证；免费网页不等于外部 App 使用许可 | **曲目、艺名及版本证据；不计同步新增源**。例如[淺堤的歌曲页](https://music-tw.line.me/track/5718540001)、[Omusic 公司说明](https://www.omusic.com.tw/) |
| **PetitLyrics / SyncPower（日本）** | 官方手机播放器标注 Free，支持跟随本地音乐显示同步歌词；网站可搜索社区投稿并区分 Text、Line Sync、Word Sync | 官方公司明确有同步歌词与 API 业务；未找到免费匿名读取规范 | **有**：逐行及逐字同步；这是供应能力证据，非 LyricGlass 已取得读取许可 | 公开消费端免费；业务 API 的 key、申请流程、费用、外部播放器与桌面端权限待确认；FAQ 说明流式显示，不允许下载或复制歌词数据 | **有价值的合作候选；不将第三方抓站器视为官方 API**。[公司业务](https://syncpower.jp/ja)、[社区类型](https://petitlyrics.com/)、[App 说明](https://petitlyrics.com/contents/app_list)、[FAQ](https://petitlyrics.com/contents/help.html) |
| **歌ネット Uta-Net（日本）** | 官方明确为免费歌词搜索、显示服务 | 本轮未找到官方开放读取 API；`api.uta-net.com` 的存在本身不等于开发者接口 | 官方内容说明是歌词卡片搜索、显示；未找到对外 LRC / 时间轴契约 | 官网明确歌词不能下载；条款明确禁止未经许可的复制、传输及 scraping | **可人工核对曲名、作词、艺人或跳转原页；不做抓取回退**。[服务说明](https://www.uta-net.com/info/contents_info.html)、[条款](https://www.uta-net.com/info/kiyaku.html) |
| **UtaTen（日本）** | 官方标注免费歌词搜索；支持假名、罗马字显示及同时看 MV | 本轮未找到官方歌词读取 API 文档 | 注音、罗马字、视频一起显示均不等于逐行时间轴；未找到对外时间字段契约 | 条款只准个人、非营利阅览，印刷、复制、转载、改动等需事前书面许可 | **语言和曲目参考；不是已证实的同步源**。[官方功能说明](https://utaten.com/specialArticle/index/3018)、[条款](https://utaten.com/index/agreement) |
| **JOYSOUND（日本）** | 公共曲库可搜索；独立的 JOYSOUND[歌詞] 官方介绍页仍写月额会员阅览，不能概括为全部免费 | **JSL SDK / 数据许可是官方接入路径**，不是免费开放歌词 API | **有**：JSL 支持配套卡拉 OK 音源的歌词字幕；原始格式、是否可单独用于 Spotify 录音未公开证实 | 官方写许可费用随提供曲数变化，也可仅许可数据；公开支持表列 Android、iOS、iPadOS、Windows，未列 macOS | **商务候选；免费通用桌面回退不合适**。[JSL 官方说明](https://camp.joysound.com/renkei_lp/dev/jsl/)、[歌词阅览介绍](https://www.joysound.com/web/s/mobile/js_kashi) |
| **Songle / Songle Sync（日本，AIST）** | API 条款说明符合规定的非商用使用免费 | 有官方 API，但不能把音乐同步控制 API 当歌词 API | Songle Sync / Widget 的节拍等事件 **不提供歌词相关信息**；歌词时间轴要转看 TextAlive | 按官方指定方式使用及标示来源；商用需书面许可；无权重分发服务数据 | **音乐分析研究；单独接入不能补歌词**。[官方 API 条款](https://api.songle.jp/terms_of_use)、[开发者本人论文第 276 页](https://staff.aist.go.jp/m.goto/PAPER/TIPSJ202502kato.pdf#page=4) |
| **TextAlive App API（日本，AIST）** | 是开发库，重点是已登记歌曲的歌词驱动 Web App | **有官方文档和 JS 库**；需开发者注册获取 app token | **有**：`firstPhrase`、`firstWord`、`firstChar` 的 `startTime` / `endTime` 为毫秒；可固定歌词修订版本 | 依约免费；仅使用具备权利或许可的内容，显示使用条款、遵守署名条件；商用先咨询；本次未注册或调用需 token 接口 | **最适合限定曲目的免费研究；不能直接替换通用 title/artist/duration 歌词源**。[入口与 token](https://developer.textalive.jp/)、[时间字段](https://developer.textalive.jp/app/song/)、[条款](https://developer.textalive.jp/terms/) |
| **全て歌詞の所為です。（日本社区）** | 站点说明任何人可搜索、登记、编辑，专注特定“界隈曲”社群 | 维护者官方仓库记录 REST Song API，读取支持匿名；本次空结果查询 HTTP 200 | 文档描述曲名、作者、歌词、URL、别名等；**未找到同步时间轴字段规范** | 读取无需本次请求提供 key；2 请求/秒；写入需管理员 key；代码 MIT 不等于歌词内容已授权 | **窄领域元数据 / 艺名来源研究；不能计入同步覆盖**。[站点说明](https://lyrics.imicomweb.com/)、[官方源码及 API README](https://github.com/izumin2000/subekashi) |

## StreetVoice 的限定验证

官方支持 LRC 是已证实事实，但“服务有这种功能”“某首录音上传了 LRC”“第三方能合法稳定读取”是三个不同结论。本轮没有把页面的“动态歌词”按钮、普通文本或 HTTP 200 当同步命中。[功能说明](https://guide.streetvoice.com/tip-lrclyric/)

主任务提供了 7 首目前待补的歌曲。本次优先检查其中的艺人公开目录和目标词，不做全站穷举：

| 目标录音 | 本次检查范围 | 结果及边界 |
| --- | --- | --- |
| `skin / Andr / SKIN / 148.156s`；`night night / Andr & Whys Young / SKIN / 239.099s` | [Andr 官方艺人目录](https://streetvoice.com/runnytummy/songs/)，第 1、2 页均 HTTP 200；加站内 `skin Andr`、`night night` 查询 | 这两页公开作品未见两首目标；搜索返回 Night Lotion、其他歌手的 Skin 等，不接收为候选。没有相符记录，故无可报告的目标实际曲长、时间戳数或范围 |
| `夜晚的牠知道 / Shallow Levée / 310.680s` | [淺堤官方目录](https://streetvoice.com/shallowlevee/songs/)，第 1、2 页均 HTTP 200；站内目标标题查询 | 未取得目标录音；不能用站外韩文合作版或同名作品代替。没有目标记录可核曲长和时间轴 |
| `小孩 / I'mdifficult / 252.755s` | [我是機車少女官方目录](https://streetvoice.com/imdifficult/songs/)，第 1–4 页均 HTTP 200；站内标题＋艺人查询 | 公开目录未见此标题；搜到其他该艺人的作品不算命中。没有目标记录可核曲长和时间轴 |
| `快一點，慢一點 / puppiebelly / 219.782s`；`沒有如果 / ECHORA & Andr / 152.242s` | 站内标题 / 标题＋艺人查询 | 返回其他作品；没有接收到身份与版本相符的目标。此检查范围有限，不推导“全站不存在” |
| `一起 / puppiebelly / 199.271s` | 未进一步检查 | 随主任务收敛范围，保留为未验证，不能报告失败或无歌词 |

另用两首已知 Andr 作品检查匿名页面的初始 HTML：

| 页面 | HTTP | 初始 HTML 的 `[mm:ss.xx]` 时间戳数量 | 能否据此声称无同步 |
| --- | ---: | ---: | --- |
| [現在的事我說不出口，754626](https://streetvoice.com/runnytummy/songs/754626/) | 200 | 0 | 不能；只证明初始 HTML 未见 LRC |
| [Night Lotion「融」，718098](https://streetvoice.com/runnytummy/songs/718098/) | 200 | 0 | 不能；动态播放器可能另行读取 |

这两项只是页面结构对照，**未取得可核验的原始时间轴、时间范围或来源字段**，不计为正向同步样本。本轮查看了页面引用的公开播放器脚本，没有找到可交付的歌词读取契约；没有使用登录 Cookie、挑战绕过或受限端点。条款中的内容复用限制也使它尚不适合直接成为发布版第三方歌词提供者。[StreetVoice 条款第 13–15 节](https://streetvoice.com/legal/terms/)

## 可直接供匹配规则使用的艺名证据

这些是曲目身份线索，不是新歌词服务。映射仍需配合完整合作者集合、专辑、版本及曲长校验。

| 英文 / 平台艺名 | 本土艺名 | 第一方证据 |
| --- | --- | --- |
| `Shallow Levée` | `淺堤` | 艺人自己的 [StreetVoice 主页](https://streetvoice.com/shallowlevee/) 直接使用“淺堤 Shallow Levée” |
| `I'mdifficult` / `I’mdifficult` | `我是機車少女` | [官方 Linktree](https://linktr.ee/imdifficult) 直接并列，且链接 Spotify、Apple Music、官方影片；[发行方 BIG ROMANTIC RECORDS](https://www.bigromanticrecords.com/single-post/imdifficult) 也并列两种名称 |
| `puppiebelly` | `汉堡黄` / `漢堡黃`，另有 `burger.cue` | [Apple Music《BURGER POP》第一方艺人采访](https://music.apple.com/us/album/burger-pop/1722758517) 当前专辑署名为 puppiebelly，采访介绍说明 burger.cue 与汉堡黄的对应；该页也讨论目标曲《快一点,慢一点》及《一起》所在专辑。繁简形式可用现有规范化处理 |

后台调研阶段未取得直接并列 `Whys Young ↔ 尹志英` 的当前第一方艺人介绍，未采用 JOOX 搜索缓存作为映射依据。主任务随后补做同录音交叉核验：QQ 的 `night night / SKIN / 239s` 目录以尹志英署名，发行方官方歌曲页以 Whys Young 署名；归一化后的正文是相同的 622 字符序列。结合官方 Linktree 的新旧姓名，对应关系作为目录署名推断使用，而非声称艺人自用中文名。见[主任务的证据与边界](lyrics-sources.md)及[无正文交叉核对指标](benchmarks/lyrics-2026-11-04/unmatched-followup/whys-recording-crosscheck.json)。

## 日本固定样本集：8 首

文件：[`benchmarks/lyrics-2026-11-04/regional/japan-samples.json`](benchmarks/lyrics-2026-11-04/regional/japan-samples.json)

采集完成时间：`2026-11-04T02:36:19.834079Z`，即 SGT 10:36:19。只保存元数据，没有存网页原文、会话、音频或歌词。

每首都读取**同一 track ID** 的两个 Spotify 公开页面：

1. 正常单曲页 `https://open.spotify.com/track/{id}` 的公开 `initialState`，提取该 URI 的曲名、完整 `artists`（或 `firstArtist + otherArtists`）及 `albumOfTrack.name`
2. 同一 ID 的 `https://open.spotify.com/embed/track/{id}` 的公开 `__NEXT_DATA__`，提取 `props.pageProps.state.data.entity.duration`，从毫秒除以 1000
3. 校验正常页和嵌入页的 URI、曲名一致；正常页有 `duration.totalMilliseconds` 时也逐首确认与嵌入页完全相等。本次 8 首均成功

这是公开页面元数据提取，不调用 Spotify 私有歌词端点，不取账号令牌。原有仓库的公开页面解析工具被只读复用，未修改脚本。样本中的艺名、曲名保留此次页面实际拼写，未为提高命中人为替换为另一个发行版。

| # | 曲名 | 完整艺人 | 专辑 / 版本 | 秒 | 正常页与时间来源 |
| ---: | --- | --- | --- | ---: | --- |
| 1 | 怪獣の花唄 | Vaundy | strobo | 224.804 | [单曲页](https://open.spotify.com/track/7dTW21YAJxnAOiUh7Rtu9S) · [embed](https://open.spotify.com/embed/track/7dTW21YAJxnAOiUh7Rtu9S) |
| 2 | 新時代 | Ado | ウタの歌 ONE PIECE FILM RED | 226.813 | [单曲页](https://open.spotify.com/track/28MATCYDctW5EiBa2repxb) · [embed](https://open.spotify.com/embed/track/28MATCYDctW5EiBa2repxb) |
| 3 | KICK BACK | Kenshi Yonezu | KICK BACK，完整录音，非 ANIME edit | 193.495 | [单曲页](https://open.spotify.com/track/5PA3UIrEhG16UoQIj1fvlw) · [embed](https://open.spotify.com/embed/track/5PA3UIrEhG16UoQIj1fvlw) |
| 4 | 廻廻奇譚 | Eve | 廻人 | 221.958 | [单曲页](https://open.spotify.com/track/5XodODtKKldKJuu4fuaqdN) · [embed](https://open.spotify.com/embed/track/5XodODtKKldKJuu4fuaqdN) |
| 5 | アイドル | YOASOBI | アイドル，日文单曲 | 213.233 | [单曲页](https://open.spotify.com/track/7ovUcF5uHTBRzUpB6ZOmvt) · [embed](https://open.spotify.com/embed/track/7ovUcF5uHTBRzUpB6ZOmvt) |
| 6 | 紅蓮華 | LiSA | 紅蓮華，完整单曲，非 TV ver. | 235.903 | [单曲页](https://open.spotify.com/track/6emZUSJE4vuBL4DRljScJs) · [embed](https://open.spotify.com/embed/track/6emZUSJE4vuBL4DRljScJs) |
| 7 | ヴァンパイア | DECO*27 | ヴァンパイア，非其他制作者重调教版 | 178.235 | [单曲页](https://open.spotify.com/track/0m9QPTZzjtqCWY9Jg8poHc) · [embed](https://open.spotify.com/embed/track/0m9QPTZzjtqCWY9Jg8poHc) |
| 8 | デビルじゃないもん | DECO*27 & PinocchioP | デビルじゃないもん | 163.682 | [单曲页](https://open.spotify.com/track/294o7PTrqj9VySUIHaJmXw) · [embed](https://open.spotify.com/embed/track/294o7PTrqj9VySUIHaJmXw) |

选曲用于覆盖 J-pop、动漫及 VOCALOID 常见匹配情况，**不是代表日本曲库的随机样本**。该 JSON 尚不包含任何歌词源结果、正确率或延迟结论。

## 取证限制与下一步

- SyncPower 官网在网页阅读工具中超时，但直接匿名 HTTP 读取返回 200，标题及同步歌词 / API 业务均确认；没有取得开发者账号或 API 样本。PetitLyrics 条款页在网页阅读工具中返回 403，因此使用可访问的官方 FAQ；没有尝试绕过 403。[SyncPower](https://syncpower.jp/ja)、[PetitLyrics FAQ](https://petitlyrics.com/contents/help.html)
- KKBOX 开发者根入口本轮未完整读取，现有官方 SDK 文档注明 2019 年更新；本报告不把旧 SDK 缺少某字段解释成“KKBOX 现在绝无此接口”。[官方 SDK 的更新信息](https://kkbox.github.io/OpenAPI-Swift/)
- 社区 API 的唯一运行请求使用确定不存在的元数据查询 `title_exact=lyricglass-no-such-song-2026-11-04&size=1`，匿名 HTTP 200，返回 `count=0`、空 `result`；证明本次读取不需 key，**不证明任何真实歌曲有同步数据**。[官方 API 说明](https://github.com/izumin2000/subekashi#全て歌詞の所為ですapiについて)
- 若继续做限定曲目实验，优先 TextAlive，但须先明确内容权利、使用场景与 app token；若要正式扩大日本商业目录，优先向 SyncPower 询问逐行数据接口、费用、桌面端、地区、缓存及外部 Spotify 播放配合条件；本次没有发送咨询。[TextAlive 规则](https://developer.textalive.jp/terms/)、[SyncPower 官方入口](https://syncpower.jp/ja)
- 对当前 LyricGlass，先用已核实艺名消除现有来源的错误拒绝，再对日本 8 首固定样本跑统一查询；只有取得同一录音的真实时间轴后，才将结果计为新增同步覆盖。
