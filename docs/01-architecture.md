# 系统架构

## 1. 架构原则

- 本地优先：数据库和文件系统是用户状态的唯一持久来源。
- 能力隔离：JavaScript 源只描述内容访问规则，不进入 UI、下载调度或文件系统。
- 单向依赖：表现层依赖用例和领域接口，基础设施实现领域端口。
- 可取消：搜索、解析、下载和图片解码均携带取消语义。
- 可替换：JS 引擎、数据库 ORM 和 HTTP 库通过适配器隔离。
- 渠道能力显式化：发行差异通过编译期 capability 控制，不能依赖隐藏开关。

## 2. 逻辑分层

```text
Flutter Views
    |
ViewModels / UI State
    |
Application Use Cases
    |
Domain Models + Ports
    |
Repositories
    +-- SQLite Service
    +-- File Store
    +-- Source Runtime Adapter
    +-- Network Adapter
    +-- Background Download Adapter
```

### 表现层

包含书架、发现/搜索、详情、阅读器、下载、独立 JS 源管理和设置页面。主界面的“JS 源”与“设置”是并列按钮，源管理不得嵌入设置页或由设置页作为唯一入口。View 只处理布局与交互，ViewModel 管理页面状态、调用用例并将错误转换为可展示状态。

### 应用层

主要用例：

- `InstallSource`
- `DownloadSourceFromUrl`
- `SearchAcrossSources`
- `LoadMangaDetails`
- `RefreshChapters`
- `AddToLibrary`
- `CreateLibraryDownloadBatch`
- `OpenReader`
- `SaveReadingProgress`
- `EnqueueChapterDownload`
- `ReconcileDownloads`

用例负责事务边界与跨仓储编排，不包含 Flutter Widget、SQLite SQL 或 QuickJS API。

### 领域层

定义实体、值对象、错误类型和端口。领域层不得依赖 Flutter、平台 SDK、数据库包或 QuickJS。

### 基础设施层

实现 SQLite、文件、HTTP、JS 沙箱、图片缓存和平台后台任务。所有外部输入在此层转成经过校验的领域对象。

## 3. 运行时组件

```text
SourceManager
  -> PackageVerifier
  -> PermissionStore
  -> SourceRuntimePool
       -> QuickJS Runtime (one source invocation context)
       -> Host API Gateway
            -> SourceHttpClient
            -> Html/JSON Parser
            -> SourceScopedStorage

ReaderCoordinator
  -> PageRepository
  -> ImageCache
  -> ProgressRepository

DownloadCoordinator
  -> DownloadQueue
  -> Android WorkManager Adapter
  -> iOS Background URLSession Adapter
  -> AtomicFileStore
```

## 4. 进程与并发模型

- Flutter UI isolate 只做状态协调和轻量转换。
- QuickJS 在专用原生工作线程中执行；每次调用都有超时、内存上限和取消令牌。
- HTML 解析、哈希计算和大 JSON 解码在后台 isolate/线程执行。
- 下载由平台后台机制持久化；前台 UI 通过数据库观察状态。
- 同一源最多 4 个 HTTP 请求，全局最多 12 个；具体值由设置向下调整，不允许源自行提高。
- 同一章节只存在一个活动下载任务，重复请求复用任务 ID。

## 5. 源调用序列

```text
发现页提交漫画名称
   -> SearchAcrossSources
   -> 快照所有已安装且已启用的 SourceInstallation
   -> 为每个源创建独立搜索任务
       -> SourceRuntimePool
       -> 创建受限 QuickJS Context
       -> 校验 SearchRequest
       -> 调用对应 source.search()
       -> JS 通过 Host API 发起 HTTP
       -> 校验域名、协议、重定向与配额
       -> 校验 JS 返回 Schema
       -> 附加 sourceId/sourceVersion
       -> 逐源流式返回发现页

用户点击某一 SourceSearchResult
   -> 使用 sourceId 定位同一个已安装且已启用源
   -> 以 MangaRef 调用该源 getMangaDetails()
   -> 以详情结果调用该源 getChapters()
   -> 写入/更新 SourceManga 与 Chapter
   -> 展示详情和章节
```

JS 对象不得跨调用长期持有。需要持久化的内容只能通过源级键值存储或标准返回对象进入宿主。

搜索结果路由使用 `(sourceId, sourceMangaId)`，不能只传标题或 URL。结果点击后的详情调用不重新执行 `search`，也不能由聚合层猜测另一个源中的对应作品。详细状态机见 [JS 源发现与详情流程](11-source-discovery-flow.md)。

### 5.1 通过 URL 添加 JS 源

```text
主界面点击“JS 源”（位于“设置”按钮侧）
   -> 源管理页点击“通过 URL 添加”
   -> 输入 HTTPS .js URL
   -> DownloadSourceFromUrl 下载到应用临时目录
   -> 校验 URL、重定向、响应大小、编码和 SHA-256
   -> 在禁用网络 Host API 的沙箱中预加载模块并读取 Manifest
   -> 校验 sourceApiVersion、导出、权限和域名
   -> 向用户展示来源 URL、Manifest、权限和签名状态
   -> 用户确认
   -> 原子保存本地副本并登记 SourceInstallation
   -> 加载已安装的本地副本
```

远端响应不能直接进入正式运行池。下载、验证、确认和安装是四个独立阶段；任一阶段失败都清理临时文件且不改变当前活动源。

### 5.2 详情加入书架与书架批量下载

```text
JS 源漫画详情页点击“添加到书架”
   -> AddToLibrary(sourceId, sourceMangaId, detailsSnapshot)
   -> 幂等创建/复用 Manga、SourceManga、LibraryEntry
   -> UI 切换为“已加入书架”

书架长按或点击“批量选择”
   -> 勾选多个 LibraryEntry
   -> 点击“下载”
   -> CreateLibraryDownloadBatch(libraryEntryIds, scope)
   -> 刷新/校验各作品章节清单
   -> 排除已完成下载并生成确认摘要
   -> 用户确认
   -> 创建 DownloadBatch 和多个 Chapter DownloadTask
   -> 下载页观察批次及单任务状态
```

详情页按钮不得直接向 JS 源写入“书架”状态；书架是宿主本地领域。批量选择只保存本地 `libraryEntryId`，不能依赖列表位置、标题或当前排序。

## 6. 错误模型

统一错误类别：

| 类别 | 示例 | UI 行为 |
|---|---|---|
| `SourceInvalid` | 缺少导出、Schema 错误 | 禁用源并显示修复信息 |
| `SourcePermissionDenied` | 未声明域名、HTTP、私网 | 阻断并记录安全事件 |
| `SourceTimeout` | JS 或网络超时 | 单源重试 |
| `SourceChanged` | 选择器失效、返回空结构 | 提示源可能失效 |
| `NetworkUnavailable` | 断网、DNS 失败 | 保留缓存并允许重试 |
| `StorageFull` | 空间不足 | 暂停队列，提示清理 |
| `DataCorrupt` | 哈希不符、数据库损坏 | 隔离文件，尝试恢复 |
| `Cancelled` | 用户取消、页面离开 | 静默结束，不计为失败 |

错误日志必须包含 `operationId`、`sourceId`、阶段和脱敏原因，不包含 Cookie、完整响应正文或下载图片。

## 7. 推荐工程结构

```text
lib/
  app/
  features/
    library/
    discovery/
    manga_detail/
    reader/
    downloads/
    sources/
    settings/
  application/
  domain/
  infrastructure/
    database/
    files/
    network/
    source_runtime/
    background/
packages/
  source_runtime_native/
    android/
    ios/
    src/
test/
integration_test/
fixtures/
  sources/
  html/
docs/
```

## 8. 依赖选择规则

- Flutter 与第三方包采用实施时的稳定版，不在规范阶段锁死未来版本号。
- 关键依赖必须有活跃维护、明确许可证、Android/iOS 支持和可自动化测试能力。
- QuickJS 通过自有窄 C ABI 封装，Dart 不直接绑定其全部 API。
- 更换库不得改变领域接口和源 SDK 协议。
- 依赖升级必须通过源兼容、数据库迁移、后台下载和阅读器回归测试。
