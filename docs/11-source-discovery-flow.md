# 漫画源发现与详情流程

状态：已确认  
日期：2026-08-20

本文定义“漫画源”一级页面中的浏览、搜索、详情和加入书架流程。

## 1. 页面入口

首页结构固定为：

```text
书架 | 漫画源 | 设置
```

用户点击“漫画源”后进入 `SourcesTab`。该页面同时提供：

- 漫画源管理；
- 单源浏览；
- 单源搜索；
- 多源聚合搜索。

不再存在独立一级“发现”页。

## 2. 漫画源页建议结构

```text
漫画源
  [搜索框：搜索全部已启用源]

  内容发现
    - 最近使用源
    - 已启用源
    - 搜索结果

  源管理
    - 添加 JS 源
    - 已安装源
    - 启用/禁用
    - 更新
    - 删除
    - 错误/权限
```

进入某个源后：

```text
SourceDetailPage
  - 搜索
  - 热门（可选）
  - 最新（可选）
  - 分类/筛选（可选）
```

只有 Manifest 声明对应 capability 时才展示入口。

## 3. 聚合搜索流程

```text
用户在 SourcesTab 输入漫画名称
  -> SearchAcrossSources
  -> 快照当前全部已安装、已启用、支持 search 的源
  -> 对每个源独立调用 search()
  -> 各源独立返回结果
  -> UI 逐步展示
```

每个源状态独立：

```text
idle -> searching -> success | empty | failed | timedOut | cancelled
```

一个源失败不得阻断其他源。

## 4. 请求与结果模型

```typescript
interface DiscoverySearchRequest {
  requestId: string;
  keyword: string;
  sourceIds: string[];
}

interface SourceSearchResult {
  resultKey: string;
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

规则：

- `resultKey` 必须唯一；
- `manga.id` 作为 `sourceMangaId`；
- `sourceId` 由宿主附加；
- UI 不能仅根据标题路由；
- 同名漫画保持独立。

## 5. 输入规则

- 去除首尾空白；
- 空关键词不调用源；
- 关键词最大 128 Unicode 字符；
- 新搜索取消旧搜索；
- 旧 `requestId` 的迟到结果直接丢弃。

## 6. 点击结果

```text
SourceSearchResult
  -> 使用 sourceId 找到产生结果的源
  -> getMangaDetails(mangaRefSnapshot)
  -> getChapters(details)
  -> 展示详情与章节
```

禁止：

```text
点击搜索结果
  -> 再次 search(title)
```

也禁止把源 A 返回的结果交给源 B 解析。

## 7. 漫画详情

详情页至少展示：

- 标题；
- 封面；
- 作者；
- 简介；
- 状态；
- 标签；
- 来源；
- 章节列表；
- 加入书架按钮。

详情可先展示搜索结果中的摘要，再异步补充完整详情和章节。

详情成功、章节失败时：

- 保留详情；
- 章节区域显示错误；
- 允许仅重试 `getChapters()`。

## 8. 加入书架

```text
详情页点击“加入书架”
  -> AddToLibrary(sourceId, sourceMangaId, detailsSnapshot)
  -> 幂等创建/复用 LibraryEntry
  -> UI 显示“已加入书架”
```

漫画源本身不实现收藏接口。

书架状态属于宿主本地数据。

## 9. 单源浏览

若源声明：

```text
popular
latest
filters
```

宿主可调用：

```text
getPopular()
getLatest()
getFilters()
```

这些结果使用与搜索结果相同的来源路由规则。

无论漫画来自搜索、热门还是最新，点击后都必须回到产生该结果的同一源。

## 10. 源变化

### 源被禁用

旧结果仍可显示摘要，但需要网络刷新时提示用户重新启用源。

### 源被删除

书架保留本地快照和已下载内容，不自动切换到同名来源。

### 源升级

使用稳定 `sourceMangaId` 尝试刷新。失败时提示“来源可能已变化”，可提供重新搜索入口。

## 11. 缓存

建议缓存键：

```text
搜索：SHA256(sourceId + sourceVersion + keyword + cursor + filters)
详情：(sourceId, sourceVersion, sourceMangaId)
```

缓存不得改变来源路由规则。

## 12. 验收条件

- 首页进入漫画源页后可进行搜索；
- 安装并启用两个测试源后可聚合搜索；
- 一个源失败时另一个源仍能显示结果；
- 每个结果显示来源；
- 点击源 A 的结果只调用源 A；
- 点击结果不会再次执行关键词搜索；
- 同名结果不自动合并；
- 新搜索开始后旧结果不会污染当前结果；
- 加入书架重复点击不产生重复记录；
- 源被删除后书架本地数据仍保留。
