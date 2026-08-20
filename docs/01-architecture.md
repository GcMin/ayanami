# 系统架构

## 1. 架构原则

- Android 优先：当前实现和验收首先围绕 Android 10+。
- 本地优先：书架、阅读进度、源安装状态和下载状态均以本地持久化为事实来源。
- 插件隔离：JavaScript 漫画源只负责内容访问规则，不进入 UI、数据库、下载调度或任意文件系统。
- 单向依赖：表现层依赖应用层，应用层依赖领域接口，基础设施实现端口。
- 可取消：搜索、详情、章节、页面解析和下载都应支持取消。
- 可替换：JS Runtime、数据库 ORM 和网络库通过适配器隔离。

## 2. 一级页面结构

```text
AppShell
  +-- LibraryTab   书架（默认）
  +-- SourcesTab   漫画源
  +-- SettingsTab  设置
```

### LibraryTab

负责：

- 书架列表；
- 阅读进度；
- 未读状态；
- 本地下载状态；
- 批量选择和批量下载；
- 继续阅读。

### SourcesTab

负责两部分：

```text
漫画源
  +-- Content Discovery
  |     +-- 单源浏览
  |     +-- 单源搜索
  |     +-- 多源聚合搜索
  |     +-- 热门/最新/筛选
  |
  +-- Source Management
        +-- 已安装源
        +-- 添加 JS 源
        +-- 启用/禁用
        +-- 更新/删除
        +-- 错误和权限信息
```

“发现”不再单独作为一级页面。

### SettingsTab

只负责应用级偏好，不承担漫画源管理。

## 3. 逻辑分层

```text
Flutter Views
    |
ViewModels / UI State
    |
Application Use Cases
    |
Domain Models + Ports
    |
Repositories / Adapters
    +-- Local Database
    +-- File Store
    +-- Source Runtime Adapter
    +-- Network Adapter
    +-- Background Download Adapter
```

### 表现层

推荐功能目录：

```text
features/
  library/
  sources/
  manga_detail/
  reader/
  downloads/
  settings/
```

搜索与发现属于 `sources/`，不再单列为一级 `discovery/` 功能。

### 应用层

主要用例：

- `InstallSource`
- `EnableSource`
- `DisableSource`
- `SearchSource`
- `SearchAcrossSources`
- `BrowseSource`
- `LoadMangaDetails`
- `RefreshChapters`
- `AddToLibrary`
- `RemoveFromLibrary`
- `OpenReader`
- `SaveReadingProgress`
- `CreateLibraryDownloadBatch`
- `EnqueueChapterDownload`

用例负责事务边界和跨仓储编排，不包含 Flutter Widget、具体 SQLite SQL 或具体 JS 引擎调用。

## 4. JavaScript 漫画源架构

```text
SourceManager
  -> SourceInstallationStore
  -> SourcePermissionStore
  -> SourceRuntimeAdapter
       -> JS Runtime
       -> Host API Gateway
            -> SourceHttpClient
            -> Html/Json Parser
            -> SourceScopedStorage
```

### 4.1 当前实现

当前仓库已有：

- `flutter_js` 驱动的 JS 执行原型；
- `ManwaSourceService`；
- JS 生成请求描述、Dart 执行 HTTP、JS 再解析结果的闭环；
- 真实漫画源搜索、详情和章节验证代码。

这说明 JS 插件链路已经开始落地，不再把“JS 源完全未实现”作为当前状态。

### 4.2 目标实现

当前 `flutter_js` 方案视为过渡 Runtime Adapter。最终运行时必须具备：

- 每源隔离；
- 超时；
- 内存限制；
- Host API 白名单；
- 网络域名限制；
- 日志脱敏；
- 可取消调用；
- JS 异常不得导致 Flutter UI 崩溃。

是否最终使用 QuickJS C ABI 由运行时原型验证决定，但领域层和 Source SDK 不依赖具体引擎。

## 5. 源调用链路

### 5.1 聚合搜索

```text
SourcesTab 输入关键词
   -> SearchAcrossSources
   -> 快照全部已启用且支持 search 的源
   -> 每个源独立执行 search()
   -> Host API 执行受限网络请求
   -> Schema 校验
   -> 附加 sourceId/sourceVersion
   -> 逐源返回结果
```

### 5.2 单源浏览

```text
用户打开某个 Source
   -> 查看该源 capability
   -> getPopular()/getLatest()/getFilters()
   -> 展示内容
```

不支持的 capability 不显示入口。

### 5.3 详情

```text
SourceSearchResult
   -> 根据 sourceId 找到同一 SourceInstallation
   -> getMangaDetails(mangaRefSnapshot)
   -> getChapters(details)
   -> 标准化并缓存
   -> 展示详情
```

禁止根据标题让其他源解析该结果。

### 5.4 阅读

```text
Chapter
   -> getPages(chapter)
   -> Page[]
   -> Image/Page Repository
   -> Reader
```

阅读器不直接调用 JS Runtime。

## 6. 数据流

书架对象至少保留：

```text
LibraryEntry
  mangaId
  sourceId
  sourceMangaId
  titleSnapshot
  coverSnapshot
  lastChapterId
  lastPage
  unreadCount
  updatedAt
```

后续即使源被删除，书架仍能展示本地快照和已下载内容。

## 7. 并发与错误隔离

- UI isolate 不执行重型 HTML/JSON 解析；
- 一个源失败不得取消其他源；
- 新搜索取消旧搜索；
- 迟到结果必须通过 `requestId` 丢弃；
- 同一章节只允许一个活动正式下载任务；
- JS Runtime 崩溃或异常必须转换为领域错误。

统一错误类别：

| 类别 | 示例 |
|---|---|
| `SourceInvalid` | Manifest/返回 Schema 错误 |
| `SourcePermissionDenied` | 请求未声明域名 |
| `SourceTimeout` | JS 或网络超时 |
| `SourceChanged` | 页面结构变化导致解析失败 |
| `NetworkUnavailable` | 断网/DNS 失败 |
| `StorageFull` | 空间不足 |
| `Cancelled` | 新请求或页面离开 |

## 8. 推荐工程结构

```text
lib/
  app/
    app.dart
    app_shell.dart
  features/
    library/
    sources/
    manga_detail/
    reader/
    downloads/
    settings/
  application/
  domain/
  infrastructure/
    database/
    files/
    network/
    source_runtime/
    background/
assets/
  sources/
test/
integration_test/
docs/
```

当前 `lib/main.dart` 中的大量原型代码后续应按该结构拆分。一个 10 万行左右的单文件当然也能运行，只是它通常会开始对维护者进行心理战。

## 9. 技术选择原则

- Flutter 负责 Android UI；
- SQLite/Drift 作为最终本地结构化存储；
- Android 后台下载使用 WorkManager；
- JS Runtime 必须通过 `SourceRuntimeAdapter` 隔离；
- Host API 契约优先于具体 JS 引擎；
- 更换 Runtime 不得改变漫画源 SDK 的业务语义。
