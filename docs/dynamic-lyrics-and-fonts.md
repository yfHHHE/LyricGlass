# Dynamic-Lyrics 与字体目录调研

核对时间：2026-11-04（Asia/Singapore）。本笔记只记录公开的一手资料与实施建议，没有安装、购买或检查竞品运行中的设置窗口；字体二进制未在调研阶段下载。

## 竞品身份与已核实功能

参考对象是 **Dynamic-Lyrics（灵动歌词），App Store ID 6476125287**，开发者显示为云冰 谭，提供者为 Guangzhou Haoke Information Technology Co., Ltd。App Store 页面列出 Mac 支持、浮动歌词、状态栏歌词、Music Island、歌词翻译等。浮动歌词支持自定义样式和快捷操作；状态栏显示长度可以调整。[官方 App Store 页面](https://apps.apple.com/us/app/dynamic-lyrics/id6476125287?platform=mac)

其版本历史还记录原生浮动窗模糊背景、全局快捷键、启动选项、屏幕选择、翻译语言设置和逐字歌词开关。这些说明可以证明对应功能存在，**不能证明当前设置的分组、尺寸、侧栏或控件排版**。本次未取得足够的一手图像来声称复刻其设置窗口。 同样，本次未建立与该开发者对应的官方 GitHub 源码仓库关系，不把同名仓库当作其实现证据。[官方版本历史](https://apps.apple.com/us/app/dynamic-lyrics/id6476125287?platform=mac)

`musiclyrics.cn` 展示 Dynamic Lyrics 的浮动窗、系统界面融合、实时歌词和翻译，并链接同一个 App Store 产品。但它的「Mac Version」链接目前指向 **Dynamic Notch**，是另一个名称的 Mac 产品；该页面不能直接当作 Dynamic-Lyrics 设置页证据。[Dynamic Lyrics 官方站](https://musiclyrics.cn/) · [Mac 链接目标](https://musiclyrics.cn/mac/)

搜索还会找到 `dynamiclyrics.app`，其页面自称面向 iPhone、CarPlay、锁屏和小组件。本次没有建立其与上述 App Store ID 的可靠身份关系，不能把两者的界面或功能混在一起。[同名网站](https://dynamiclyrics.app/)

### 应用于 LyricGlass 的设计判断

以下是针对 LyricGlass 的实施建议，并非竞品截图中观察到的布局：

- 右键菜单只保留显示/隐藏、锁定位置、设置与退出；把播放源、连接、歌词偏移、重试、LRC、缓存与演示集中到设置。
- 使用原生侧栏区分「外观」「播放与歌词」「关于」，避免一页并排堆满全部选项。
- 外观页保留实时歌词预览，让颜色、背景、字号和字体的变化有明确反馈；预览与实际歌词共用绘制组件。
- 用排版、留白、分组背景和一致的控件宽度提高精致度，保留原生键盘与辅助功能操作。
- 字体按用户提出的五组分类，并显示可用状态；未安装的收费字体不能显示成已经可用，也不能静默以系统字体冒充。

## 可以随 app 提供的字体

下面各项均直接读取了对应官方固定版本的 OFL 文件，确认包含 SIL Open Font License 1.1。分发时保留原始二进制、完整许可和来源记录；不要改名、改造后继续使用保留名称。具体保留名称以各项的原始许可为准。

Google Fonts 的以下文件固定于提交 `2fe1e8c6b137fb13041a7cfca6fdcd8a910ea4dc`。它们是仓库提供的独立桌面 TTF，不是 CSS 分片 WOFF/WOFF2；「独立文件」不意味着覆盖世界上所有字符。[官方固定版本字体仓库](https://github.com/google/fonts/tree/2fe1e8c6b137fb13041a7cfca6fdcd8a910ea4dc/ofl)

| 显示名称 | 桌面文件 | 文件字节数 | 原始许可 |
| --- | --- | ---: | --- |
| 思源风格黑体 / Noto Sans SC | [NotoSansSC[wght].ttf](https://raw.githubusercontent.com/google/fonts/2fe1e8c6b137fb13041a7cfca6fdcd8a910ea4dc/ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf) | 17,772,300 | [OFL.txt](https://raw.githubusercontent.com/google/fonts/2fe1e8c6b137fb13041a7cfca6fdcd8a910ea4dc/ofl/notosanssc/OFL.txt) |
| 思源风格宋体 / Noto Serif SC | [NotoSerifSC[wght].ttf](https://raw.githubusercontent.com/google/fonts/2fe1e8c6b137fb13041a7cfca6fdcd8a910ea4dc/ofl/notoserifsc/NotoSerifSC%5Bwght%5D.ttf) | 25,125,512 | [OFL.txt](https://raw.githubusercontent.com/google/fonts/2fe1e8c6b137fb13041a7cfca6fdcd8a910ea4dc/ofl/notoserifsc/OFL.txt) |
| Inter | [Inter[opsz,wght].ttf](https://raw.githubusercontent.com/google/fonts/2fe1e8c6b137fb13041a7cfca6fdcd8a910ea4dc/ofl/inter/Inter%5Bopsz%2Cwght%5D.ttf) | 876,576 | [OFL.txt](https://raw.githubusercontent.com/google/fonts/2fe1e8c6b137fb13041a7cfca6fdcd8a910ea4dc/ofl/inter/OFL.txt) |
| JetBrains Mono | [JetBrainsMono[wght].ttf](https://raw.githubusercontent.com/google/fonts/2fe1e8c6b137fb13041a7cfca6fdcd8a910ea4dc/ofl/jetbrainsmono/JetBrainsMono%5Bwght%5D.ttf) | 187,208 | [OFL.txt](https://raw.githubusercontent.com/google/fonts/2fe1e8c6b137fb13041a7cfca6fdcd8a910ea4dc/ofl/jetbrainsmono/OFL.txt) |
| Fira Code | [FiraCode[wght].ttf](https://raw.githubusercontent.com/google/fonts/2fe1e8c6b137fb13041a7cfca6fdcd8a910ea4dc/ofl/firacode/FiraCode%5Bwght%5D.ttf) | 260,364 | [OFL.txt](https://raw.githubusercontent.com/google/fonts/2fe1e8c6b137fb13041a7cfca6fdcd8a910ea4dc/ofl/firacode/OFL.txt) |
| Cascadia Code | [CascadiaCode[wght].ttf](https://raw.githubusercontent.com/google/fonts/2fe1e8c6b137fb13041a7cfca6fdcd8a910ea4dc/ofl/cascadiacode/CascadiaCode%5Bwght%5D.ttf) | 727,940 | [OFL.txt](https://raw.githubusercontent.com/google/fonts/2fe1e8c6b137fb13041a7cfca6fdcd8a910ea4dc/ofl/cascadiacode/OFL.txt) |
| Merriweather | [Merriweather[opsz,wdth,wght].ttf](https://raw.githubusercontent.com/google/fonts/2fe1e8c6b137fb13041a7cfca6fdcd8a910ea4dc/ofl/merriweather/Merriweather%5Bopsz%2Cwdth%2Cwght%5D.ttf) | 4,628,080 | [OFL.txt](https://raw.githubusercontent.com/google/fonts/2fe1e8c6b137fb13041a7cfca6fdcd8a910ea4dc/ofl/merriweather/OFL.txt) |
| EB Garamond | [EBGaramond[wght].ttf](https://raw.githubusercontent.com/google/fonts/2fe1e8c6b137fb13041a7cfca6fdcd8a910ea4dc/ofl/ebgaramond/EBGaramond%5Bwght%5D.ttf) | 851,176 | [OFL.txt](https://raw.githubusercontent.com/google/fonts/2fe1e8c6b137fb13041a7cfca6fdcd8a910ea4dc/ofl/ebgaramond/OFL.txt) |

Noto 与 Source Han 是同源设计的不同发行，不能把两个名字理解成同一个二进制的逐字等价别名。对于用户的「Source Han / Noto」选项，可以明确选用 Noto SC 的实现并保留可检索的中文名称，避免捆绑两套相近的大体积字体。[Adobe Source Han Sans](https://github.com/adobe-fonts/source-han-sans) · [Adobe Source Han Serif](https://github.com/adobe-fonts/source-han-serif)

### 霞鹜文楷 / LXGW WenKai

官方固定提交为 `da0fdf92a0adc5d83c82ecde06d6665c97a2a45e`，发行版 v1.530。该版本提供 Light、Regular、Medium，**没有名为 Bold 的文件**；强调字重可选 Medium，不应把 Medium 文件当作真实 Bold 对用户描述。原版中文字体来源是 Fontworks Klee 的衍生设计。[官方项目](https://github.com/lxgw/LxgwWenKai) · [固定许可](https://raw.githubusercontent.com/lxgw/LxgwWenKai/da0fdf92a0adc5d83c82ecde06d6665c97a2a45e/OFL.txt)

| 用途 | 文件 | 字节数 |
| --- | --- | ---: |
| 常规 | [LXGWWenKai-Regular.ttf](https://raw.githubusercontent.com/lxgw/LxgwWenKai/da0fdf92a0adc5d83c82ecde06d6665c97a2a45e/fonts/TTF/LXGWWenKai-Regular.ttf) | 25,928,940 |
| 强调 | [LXGWWenKai-Medium.ttf](https://raw.githubusercontent.com/lxgw/LxgwWenKai/da0fdf92a0adc5d83c82ecde06d6665c97a2a45e/fonts/TTF/LXGWWenKai-Medium.ttf) | 25,800,076 |

其许可除标准 OFL 外带有保留名称及额外许可段落，随原始文件完整提供；本次实现无需修改字体。Google Fonts 的 `ofl/lxgwwenkai` 在核对时不存在，不能写一个猜测的下载链接。[官方字体目录](https://github.com/lxgw/LxgwWenKai/tree/da0fdf92a0adc5d83c82ecde06d6665c97a2a45e/fonts/TTF)

### 源流明体 / GenRyuMin

官方固定提交为 `030cd4fa3dd6b0607c5e7f35f13977a2e0a10522`，发行版 v2.100。项目包含 TC、TW、JP、PJP 版本，选择时记录准确版本；中文场景可选择 TC，不要把它描述成专门的 SC 字体。[官方项目](https://github.com/ButTaiwan/genryu-font) · [固定 SIL OFL 1.1 许可](https://raw.githubusercontent.com/ButTaiwan/genryu-font/030cd4fa3dd6b0607c5e7f35f13977a2e0a10522/SIL_Open_Font_License_1.1.txt)

| 用途 | 文件 | 字节数 |
| --- | --- | ---: |
| 常规 | [GenRyuMin2TC-R.otf](https://raw.githubusercontent.com/ButTaiwan/genryu-font/030cd4fa3dd6b0607c5e7f35f13977a2e0a10522/otf/TC/GenRyuMin2TC-R.otf) | 16,454,556 |
| 粗体 | [GenRyuMin2TC-B.otf](https://raw.githubusercontent.com/ButTaiwan/genryu-font/030cd4fa3dd6b0607c5e7f35f13977a2e0a10522/otf/TC/GenRyuMin2TC-B.otf) | 16,222,784 |

文件名不一定等于 PostScript 名称。下载后用 Core Text 枚举字体描述符并验证实际 family、字重和中文样本，不能仅按文件名猜测注册后的名称。

### 已有 OpenDyslexic

保留现有 Regular、Bold 及各自已经固定的来源和 OFL；不需要更换为另一个不明下载站的版本。OpenDyslexic 的中文缺字继续通过系统后备字体处理。[官方项目](https://github.com/antijingoist/opendyslexic)

## 系统字体与仅使用本机安装的字体

Apple 的字体文档明确要求：不要把系统提供、可按需下载或经 Apple Fonts 发布的字体重新随 app 分发，包括 SF Pro、SF Mono 和 New York。运行时应使用 AppKit 系统字体/API，私有字体只以 `.process` 范围注册。[Apple 字体使用文档](https://developer.apple.com/documentation/technologyoverviews/fonts) · [Apple 字体总览](https://developer.apple.com/fonts/)

| 字体 | LyricGlass 的接入方式 | 一手依据 |
| --- | --- | --- |
| SF Pro / San Francisco | `NSFont.systemFont`，跟随当前 macOS | [Apple 字体文档](https://developer.apple.com/documentation/technologyoverviews/fonts) |
| SF Pro Rounded | 系统字体 `.rounded` 设计 | [Apple 字体文档](https://developer.apple.com/documentation/technologyoverviews/fonts) |
| SF Mono | 系统等宽字体/API，不打包 Apple 字体文件 | [Apple 字体文档](https://developer.apple.com/documentation/technologyoverviews/fonts) |
| New York | 系统字体 `.serif` 设计 | [Apple 字体文档](https://developer.apple.com/documentation/technologyoverviews/fonts) |
| PingFang SC / 苹方 | 按本机可用 PostScript 名称获取，验证实际可用性 | [Apple 系统字体目录](https://developer.apple.com/fonts/system-fonts/) |
| Hiragino Sans GB / 冬青黑体 | 按本机可用名称获取；可能需要通过字体册下载 | [Apple 随附字体说明](https://support.apple.com/en-ie/122869) |
| Helvetica Neue | 使用本机已安装版本，不重新分发 | [Apple 随附字体说明](https://support.apple.com/en-ie/122869) |
| 方正兰亭宋 / FZLanTingSong | 仅使用本机已授权安装的字体；不得以免费下载按钮推断 app 嵌入授权 | [方正兰亭宋官方页面](https://www.foundertype.com/index.php/FontInfo/ductdetail/id/248.html) |
| 方正悠宋 / FZYouSong | 同上；家族包含多档字重，匹配实际安装名称 | [方正悠宋官方页面](https://nzj.foundertype.com/394.html?font_id=1825) |
| Neue Haas Grotesk | 仅使用本机已授权安装版本；桌面许可不包含分发字体或嵌入 app | [Monotype/MyFonts 产品许可说明](https://www.myfonts.com/collections/neue-haas-grotesk-font-linotype) |
| Berkeley Mono | 仅使用本机已授权安装版本；不要自动下载或加入仓库 | [官方规格与许可标识](https://cdn.berkeleygraphics.com/static/typefaces/berkeley-mono/datasheet/DX-102-10.pdf) · [官方许可入口](https://berkeleygraphics.com/legal/license) |

方正兰亭宋是产品 ID 248，和「方正兰亭刊宋」ID 415 不同，搜索和字体别名不要混淆。方正页面将桌面使用、商业发布和软件内置字体授权分开说明，不能因用户有桌面字体就视为 LyricGlass 取得对外分发字体文件的许可。[方正授权说明](https://www.foundertype.com/index.php/FontInfo/ductdetail/id/248.html)

Berkeley 规格书标明专有、不可转让；官方许可网页本次通过读取工具不可访问，所以本笔记不推测其额外商业条款。[官方规格书](https://cdn.berkeleygraphics.com/static/typefaces/berkeley-mono/datasheet/DX-102-10.pdf)

## 落地检查

- 字体菜单按中文黑/楷、中文宋/明、英文无衬线、等宽、英文衬线分组，保留 OpenDyslexic；系统字体、随附字体和未安装字体的状态分别可见。
- 对可选项验证真正的字体名称、常规/强调字重和中英样本。缺少指定字体时显示不可选状态或明确的后备说明，避免名称与实际渲染不一致。
- 记录每个字体文件的固定来源、SHA256 和原始许可。中文字体本身较大，完整打包上述中文常规与强调字体约增加 127 MB，拉丁字体约再增加 7.5 MB；安装包大小以实际构建为准。
- 原生字体尺寸应依据实际字体度量和样本文字校验，保证最大字号下两行及阴影仍可见。
- 把播放器模式、实际来源、歌词偏移、重试/LRC、缓存及连接权限移入设置时，保留原有行为与可恢复入口，特别是鼠标穿透之后仍可从菜单栏解锁。
