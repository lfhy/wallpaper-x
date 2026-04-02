# Project Working Memory

## Product Context
- `MyWallpaperX` 是一个 macOS 动态壁纸软件。
- Steam 创意工坊能力是软件中的一个工具型模块，不是产品唯一核心。
- Steam 这条链路的目标不是做完整 Steam 平台，而是：
  - 浏览 Wallpaper Engine 创意工坊里的视频类壁纸
  - 登录 Steam
  - 保持登录状态
  - 下载到 `~/Movies/MyWallpaperX/创意工坊`

## User Preferences
- 每次提问时，除非用户明确要求“直接改”，否则先检查、给结论，再等用户确认是否修改。
- 如果用户的建议不合理，需要主动指出并讨论，不要盲从。
- 优先做“最方便、最好用”的方案，而不是理论上最完美但工程代价过大的方案。
- 用户不希望用内嵌网页方式展示创意工坊浏览页，希望原生网格 UI。
- 登录页需要客户端化、流程直观。
- 登录状态和网格缓存都要持久化，不能每次返回都丢。

## Architecture Boundary
- 按 `AGENTS.md`，默认优先操作公共层：`App/`、`Shell/`、`Core/`、`Shared/`、`docs/`
- 这次 Steam 创意工坊功能属于用户明确要求修改的模块，可以进入 `Modules/SteamWorkshop`

## Current Steam Workshop Design
- 浏览页是原生网格，不直接呈现网页。
- 2026-04-02 当前浏览网格已切到 AppKit `NSCollectionView`，不再使用 SwiftUI `LazyVGrid`。
- 卡片默认展示较少信息。
- 点卡片进入类似 Quick Look 的详情弹窗。
- 详情弹窗内展示更多信息并提供下载按钮。
- 目前数据来源是抓取 Wallpaper Engine 创意工坊公开页面 HTML。
- 当前已确认应采用“两段式抓取”：
  - 浏览页抓卡片基础信息与预览图
  - 详情页抓文件大小、分辨率、类型、时间等权威元数据

## Current SteamCMD Strategy
- 不放弃 SteamCMD。
- 当前采用“随 app 打包内置 SteamCMD 运行时”的方案。
- 当前链路是：
  - app
  - `/bin/bash`
  - `./steamcmd.sh`
- 下载和登录都仍然围绕 SteamCMD。
- `MyWallpaperXWallpaperDaemon` 现在只负责壁纸播放，不再承接 SteamCMD 登录/下载。

## Important Paths
- 项目根目录：
  - `/Users/songziqiang/Documents/Development/MyWallpaperX`
- 当前调试 app 构建产物：
  - `/Users/songziqiang/Library/Developer/Xcode/DerivedData/MyWallpaperX-ezuatvrxfeqxwzeubireydvbdhtc/Build/Products/Debug/MyWallpaperX.app`
- 新的 SteamCMD 认证日志路径：
  - `/Users/songziqiang/Library/Caches/MyWallpaperX/SteamWorkshop/steamcmd-auth-debug.log`
- 旧的容器日志路径：
  - `/Users/songziqiang/Library/Containers/com.songziqiang.MyWallpaperX/Data/Library/Caches/MyWallpaperX/SteamWorkshop/steamcmd-auth-debug.log`
- 当前 Steam Workshop 缓存目录：
  - `/Users/songziqiang/Library/Caches/MyWallpaperX/SteamWorkshop`
- SteamCMD 下载运行时目录：
  - `/Users/songziqiang/Library/Application Support/MyWallpaperX/SteamWorkshopRuntime`
- 下载目标目录：
  - `~/Movies/MyWallpaperX/创意工坊`

## Important Files
- Steam 服务实现：
  - `/Users/songziqiang/Documents/Development/MyWallpaperX/MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService.swift`
- Steam 浏览页：
  - `/Users/songziqiang/Documents/Development/MyWallpaperX/MyWallpaperX/Modules/SteamWorkshop/UI/SteamWorkshopBrowserView.swift`
- Helper 可执行文件源码：
  - `/Users/songziqiang/Documents/Development/MyWallpaperX/WallpaperDaemonSources/main.swift`
- 框架备忘录：
  - `/Users/songziqiang/Documents/Development/MyWallpaperX/docs/framework-architecture-memo.md`

## Confirmed Findings
- 旧版本在 App Sandbox 下运行时，SteamCMD 登录阶段会报：
  - `CreateBoundSocket: ::bind to port 0 returned error [no name available](1)`
- 旧日志里可以确认：
  - `Steam>` 已出现
  - `login 用户名 密码` 命令已真实发出
  - 失败点不是命令格式，也不是发送时机
- 后来把 helper 启动前加入了同步清理逻辑后，新的无沙盒版本出现了另一种问题：
  - helper 启动了
  - 但 `Steam>` 没有出现
  - 20 秒超时，提示“SteamCMD 控制台未进入可登录状态”
- 已判断启动前的同步清理逻辑会卡住 SteamCMD 控制台启动，已移除该阻塞逻辑。
- 失败时曾残留大量孤儿 `steamcmd` / `steamcmd.sh` 进程，导致 CPU 占用升高。
- 已增加退出时子进程组清理，避免再次大量残留。
- 旧的“浏览页进入即额外 `refresh()`”会导致重复刷新，已移除。

## 2026-04-02 Steam Workshop Crawling Findings

### Snapshot Script
- 已新增抓取脚本：
  - `/Users/songziqiang/Documents/Development/MyWallpaperX/scripts/steam_workshop_snapshot.py`
- 用途：
  - 重新请求 Steam 页面，不依赖浏览器“另存为网页”
  - 保存 `page.html`
  - 保存 `headers.json`
  - 保存 `assets.json`
  - 导出 `inline-scripts/*.js`
- 默认抓取：
  - Wallpaper Engine 视频浏览页
  - 一个详情页

### Snapshot Locations Used In Analysis
- 第一组抓取：
  - `/tmp/steam-workshop-snapshots/browse-default`
  - `/tmp/steam-workshop-snapshots/detail-3694015003`
- 第二组抓取：
  - `/tmp/steam-workshop-snapshots-2/browse-default`
  - `/tmp/steam-workshop-snapshots-2/detail-3695850086`
- 2026-04-02 新一轮抓取：
  - `/tmp/steam-workshop-snapshots-20260402/browse-default`
  - `/tmp/steam-workshop-snapshots-20260402/detail-3693979526`

### Snapshot Script Output Status
- `scripts/steam_workshop_snapshot.py` 现已支持额外输出：
  - `page-summary.json`
- `page-summary.json` 当前会提取：
  - `page_kind`（`browse` / `detail` / `age-check` / `author-workshop`）
  - `workshop_item_ids`
  - `hover_bind_ids`
  - `preview_image_urls`
  - `preview_video_urls`
  - `detail_stats`
  - `detail_tags`
  - `detected_author_profile_url`
  - `detected_author_workshop_url`
  - `browse_author_links`
- 这意味着后续做解析器或回归检查时，不必每次重新人工翻整页 HTML。

### Confirmed Crawl Entry URLs / Endpoints
- 浏览页主入口：
  - `https://steamcommunity.com/workshop/browse/?appid=431960&requiredtags%5B0%5D=Video&actualsort=trend&browsesort=trend&p=1&days=7`
- 当前代码生成的浏览页 URL 规则：
  - 基础地址：
    - `https://steamcommunity.com/workshop/browse/`
  - 固定参数：
    - `appid=431960`
    - `requiredtags[0]=Video`
    - `p=1`
    - `numperpage=24`
  - 排序参数：
    - `browsesort=trend` / `actualsort=trend` 对应“精选”
    - `browsesort=mostrecent` / `actualsort=mostrecent` 对应“最新”
  - 精选页额外参数：
    - `days=7`
- 详情页主入口：
  - `https://steamcommunity.com/sharedfiles/filedetails/?id=<publishedfileid>`
- 已验证详情页样本：
  - `https://steamcommunity.com/sharedfiles/filedetails/?id=3694015003&searchtext=`
  - `https://steamcommunity.com/sharedfiles/filedetails/?id=3695850086`
  - `https://steamcommunity.com/sharedfiles/filedetails/?id=3693979526&searchtext=`

### Confirmed Asset URL Patterns
- 浏览页卡片预览图地址模式：
  - `https://images.steamusercontent.com/ugc/<bucket>/<hash>/?imw=200&imh=200&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true`
- 同一预览图的原始资源地址模式：
  - `https://images.steamusercontent.com/ugc/<bucket>/<hash>/`
- 这些地址不是伪链接，是真实资源入口。
- 真实格式不能只看 URL 字符串，必须看响应头：
  - 可能返回 `image/jpeg`
  - 也可能返回 `image/gif`
- 当前确认：
  - 列表动态图不是视频地址
  - 就是这类 `images.steamusercontent.com/ugc/...` 资源本身返回 GIF

### Confirmed Page-Embedded Data Sources
- 浏览页卡片基础数据来自 HTML：
  - `a.ugc[data-publishedfileid]`
  - `img.workshopItemPreviewImage`
  - `div.workshopItemTitle`
  - `div.workshopItemAuthorName`
  - `a.workshop_author_link`
- 浏览页摘要数据来自页面内联脚本：
  - `SharedFileBindMouseHover("sharedfile_<id>", false, {...})`
- 当前从这个内联 JSON 中已确认可取：
  - `id`
  - `title`
  - `description`
  - `short_description`（有些项目存在）
  - `appid`
- 详情页元数据来自 HTML：
  - `div.workshopTags`
  - `div.detailsStatLeft`
  - `div.detailsStatRight`
- 2026-04-02 新增确认的作者入口规则：
  - 浏览页卡片作者链接 `a.workshop_author_link` 直接就是作者作品页入口
  - 链接格式可能是：
    - `https://steamcommunity.com/profiles/<steamid64>/myworkshopfiles/?appid=431960`
    - `https://steamcommunity.com/id/<vanity>/myworkshopfiles/?appid=431960`
  - 详情页“创建者”卡片里的 `a.friendBlockLinkOverlay` 只是个人主页根链接
  - 详情页面包屑里的“<作者> 的创意工坊”才是更准确的作者作品页入口
  - 作者作品页自身再次跳转后，URL 可能丢掉 `appid` 参数；客户端打开时应主动补回 `appid=431960`

### External JS Files Inspected
- 已检查过这些脚本是否负责补动态缩略图：
  - `https://community.fastly.steamstatic.com/public/javascript/workshop_functions.js?v=Wv8xkmf6Zu53&l=schinese&_cdn=fastly`
  - `https://community.fastly.steamstatic.com/public/javascript/sharedfiles_functions_logged_out.js?v=-sWDs_50zi8c&l=schinese&_cdn=fastly`
  - `https://community.fastly.steamstatic.com/public/shared/javascript/shared_global.js?v=7Ir8gsoAIQ56&l=schinese&_cdn=fastly`
  - `https://community.fastly.steamstatic.com/public/javascript/global.js?v=LyPx5Rp50fw-&l=schinese&_cdn=fastly`
  - `https://community.fastly.steamstatic.com/public/shared/javascript/tooltip.js?v=k5leO7MVvAaV&l=schinese&_cdn=fastly`
- 结论：
  - `SharedFileBindMouseHover` 只负责文字 hover 和用户动作提示
  - 当前没有证据表明这些脚本会再额外请求“动态图预览接口”
  - 列表动态图的关键仍是 `workshopItemPreviewImage` 这个资源地址本身

### API / Interface Status
- 当前已明确可稳定使用的“页面接口”只有两类：
  - 浏览页 HTML
  - 详情页 HTML
- 当前已明确可稳定使用的“资源接口”只有一类：
  - `images.steamusercontent.com/ugc/...`
- 当前还没有确认到可直接替代 HTML 的官方 JSON 接口。
- 也还没有确认到专门返回“动态缩略图地址”的独立接口。
- 后续如果继续挖接口，优先方向：
  - 检查详情页 / 浏览页更多内联脚本变量
  - 检查 Steam 前端发起的异步请求
  - 检查 `api.steampowered.com` 是否有未公开但前端在调用的数据入口

### Detail Page Structure
- `3694015003` 这个示例详情页抓下来其实是“年龄确认页”，不是完整详情页。
- 不能再把成人内容确认页当作字段解析样本。
- `3695850086` 这个非成人详情页是有效样本。
- `3693979526` 这个非成人详情页也是有效样本。
- 非成人详情页里稳定存在：
  - 标题：`div.workshopItemTitle`
  - 标签区：`div.workshopTags`
  - 统计区：`detailsStatLeft` / `detailsStatRight`
  - 预览图
  - 下载按钮区
- 从详情页可稳定解析出的关键字段：
  - `Type`
  - `Age Rating`
  - `Genre`
  - `Resolution`
  - `Category`
  - `文件大小`
  - `发表于`
  - 有时可用 `Updated` / `Posted` 做时间回退
- 当前确认过的真实样例：
  - 标题：`千夏`
  - 类型：`Video`
  - 年龄分级：`Everyone`
  - 风格：`Unspecified`
  - 分辨率：`3840 x 2160`
  - 分类：`Wallpaper`
  - 文件大小：`119.801 MB`
  - 发布时间：`3 月 30 日 上午 9:13`
- 当前新增确认过的真实样例：
  - 项目：`3693979526`
  - 标题：`战双帕弥什Punishing Gray Ravenパニシング：グレイレイヴン`
  - 类型：`Video`
  - 年龄分级：`Everyone`
  - 风格：`Anime`
  - 分辨率：`3840 x 2160`
  - 分类：`Wallpaper`
  - 文件大小：`9.682 MB`
  - 发布时间：`3 月 28 日 上午 4:53`

### Browse Page Structure
- 浏览页稳定存在：
  - `a.ugc[data-publishedfileid]`
  - `img.workshopItemPreviewImage`
  - `div.workshopItemTitle`
  - `div.workshopItemAuthorName`
  - `SharedFileBindMouseHover(...)`
  - 分页信息
- 浏览页不可靠或通常没有：
  - 文件大小
  - 分辨率
  - 详细时间
- `SharedFileBindMouseHover(...)` 的 JSON 里可稳定补出：
  - `id`
  - `title`
  - `description`
  - 有时可用 `short_description`
- 当前浏览页样本中：
  - 一页可抓到 30 个条目
  - 其中 9 个带成人标记 `has_adult_content`
- 2026-04-02 默认浏览页快照中再次确认：
  - 一页可抓到 30 个条目
  - `workshop_item_ids` 与 `hover_bind_ids` 可以一一对应
  - 页面内确实包含 `3693979526`
  - 当前样本中 30 个项目 ID 为：
    - `3692350202`
    - `3692552963`
    - `3692661003`
    - `3692685212`
    - `3692730591`
    - `3693052008`
    - `3693167595`
    - `3693177435`
    - `3693541298`
    - `3693817733`
    - `3693979526`
    - `3693999277`
    - `3694073141`
    - `3694218591`
    - `3694609705`
    - `3694653764`
    - `3694802410`
    - `3694873457`
    - `3695449718`
    - `3695681565`
    - `3695686517`
    - `3695850086`
    - `3696635405`
    - `3696769227`
    - `3696881570`
    - `3696890942`
    - `3696993837`
    - `3697014306`
    - `3697088900`
    - `3697137461`

### Preview Asset Findings
- 详情页本身不能用于判断“动态缩略图是否存在”。
- 默认浏览页卡片缩略图 URL 才是关键来源。
- 页面 HTML 里预览图 URL 没有直接暴露 `.gif` 扩展名。
- 真实动态图 / 静态图需要通过预览图 URL 的响应 `Content-Type` 判断。
- 已确认：
  - 有些 `workshopItemPreviewImage` 返回 `image/jpeg`
  - 有些返回 `image/gif`
- 这说明：
  - 浏览页确实存在 GIF 动态缩略图
  - 不是 hover 脚本后补进去的视频
  - 也不是详情页提供的动态预览
- 已验证具体 GIF 例子：
  - URL：
    - `https://images.steamusercontent.com/ugc/10326955497799059572/D9C71885222C4A226CABABCDCD830D35F40C8057/?imw=200&imh=200&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true`
  - 返回：
    - `Content-Type: image/gif`
  - 去参数后的原始资源也返回：
    - `Content-Type: image/gif`
  - 该图对应的 Workshop 项目：
    - `3693052008`
    - 标题：`AI星瞳藏刃 飞花入梦 #眼睛里有星`
    - 作者：`我赶羚羊`

### Current Parsing Strategy That Should Be Preserved
- 浏览页：
  - 解析卡片基础信息
  - 解析 hover JSON 摘要
  - 保留预览图 URL
  - 额外探测预览图 MIME 类型，区分 GIF / JPG
- 详情页：
  - 解析 `Type`
  - 若 `Type != Video`，则过滤掉该条目
  - 解析 `Resolution`
  - 解析 `File Size`
  - 解析 `Posted / Updated`
  - 解析 `Category / Genre / Age Rating`

### Recent Regression And Fix
- 回归现象：
  - Steam 创意工坊列表一度只显示 1 张壁纸
- 真正原因：
  - 浏览页卡片解析正则写错，只匹配到了 1 个块
  - 不是 Steam 只返回 1 条
  - 不是 GIF 探测把其他项吞掉
- 修复后验证结果：
  - 同一份浏览页样本重新可匹配出 30 个条目
- 这个回归说明：
  - 后续只要再改浏览页解析逻辑，必须优先用本地抓下来的样本校验条目数量

## Current Steam Workshop Implementation Status
- `SteamWorkshopService` 当前已接入：
  - 浏览页卡片解析
  - 详情页补全元数据
  - 浏览页 hover 摘要解析
  - 预览图 MIME 探测
  - GIF / JPG 区分
  - 详情缓存已回写预览类型结果，避免同一批条目反复做 MIME 探测
  - 作者个人主页 URL 与作者作品页 URL 分离建模，详情按钮优先直达作者作品页
  - 作者工坊页已复用同一套列表抓取 / 分页 / 详情补全链路，不再依赖外部浏览器
- 2026-04-02 这一轮已经额外接入：
  - 详情页完整字段承载模型，而不只是少数固定字段
  - `Type / Age Rating / Genre / Category / File Size / Resolution / Posted / Updated / Favorites / Subscriptions / Score`
  - 详情页动态字段列表 `detailFields`
  - 浏览页分类筛选 `Category`
  - 更完整的主题筛选枚举
- `SteamWorkshopBrowserView` 当前已接入：
  - GIF 动态预览显示
  - 根据真实预览类型显示“动态预览 / 静态预览”
  - 浏览页网格已改成 AppKit 容器，布局思路与其他模块一致
  - 浏览卡片会跟随下载状态实时切换：
    - 下载中显示进度文本并允许取消
    - 下载失败显示重试态
    - 已下载显示本地完成态
  - 卡片详情弹层显示：
    - 类型
    - 年龄分级
    - 题材
    - 分类
    - 文件大小
    - 分辨率
    - 发布时间
    - 更新时间
    - 收藏
    - 订阅
    - 评分
  - 卡片详情弹层新增完整“详细信息”区，会把详情页抓到的字段尽量完整展示
  - 详情弹层会显示最近一次下载失败原因，并提供就地重试入口
  - 详情弹层“作者工坊”按钮已改为优先使用页面里真实暴露的作者作品页直链
  - 点击“作者工坊”会在模块内部切换到该作者的工坊列表，并复用原有列表抓取流程
  - 作者工坊模式已接入独立分页判断，不再沿用总榜的页容量阈值
  - 从作者工坊“返回总榜”时，会恢复进入前的总榜列表状态、滚动位置和详情选中项
- `SteamWorkshopToolbarController` 当前已接入：
  - 排序
  - 热门时间段
  - 主题筛选
  - 年龄分级筛选
  - 分辨率筛选
  - 分类筛选
  - 作者工坊模式下会禁用排序 / 热门时间段 / 筛选，搜索改为作者列表内搜索
  - 作者工坊模式下工具栏会显示“返回总榜”入口
  - 进入 / 退出作者工坊时，工具栏按钮状态会立即同步，不再等到二次点击后才刷新
- 2026-04-02 本轮新增确认：
  - 工具栏筛选菜单已完成中文化
  - 筛选摘要不再显示后台英文 tag 值，改为显示中文筛选名称
  - 工具栏筛选按钮会根据已选筛选数量显示 `筛选 1`、`筛选 2` 这类状态
  - AppKit 卡片已加入 hover 高亮、边框和阴影反馈
  - AppKit 卡片二级元信息和标签已做中文化映射
  - 浏览卡片已接入下载状态：
    - 下载中会实时刷新进度文本并允许取消
    - 下载失败会切到重试态
    - 已下载显示完成态并禁用重复下载
  - 详情面板已接入本地状态操作：
    - 已下载项目显示“打开文件夹”
    - 已下载项目可直接“设为壁纸”
- 仍建议后续补上：
  - 如果后续要覆盖“详情抓取失败时的回退卡片”，仍可继续补独立的预览 URL 级 MIME 缓存
  - AppKit 卡片选中 / 下载进度视觉继续细化到更接近官方客户端

## 2026-04-02 Module Integration Notes
- 已确认本轮不是只停留在脚本层，抓到的详情页数据已经接入 `SteamWorkshop` 模块。
- 当前详情页信息源仍然是：
  - 浏览页 HTML
  - 详情页 HTML
- 当前模块里对详情字段的处理策略是：
  - 优先抓稳定字段进入固定 UI 槽位
  - 其余字段进入 `detailFields`
  - 详情弹层尽量完整展示，而不是只显示摘要
- 当前固定字段映射规则：
  - `Type` → 类型
  - `Age Rating` → 年龄分级
  - `Genre` → 题材
  - `Category` → 分类
  - `File Size` / `文件大小` → 文件大小
  - `Resolution` → 分辨率
  - `Posted` / `发表于` → 发布时间
  - `Updated` / `Last Updated` → 更新时间
  - `Favorite / Favorited` → 收藏
  - `Subscriptions` → 订阅
  - `Score` → 评分

## Current Known Problems
- 旧的 SwiftUI 网格错位问题已通过改成 AppKit 网格处理。
- 详情页作者字段的“在线 / 离线”混入问题已经修过一轮，但仍建议继续观察更多样本页是否还有漏网别名。
- `contains_login_gate` 这类脚本摘要字段只是宽松判断，不应作为业务真值。
- 详情页并不总能提供预览视频 URL：
  - 当前更稳定的是图片 / GIF 预览
  - 不能假设每个详情页都有可直接播放的视频预览资源
- 浏览页卡片层已经开始展示类型、年龄分级、题材、分类等元信息，但距离官方客户端仍差一层更完整的状态组织与下载态表达。
- 浏览页卡片的下载态已经补到“下载中 / 失败重试 / 已下载”三种基础状态，但还可以继续补：
  - 下载完成后的更明确视觉层级
  - 已安装与可更新的差异化表达
- 详情页字段存在中英文混排：
  - 当前代码已经兼容一部分中英文 key
  - 但后续仍应继续扩充字段别名，避免不同地区页面导致字段丢失
- 成人内容条目已经有列表角标、详情提示和“在 Steam 中打开”入口，但成人校验页本身仍可继续补更明确的异常态展示。
- 当前已做的 QoS 风险缓解：
  - `SteamWorkshop` 关键异步路径已调整为更合适的任务优先级
  - 预取不再使用容易造成上下文割裂的 `Task.detached(priority: .utility)`
  - 后续仍建议继续观察 Instruments 的 Hang Risk 提示是否完全消失

## Restart Reminder
- 如果重启客户端后继续做 `SteamWorkshop`，优先记住以下事实：
  - 当前模块方向是“Wallpaper Engine 桌面客户端化”，不是网页壳
  - 数据源仍以 Steam 浏览页 + 详情页 HTML 为主
  - 当前默认视频浏览页样本稳定有 30 个项目
  - `3693979526` 是新的有效详情页基准样本
  - 本轮已完成“字段接入模块”、“详情弹层展示增强”、“AppKit 网格替换”、“筛选菜单中文化”、“预览类型缓存回写”、“下载失败重试态接入”、“作者工坊模块内二次抓取”
  - 下一阶段更值得做的是：
    - 继续增强卡片列表的已更新态 / 可更新态表达
    - 做成人页 / 异常页兜底细化
    - 把 MIME 缓存从条目级进一步扩展到 URL 级回退链路

## Current Build Status
- 主 app 的 `ENABLE_APP_SANDBOX` 已改为 `NO`
- 最新 Debug 构建已成功编译
- SteamCMD 执行链路已从 daemon 切回主 app 直接启动内置 `steamcmd.sh`
- 当前需要验证：最新无沙盒构建下，直接启动链路是否稳定进入 `Steam>` 并保持登录/下载 UX 正常

## Current Risks
- SteamCMD 的实际运行行为对 macOS 权限模型很敏感。
- 现在不要再把 SteamCMD 逻辑重新塞回壁纸 daemon，避免职责再次混杂。
- 需要优先保证：
  - `steamcmd.sh` 能进入 `Steam>`
  - 登录命令能发送
  - 失败时能回收子进程
  - 进入浏览页时不再无意义触发重新登录

## Next Recommended Steps
- 用最新 Debug 构建重新测试一次登录。
- 第一优先级不是“马上登录成功”，而是确认是否已经恢复到：
  - `Steam>` 出现
  - `login ...` 被发送
- 若恢复到了这一步，再继续分析联网失败或 Steam Guard 流程。
- 每次分析时都优先读取最新日志，不凭记忆推断。

## How To Prompt Next Time
- 如果要我先接上下文：
  - “先读 `AGENTS.md`、`CLAUDE.md`、`docs/project-working-memory.md`、`docs/debug-logbook.md` 再继续。”
- 如果只想继续 Steam 问题：
  - “先读 `docs/project-working-memory.md` 和 `docs/debug-logbook.md`，继续处理 Steam 问题。”
- 如果要我先看日志再判断：
  - “先读 `docs/project-working-memory.md`，再读取最新 Steam 日志给结论，不要直接改。”
- 如果要继续创意工坊页面抓取/显示：
  - “先读 `docs/project-working-memory.md`，继续处理 Steam 创意工坊浏览页抓取和显示逻辑。”
- 多参考市面上主流软做法，不要自己盲目造轮子。
- 每次会话修改完记得修正本文档以免误导。
