# JS 源发现与详情流程

> 实现状态：漫蛙 JS 源已按本文契约接入；后续新增来源仍需遵循相同的 requestId、来源快照与详情/章节路由规则。

状态：已确认、待后续实现  
适用范围：安装 JS 源后的发现、搜索结果和漫画详情导航

本文定义未来接入 JS 漫画源时的端到端交互契约。当前 MVP 仍使用固定测试内容，不在本次文档修改中启用 QuickJS 或网络源。

## 1. 用户流程

```text
用户点击主界面中位于“设置”按钮侧的独立“JS 源”按钮
  -> 在源管理页通过 HTTPS URL 下载、校验并安装一个或多个 JS 源
  -> 启用源
  -> 打开“发现”页
  -> 输入漫画名称并提交
  -> 宿主把相同名称分别传给所有已启用源的 search()
  -> 每个源独立搜索并返回 MangaRef 列表
  -> 发现页逐源展示结果和状态
  -> 用户点击某个结果
  -> 宿主根据 sourceId 找回产生该结果的同一个 JS 源
  -> 调用 getMangaDetails(ref)
  -> 调用 getChapters(details)
  -> 展示漫画详情和章节列表
```

点击结果后的“获取具体信息”是调用对应源的详情接口，不是再次执行关键词 `search`。这样可以避免搜索排序变化、同名作品混淆和跨源数据误用。

“JS 源”不属于设置页。设置页只管理普通应用偏好；源的 URL 安装、权限、启停、版本和错误状态全部位于独立源管理页。

## 2. 参与条件

一次聚合搜索只选择同时满足以下条件的源：

- 已成功安装；
- 用户已启用；
- Manifest 声明 `search` capability；
- `sourceApiVersion` 与宿主兼容；
- 当前构建渠道允许执行该源。

宿主在搜索开始时生成来源快照。本次搜索过程中新增或启用的源不自动加入；用户再次提交才生效。中途被禁用或删除的源应取消尚未完成的任务，并保留已返回结果的来源标记。

## 3. 请求与结果模型

```typescript
interface DiscoverySearchRequest {
  requestId: string;
  keyword: string;
  sourceIds: string[];
  filtersBySource?: Record<string, Record<string, Json>>;
}

interface SourceSearchResult {
  resultKey: string;          // sourceId + sourceMangaId 的无歧义编码
  requestId: string;
  sourceId: string;
  sourceVersion: string;
  manga: MangaRef;
}

interface MangaDetailsRoute {
  sourceId: string;
  sourceVersion: string;
  sourceMangaId: string;
  mangaRefSnapshot: MangaRef;
}
```

约束：

- `resultKey` 必须在当前结果集中唯一，不能只使用标题或 URL。
- `manga.id` 是 `sourceMangaId`，由源生成并在该源内稳定。
- `sourceId` 和 `sourceVersion` 由宿主附加，不信任 JS 自行填写。
- `mangaRefSnapshot` 只包含经过 Schema 校验的 JSON 数据，不持有 JS 或原生对象句柄。
- UI、路由和缓存都使用 `resultKey`；标题仅用于展示。

## 4. 发现页搜索规则

### 4.1 输入

- 提交前去除首尾空白，但不改变中间字符、大小写、简繁体或语言。
- 空字符串不调用源；关键词上限为 128 个 Unicode 字符。
- 新搜索会取消上一次仍在进行的聚合任务。
- 键入建议可使用 350–500 ms 防抖，但只有显式提交或防抖完成后才建立新的 `requestId`。

### 4.2 分发

`SearchAcrossSources` 为每个参与源创建独立调用：

```javascript
source.search({
  keyword,
  cursor: null,
  filters: filtersForThisSource
})
```

每个源遵守自身速率限制和宿主全局并发限制。聚合器不得把一个源的过滤器传给另一个源，也不得因某一源失败而取消其他源。

### 4.3 返回与展示

每个源有独立状态：

```text
idle -> searching -> success | empty | failed | timedOut | cancelled
```

- 结果按到达顺序逐步显示，用户无需等待全部源结束。
- 每个结果必须显示来源名称；源语言和更新时间存在时一并显示。
- 同名结果保持独立，不自动合并。
- 分页游标属于具体源；加载更多只调用该源，不重新搜索其他源。
- 单源重试只重试该源并沿用当前关键词；新结果仍绑定当前 `requestId`。
- 旧 `requestId` 的迟到结果必须丢弃，不能污染新搜索。

## 5. 点击结果与详情加载

用户点击结果时：

1. 使用 `sourceId` 查询当前 `SourceInstallation`；
2. 确认源仍存在、已启用且 API 兼容；
3. 立即进入详情页，并用 `mangaRefSnapshot` 显示标题、封面等已有摘要；
4. 将同一个 `mangaRefSnapshot` 传给对应源的 `getMangaDetails`；
5. 校验详情返回值并更新 `SourceManga`；
6. 将详情结果传给同一源的 `getChapters`；
7. 校验、规范化并持久化章节，逐步更新详情页。
8. 详情页显示“添加到书架”；点击后由宿主以 `(sourceId, sourceMangaId)` 幂等写入本地书架。

```text
SourceSearchResult
  -> SourceManager.requireEnabled(sourceId)
  -> source.getMangaDetails(mangaRefSnapshot)
  -> validate MangaDetails
  -> source.getChapters(details)
  -> validate Chapter[]
  -> render/persist
```

详情与章节可以分阶段展示。详情成功而章节失败时保留详情，章节区域提供重试；重试只重新调用当前源的 `getChapters`。

“添加到书架”不是 JS SDK 函数。源只提供作品与章节数据；书架按钮、已加入状态、移出书架和后续批量下载全部由宿主管理。完整规则见 [书架与批量下载流程](12-library-batch-download.md)。

## 6. 源变化与失效

- 源已禁用：不自动执行，提示用户启用该源或返回搜索结果。
- 源已删除：保留摘要快照，提示来源不可用；不切换到同名源。
- 源版本已升级：使用当前活动版本尝试解析稳定 ID；失败时提示结果可能已过期，并提供“使用当前源重新搜索”。
- `sourceMangaId` 不存在：标记为失效结果，不根据标题猜测替代作品。
- 详情 Schema 错误：记录脱敏源错误，不把未校验对象写入数据库。
- 网络或超时：显示当前源错误并允许重试，不返回发现页重新聚合。

## 7. 状态与取消

发现页离开或提交新关键词时取消旧搜索。详情页离开时取消尚未完成的详情/章节调用，但已通过验证并成功写入的缓存可以保留。

UI 更新必须同时核对 `requestId`、`sourceId` 和页面生命周期，避免迟到异步结果覆盖当前页面。

## 8. 缓存

搜索缓存键建议为：

```text
SHA256(sourceId + sourceVersion + normalizedKeyword + cursor + filters)
```

详情缓存键为 `(sourceId, sourceVersion, sourceMangaId)`。缓存只能改善体验，不能改变来源路由；缓存过期后仍调用原源刷新。

## 9. 隐私与日志

搜索词会发送给用户启用的第三方源站。首次启用源时应说明其域名会收到搜索请求。

日志允许记录 `requestId`、`sourceId`、阶段、耗时和错误类别；默认不记录完整关键词、Cookie、响应正文或含敏感查询参数的 URL。

## 10. 验收条件

- 安装并启用两个测试源后，提交一次名称会分别调用两个源的 `search`。
- 一个源超时或返回空列表时，另一个源的结果正常出现。
- 搜索结果显示来源，且具有唯一 `(sourceId, sourceMangaId)`。
- 点击源 A 的结果只调用源 A 的 `getMangaDetails` 和 `getChapters`。
- 点击结果不会再次调用任何源的 `search`。
- 两个源返回同名漫画时保持两条独立结果。
- 新搜索开始后，旧请求的迟到结果不会进入当前页面。
- 源被禁用、删除或升级后点击旧结果会显示本文规定的可恢复状态。
- 详情成功而章节失败时，详情仍可见且章节可单独重试。
- 详情页“添加到书架”重复点击不产生重复记录，成功后显示“已加入书架”。
