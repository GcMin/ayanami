# 领域模型与本地数据

## 1. 标识规则

- `sourceId`：反向域名风格、小写、安装后不可变。
- `sourceMangaId`、`sourceChapterId`：由源生成，在该源内稳定。
- 本地实体 ID：UUID v7 或等价的时序 UUID，由宿主生成。
- 不使用标题、URL 或章节序号作为本地主键。
- URL 可变化；源 ID 与源内 ID 的组合才是远端身份。

## 2. 核心实体

```text
SourceInstallation
  sourceId, version, manifest, packageHash, signatureState,
  grantedPermissions, enabled, installedAt

Manga
  id, preferredTitle, coverRef, createdAt, updatedAt

SourceManga
  id, mangaId, sourceId, sourceMangaId, url,
  title, metadataJson, lastFetchedAt

Chapter
  id, sourceMangaId, sourceChapterId, title,
  chapterNumber, volumeNumber, language, publishedAt, sortKey

Page
  id, chapterId, pageIndex, remoteDescriptorJson,
  width, height, mimeType, localFileId

LibraryEntry
  mangaId, preferredSourceMangaId, addedAt,
  lastCheckedAt, unreadCount

ReadingProgress
  mangaId, chapterId, pageIndex, pageOffset,
  completed, updatedAt

DownloadBatch
  id, origin, scope, state, selectedMangaCount,
  totalChapterCount, completedChapterCount, createdAt, updatedAt

DownloadTask
  id, batchId?, chapterId, state, priority, constraints,
  attemptCount, errorCode, createdAt, updatedAt

LocalFile
  id, relativePath, sizeBytes, sha256, mimeType, state
```

## 3. 建议数据库表

| 表 | 关键约束 |
|---|---|
| `source_installation` | PK `source_id`; 唯一活动版本 |
| `source_permission` | PK `(source_id, permission, scope)` |
| `source_kv` | PK `(source_id, key)`；值与总容量受限 |
| `manga` | PK `id` |
| `source_manga` | UNIQUE `(source_id, source_manga_id)` |
| `chapter` | UNIQUE `(source_manga_id, source_chapter_id)` |
| `page` | UNIQUE `(chapter_id, page_index)` |
| `library_entry` | PK `manga_id` |
| `reading_progress` | PK `manga_id` |
| `reading_history` | 按 `opened_at` 建索引 |
| `download_batch` | 批量操作的汇总状态；`origin = library_multi_select` |
| `download_task` | 对活动状态建立索引 |
| `download_item` | UNIQUE `(task_id, page_id)` |
| `local_file` | UNIQUE `relative_path`; `sha256` 建索引 |
| `reader_preference` | 作品级设置覆盖全局设置 |
| `image_cache_entry` | 图片缓存键、相对路径、大小、访问时间和来源页；支持 LRU |
| `schema_meta` | 数据库版本与迁移状态 |

外键默认启用。删除 `source_installation` 不级联删除 `manga`、下载文件和阅读进度；仅将相关 `source_manga` 标记为不可刷新。

## 4. 多源作品关系

首版行为：

- 从搜索结果收藏时创建一个 `Manga` 和一个 `SourceManga`。
- 用户可在详情页执行“关联其他来源”。
- 关联操作只合并书架展示，不合并章节 ID。
- 阅读进度绑定本地 `Manga`，同时记录实际 `chapterId`。
- 切换来源后，不通过章节标题猜测精确对应页；仅按用户选择或显式章节编号定位。

自动同名合并属于非目标，避免误把重名作品或不同版本合并。

## 4.1 加入书架

- 详情页以 `(sourceId, sourceMangaId)` 查找或创建 `SourceManga`，再创建或复用 `LibraryEntry`。
- 同一来源作品重复点击“添加到书架”不得创建重复记录。
- 按钮状态由本地 `LibraryEntry` 决定，不调用 JS 源保存收藏状态。
- 加入时保存已验证的详情和章节快照；离线时仍可展示最后一次成功数据。
- 移出书架不默认删除下载或阅读进度，继续遵循本文的数据保留规则。

## 4.2 书架批量选择

- 选择集合存储 `libraryEntryId`，不使用列表索引；排序、筛选或局部刷新后选择必须保持正确。
- 批量下载创建一个 `DownloadBatch`，每个选中漫画展开为若干章节级 `DownloadTask`。
- `DownloadBatch` 是汇总和控制边界，不把所有漫画写入一个不可恢复事务。
- 同一章节已有活动任务时复用该任务并关联到批次；已完成章节默认从“未下载章节”范围中排除。

## 4.3 阅读器偏好与章节缓存

`reader_preference` 至少保存：

```text
scope                  global | manga
mangaId                作品级时必填
scaleMode              originalSize | fitWidth | fitHeight | fitScreen | smartFit
readingDirection
minScale/maxScale/doubleTapScale
pageSpacingDp
cropMode
readAheadEnabled
readAheadNextPageCount 默认 5，允许 1..20
allowMeteredReadAhead   默认 false
updatedAt
```

本次会话设置只存在内存，不写表。作品级记录覆盖全局记录，JS 源无权读写这些偏好。

`image_cache_entry` 记录 `sourceId`、`chapterId`、`pageIndex`、缓存键、相对路径、大小、最后访问时间和验证状态。缓存记录不能替代 `LocalFile` 的正式下载引用，也不能使章节被标记为离线完成。

## 5. 章节排序

源返回顺序不可信。宿主保存源顺序，并计算用于展示的 `sortKey`：

1. 有卷号和章节号时按数值排序；
2. 只有章节号时按章节号；
3. 无法解析时使用源返回顺序和发布时间；
4. 番外、0.5 话和重复修订不得因浮点转换丢失，原始标签始终保留。

`chapterNumber` 使用十进制定点字符串或可空 decimal，不使用二进制浮点作为身份。

## 6. 页面描述与延迟解析

`Page.remoteDescriptorJson` 可保存 URL、请求头、页面 URL、过期时间和源自定义 JSON，但不得保存 Cookie。若 URL 会过期，下载/阅读前调用源的 `resolvePageRequest` 重新解析。

图片成功落盘后写入 `LocalFile`，再在同一事务中关联 `Page.localFileId`。数据库不得指向 `.part` 临时文件。

## 7. 状态机

下载任务：

```text
queued -> resolving -> downloading -> verifying -> completed
   |          |             |             |
   +--------> paused <------+-------------+
   +--------> failed <------+-------------+
   +--------> cancelled
```

- `completed`、`cancelled` 为终态；重新下载创建新 attempt 或新任务。
- `failed` 可以重试；保留错误码与已完成页面。
- 应用启动时把无平台任务对应的 `resolving/downloading/verifying` 恢复为 `queued` 或 `paused`。

本地文件状态：

```text
pending -> ready -> missing | quarantined -> deleted
```

## 8. 数据迁移与备份

- 每次数据库结构变化必须提供向前迁移和迁移测试夹具。
- 破坏性迁移前创建数据库备份；内容图片不重复复制。
- 迁移失败时保留原数据库并启动只读恢复界面，不自动清空数据。
- 用户设置、书架、历史和下载索引支持导出为版本化 JSON；源包和漫画图片单独处理。

## 9. 数据保留

- 删除书架项默认不删除下载，需二次选择。
- 删除章节下载只删除应用管理的内容目录文件。
- 删除源保留其包哈希、历史版本和安全事件 30 天，便于诊断；用户可立即彻底清除。
- 日志采用容量轮转，不长期积累网络记录。
