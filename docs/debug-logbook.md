# Debug Logbook

## 2026-04-02 SteamCMD Debug Track

### Goal
- 让软件内置的 SteamCMD 支持：
  - 登录 Steam
  - 保持登录状态
  - 浏览 Wallpaper Engine 创意工坊视频壁纸
  - 下载指定 Workshop 项目

### Key Runtime Paths
- 新日志：
  - `/Users/songziqiang/Library/Caches/MyWallpaperX/SteamWorkshop/steamcmd-auth-debug.log`
- 旧容器日志：
  - `/Users/songziqiang/Library/Containers/com.songziqiang.MyWallpaperX/Data/Library/Caches/MyWallpaperX/SteamWorkshop/steamcmd-auth-debug.log`
- 当前 Debug app：
  - `/Users/songziqiang/Library/Developer/Xcode/DerivedData/MyWallpaperX-ezuatvrxfeqxwzeubireydvbdhtc/Build/Products/Debug/MyWallpaperX.app`

### Stage 1
- 现象：
  - 登录一直卡在“请求中”
- 结论：
  - 不是 UI 卡住，而是缺少足够日志，无法确认命令是否真的发送
- 后续动作：
  - 为 Steam 认证流程增加持久调试日志

### Stage 2
- 日志确认：
  - `Steam>` 已出现
  - `login username password` 已写入
  - SteamCMD 输出 `Logging in using username/password.`
  - 随后不断报：
    - `CreateBoundSocket: ::bind to port 0 returned error [no name available](1)`
- 结论：
  - 失败点在联网建连阶段
  - 不是命令格式错误
  - 不是发送时机错误
  - 不是 `Steam>` 尚未就绪

### Stage 3
- 动作：
  - 引入 helper 模式
  - 让 helper 代理运行 `steamcmd.sh`
- 结果：
  - helper 侧日志成功建立
  - 新链路可以明确区分 app、helper、steamcmd 各阶段

### Stage 4
- 动作：
  - 增加 helper 启动前的清理逻辑
  - 试图自动清掉历史孤儿 SteamCMD 进程
- 新问题：
  - 日志只出现：
    - `steam helper started in proxy mode`
    - `steam root: ...`
  - 没有出现 `steam proxy child started successfully`
  - 没有出现 `Steam>`
  - 最终 20 秒超时
- 结论：
  - 启动前同步清理逻辑会阻塞 SteamCMD 控制台启动

### Stage 5
- 动作：
  - 关闭主 app `ENABLE_APP_SANDBOX`
- 结论：
  - 当前调试 app 已是无沙盒版本
  - 新日志路径变为普通用户缓存目录，不再主要写入容器目录

### Stage 6
- 动作：
  - 移除 helper 启动关键路径中的同步 `ps` 清理逻辑
  - 保留退出时清理与 signal 清理
- 当前目标：
  - 先恢复到 `Steam>` 出现
  - 再继续分析后续登录失败

### Stage 7
- 动作：
  - 将 SteamCMD 执行链路从 `MyWallpaperXWallpaperDaemon` 移回主 app
  - 主 app 直接以 `/bin/bash ./steamcmd.sh` 方式启动内置 SteamCMD
  - daemon 中移除 Steam helper 入口，恢复为纯壁纸播放职责
- 结论：
  - 无沙盒前提下，继续让 daemon 代理 SteamCMD 已经没有必要
  - 直接执行链路更简单，也更容易维护登录、下载和调试日志

### CPU Issue Record
- 现象：
  - 启用 demo 时 CPU 占用异常升高
- 排查结果：
  - 不是主界面网格本身
  - 是多组残留的孤儿 `steamcmd` / `steamcmd.sh`
- 已处理：
  - 手动清理过历史残留进程
  - helper 现在在退出路径上会清理自己的子进程组

### Current Hypothesis
- 当前最重要的不是继续猜联网失败原因，而是先确认：
  - 最新无沙盒构建
  - 去掉阻塞清理后
  - 是否重新恢复 `Steam>` 提示符

### Operational Rule
- 以后只要 Steam 问题连续三轮还没定位，就先加日志、先读日志，不继续盲猜。
- 多参考市面上主流软做法，不要自己盲目造轮子。
- 每次会话修改完记得修正本文档以免误导
