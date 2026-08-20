# JavaScript 漫画源 SDK 规范

规范版本：`sourceApiVersion = 1`  
状态：MVP 必须实现

## 1. 设计目标

一个源负责把其声明域名中的内容转换为宿主标准模型。源可以完成搜索、列表、详情、章节和图片请求描述，但不能访问 UI、任意网络、任意文件或平台 API。

源不是浏览器扩展，也不是 Node.js 包。宿主实现一个明确的 ECMAScript 子集和少量异步 Host API；任何未在本文定义的全局对象都视为不可用。

## 2. 分发格式

### 2.1 开发格式

开发者模式允许从本地文件或用户输入的 HTTPS URL 导入一个 UTF-8 编码的 `.js` 文件。宿主从其 `manifest` 导出读取清单。开发源始终标记为“未签名”，升级必须再次确认。

通过 URL 导入时，宿主必须先将响应下载到隔离临时文件，再进行结构校验和无网络预加载；用户确认安装后才把不可变本地副本加入运行时。禁止把远端 URL 当作每次调用时动态加载的模块地址。

### 2.2 正式格式

`.msrc` 是 ZIP 容器：

```text
example.msrc
  manifest.json
  source.js
  icon.png          # 可选，PNG/WebP，最大 256 KiB
  README.md         # 可选，最大 128 KiB
  signature.json    # 可选；正式仓库应提供
```

约束：

- 包最大 2 MiB，解压后最大 8 MiB，文件数不超过 16。
- 禁止绝对路径、`..`、符号链接、重复规范化路径和 ZIP bomb。
- `source.js` 最大 1 MiB；仅允许 UTF-8 文本。
- `manifest.json` 与 JS 导出的 `manifest` 必须语义相同；不一致则拒绝安装。
- 包哈希为规范化条目清单及内容计算的 SHA-256，不能依赖 ZIP 时间戳。

## 3. Manifest

```json
{
  "id": "org.example.reader",
  "name": "Example Source",
  "version": "1.2.0",
  "sourceApiVersion": 1,
  "minAppVersion": "1.0.0",
  "languages": ["zh-CN"],
  "baseUrl": "https://example.org",
  "author": "Source Author",
  "description": "Example only",
  "contentRating": "general",
  "capabilities": ["search", "popular", "latest"],
  "permissions": ["network", "cookies", "sourceStorage"],
  "domains": ["example.org", "cdn.example.org"],
  "rateLimit": {
    "requests": 4,
    "periodMs": 1000
  }
}
```

### 3.1 字段规则

| 字段 | 要求 |
|---|---|
| `id` | 必填；`^[a-z0-9]+([.-][a-z0-9-]+)+$`；最长 128 |
| `name` | 必填；1–80 个 Unicode 字符 |
| `version` | 必填；SemVer，不接受构建元数据决定升级顺序 |
| `sourceApiVersion` | 必填；整数；宿主仅运行支持的主版本 |
| `languages` | 至少一项 BCP 47 语言标签 |
| `baseUrl` | 必填 HTTPS URL；主机必须在 `domains` 中 |
| `capabilities` | 与实际导出一致 |
| `permissions` | 只能取宿主已知枚举值 |
| `domains` | 1–32 个精确域名或受限子域通配符 |
| `rateLimit` | 只能比宿主全局限制更严格 |

`contentRating` 为 `general`、`mature` 或 `adult`。该字段只用于提示和过滤，不能替代渠道政策或法律判断。

### 3.2 域名匹配

- `example.org` 只匹配该主机。
- `*.example.org` 匹配子域，但不匹配裸域。
- 禁止 `*`、公共后缀、IP 网段、端口通配符和 Unicode 混淆域名。
- 安装时将 IDN 规范化为 ASCII/Punycode 并展示原始值与规范值。
- 每次请求和每个重定向跳转都重新校验解析后的目标。

## 4. 模块与导出

源使用 ES Module 语义：

```javascript
export const manifest = { /* 与 manifest.json 相同 */ };

export async function search(query) {}
export async function getMangaDetails(ref) {}
export async function getChapters(manga) {}
export async function getPages(chapter) {}

// 可选
export async function getPopular(request) {}
export async function getLatest(request) {}
export async function getFilters() {}
export async function resolvePageRequest(page, context) {}
export async function initialize() {}
export async function dispose() {}
```

禁止或不提供：

```text
require, process, window, document, fetch, XMLHttpRequest,
WebSocket, Worker, SharedArrayBuffer, WebAssembly,
eval, Function, dynamic import, native modules,
任意文件 API、系统时间修改和平台 API
```

`Date.now()` 可用但不是安全时间源。随机数只用于源内部临时值，不得作为远端稳定 ID。

## 5. 标准数据类型

以下 TypeScript 仅用于描述协议：

```typescript
type Json = null | boolean | number | string | Json[] | { [key: string]: Json };

interface MangaRef {
  id: string;
  title: string;
  url?: string;
  coverUrl?: string;
  subtitle?: string;
  latestChapter?: string;
  updatedAt?: string;       // ISO 8601
  extra?: Record<string, Json>;
}

interface MangaDetails extends MangaRef {
  alternativeTitles?: string[];
  authors?: string[];
  artists?: string[];
  description?: string;
  tags?: string[];
  status?: "unknown" | "ongoing" | "completed" | "hiatus" | "cancelled";
}

interface Chapter {
  id: string;
  mangaId: string;
  title: string;
  url?: string;
  chapterNumber?: string;
  volumeNumber?: string;
  language?: string;
  publishedAt?: string;
  scanlator?: string;
  extra?: Record<string, Json>;
}

interface Page {
  index: number;
  imageUrl?: string;
  pageUrl?: string;
  headers?: Record<string, string>;
  width?: number;
  height?: number;
  mimeType?: string;
  expiresAt?: string;
  extra?: Record<string, Json>;
}

interface PagedResult<T> {
  items: T[];
  nextCursor?: string;
  hasNextPage: boolean;
}
```

所有字符串、数组深度、对象键数和返回总大小均由宿主限制。`extra` 只能包含 JSON，不能包含函数、循环引用或二进制对象。

## 6. 必需入口

宿主调用顺序固定为：

```text
发现页关键词
  -> 对每个已启用源调用 search()
  -> 用户选择某个 MangaRef
  -> 对产生该结果的同一源调用 getMangaDetails(ref)
  -> 对同一源调用 getChapters(details)
  -> 用户选择章节后调用 getPages(chapter)
```

`MangaRef` 是从搜索跳转至详情的源内引用。源必须返回稳定 `id`；宿主会在结果外附加 `sourceId`，并以二者组成全局路由键。`getMangaDetails` 不应要求宿主重新搜索关键词才能构造参数。

### 6.1 搜索

```javascript
export async function search({ keyword, cursor, filters }) {
  const response = await http.get("/search", {
    query: { q: keyword, cursor: cursor ?? "" }
  });
  const doc = html.parse(response.text());
  return {
    items: doc.selectAll(".item").map((node) => ({
      id: node.attr("data-id"),
      title: node.select(".title").text().trim(),
      url: url.resolve(manifest.baseUrl, node.select("a").attr("href")),
      coverUrl: url.resolve(manifest.baseUrl, node.select("img").attr("src"))
    })),
    hasNextPage: doc.select("a.next") !== null
  };
}
```

空关键词是否允许由源的筛选器声明决定。宿主对用户输入做长度限制，但不改变字符内容；转义责任由 `http` 的 query 编码承担。

### 6.2 详情

```javascript
export async function getMangaDetails(ref) {
  // 返回 MangaDetails
}
```

`ref` 必须是当前源先前返回的 `MangaRef` 快照，至少包含稳定 `id` 和标题，可包含 URL 与 `extra`。宿主点击搜索结果时调用产生该结果的同一源；不得把其他源的 `MangaRef` 传入本函数。

### 6.3 章节

```javascript
export async function getChapters(manga) {
  // 返回 Chapter[]；id 在源内必须稳定
}
```

`manga` 是同一源的 `getMangaDetails` 返回值。详情可先于章节呈现；章节调用失败不得清空已成功加载的详情。

源可以按任意顺序返回，宿主负责显示排序。源不得只用章节标题作为 ID，除非上游确实没有更稳定标识。

### 6.4 页面

```javascript
export async function getPages(chapter) {
  // 返回 Page[]，index 从 0 连续递增
}
```

若图片 URL 需要短期签名，`getPages` 返回描述，`resolvePageRequest` 在实际下载前生成最终请求。

## 7. Host API

源只可访问以下冻结对象：

```text
http       受控网络请求
html       HTML 解析和选择器
json       JSON parse/stringify/query
url        URL 解析、拼接和编码
crypto     SHA-256、HMAC、Base64、Hex
date       ISO 8601 和常见站点日期解析
parser     章节号等纯函数解析
storage    源隔离键值存储
cookies    源隔离 Cookie 操作的受限视图
console    脱敏、限量日志
source     当前 Manifest 与运行上下文只读信息
```

不提供 MD5 以外的弱算法作为安全用途；若兼容站点签名必须提供 MD5，应将 API 标记为 `legacyMd5` 并禁止用于包验证。

## 8. HTTP API

```typescript
interface HttpRequest {
  method: "GET" | "POST" | "HEAD";
  url: string;
  query?: Record<string, string | string[]>;
  headers?: Record<string, string>;
  body?: string | Uint8Array;
  timeoutMs?: number;
  responseType?: "text" | "bytes";
  followRedirects?: boolean;
  useCookies?: boolean;
}

interface HttpResponse {
  status: number;
  finalUrl: string;
  headers: Record<string, string>;
  elapsedMs: number;
  text(): string;
  bytes(): Uint8Array;
}
```

默认与上限：

| 项目 | 默认 | 硬上限 |
|---|---:|---:|
| 网络超时 | 15 秒 | 30 秒 |
| 重定向 | 允许 | 5 次 |
| 单源并发 | 2 | 4 |
| 全局并发 | 8 | 12 |
| 文本响应 | — | 8 MiB |
| 单图片响应 | — | 50 MiB |
| 请求体 | — | 2 MiB |

规则：

- 默认只允许 HTTPS；开发者模式可逐源临时允许 HTTP，并显示持续警告。
- 禁止 loopback、link-local、私网、保留地址、`file:` 和其他协议。
- DNS 解析前后都校验目标地址，防止 DNS rebinding。
- 源不能设置 `Host`、`Content-Length`、`Connection`、代理和系统 Cookie 头。
- Cookie jar 按 `sourceId` 隔离。项目不提供交互式登录；需要认证的源不在支持范围内。
- 响应对象只能在当前 JS 调用中使用，不能跨调用保存原生句柄。

## 9. HTML API

MVP 支持 CSS Selector：元素、ID、类、属性、后代/子代、常用伪类。XPath 可后续扩展，不是 v1 必需能力。

```typescript
interface HtmlDocument {
  select(selector: string): HtmlNode | null;
  selectAll(selector: string): HtmlNode[];
}

interface HtmlNode {
  text(): string;
  ownText(): string;
  html(): string;
  attr(name: string): string | null;
  select(selector: string): HtmlNode | null;
  selectAll(selector: string): HtmlNode[];
}
```

解析器不执行页面脚本、不加载子资源、不创建 WebView。HTML 节点数量和文档深度有上限。

## 10. 源级存储

- 每源最大 1 MiB、最多 256 个键。
- 键最长 128 字节，值必须为 JSON，单值最大 64 KiB。
- 一个源不能读取其他源或应用设置。
- 删除源时由用户选择保留或清除源存储。
- 不应在此保存账号凭据；项目没有登录能力。

## 11. 沙箱资源预算

每次调用建议初始值：

| 资源 | 上限 |
|---|---:|
| QuickJS Runtime 内存 | 64 MiB |
| JS 同步执行时间 | 5 秒 |
| 含宿主异步等待的总时长 | 30 秒 |
| JS 栈深度 | 引擎安全值，禁止无限递归 |
| 单次返回序列化数据 | 4 MiB |
| 日志 | 100 条或 64 KiB |

宿主使用 QuickJS 内存限制和中断处理器强制终止。网络等待不消耗 JS CPU 配额，但计入总时长。超限统一返回可识别错误，不允许源捕获后继续无限运行。

## 12. 安装、升级与回滚

源安装入口位于独立“JS 源”页面，与主界面的“设置”按钮并列；设置页不包含源安装或管理入口。

### 12.1 URL 下载规则

- 用户必须显式输入或粘贴 HTTPS URL；生产构建不接受带用户名/密码、片段或非 HTTPS 协议的 URL。
- 下载请求沿用源包下载专用网络策略：每次重定向重新校验协议、域名和解析后地址，拒绝私网、loopback 和 link-local 地址。
- 单个 `.js` 响应最大 1 MiB，只接受 UTF-8；响应 MIME 应为 JavaScript 或文本类型，未知二进制类型拒绝。
- 下载到随机命名临时文件，计算 SHA-256；不得直接覆盖已安装版本。
- 预加载阶段禁用 `http`、`cookies` 和持久 `storage`，只允许解析模块并读取 Manifest/导出清单。
- 安装确认页展示最终 URL、重定向后的主机、文件哈希、源 ID、版本、权限、域名和未签名风险。
- 用户确认后将内容复制到按 `sourceId/version/hash` 管理的应用私有目录；后续运行只加载该本地副本。
- 再次访问原 URL 只用于用户主动检查或安装更新，不能静默替换正在使用的脚本。

### 12.2 通用安装流程

1. 在临时目录安全解包并校验结构。
2. 校验 Manifest、API 版本、哈希和签名。
3. 比较新旧权限与域名。
4. 在无网络验证模式下加载模块和检查导出。
5. 展示差异并取得用户确认。
6. 原子切换活动版本，保留上一版本供回滚。
7. 首次真实调用失败时允许用户一键回滚。

禁止源自行更新。应用只下载用户确认的源版本，更新索引仅提供可用版本信息。

## 13. 兼容性

- `sourceApiVersion` 主版本不兼容时拒绝运行。
- 新增可选字段时旧宿主必须忽略未知字段；安全相关未知权限必须拒绝。
- 源不得依赖 QuickJS 私有行为或宿主未声明的全局对象。
- SDK 提供命令行验证器和固定 HTML/JSON 夹具，无需真实网站即可回归。

## 14. 最小验收夹具

必须提供：

- 正常静态 HTML 源；
- JSON API 源；
- 分页搜索源；
- 图片 Referer 源；
- 短期图片 URL 源；
- 超时/无限循环恶意源；
- 私网访问与重定向逃逸恶意源；
- ZIP Slip、超大包和权限升级包；
- 返回错误类型、超深对象和重复页面索引的源。
