# Ayanami 漫画阅读器

Ayanami 是一款 **Android 优先的本地漫画阅读器**，产品体验参考 Suwayomi 的“书架 + 多漫画源 + 本地阅读”思路，但不依赖独立服务端。

应用本身不提供漫画内容。用户通过 **JavaScript 漫画源插件**添加可访问的数据源，由宿主统一完成搜索、详情、章节、阅读、缓存与下载。

## 首页结构

应用启动后直接进入首页，底部仅保留三个一级入口：

1. **书架**：默认首页，展示已收藏漫画、阅读进度、未读章节与本地下载状态。
2. **漫画源**：管理 JS 插件，并在已启用漫画源中进行浏览、搜索和发现。
3. **设置**：管理阅读器、下载、缓存、外观、诊断等应用级偏好。

“发现/搜索”不再作为独立一级入口，而属于“漫画源”页面的内容发现能力。

## JavaScript 漫画源

漫画源采用 JavaScript 插件形式。每个源负责把某个站点或内容服务转换为宿主标准模型。

当前目标接口：

```text
search()
getMangaDetails()
getChapters()
getPages()

可选：
getPopular()
getLatest()
getFilters()
```

宿主负责：

- 网络权限与域名限制；
- JS 运行时隔离；
- 搜索结果聚合；
- 书架与阅读进度；
- 图片加载、缓存与下载；
- 源安装、启停、更新和错误诊断。

漫画源不得直接操作 Flutter UI、应用数据库、任意文件系统或平台原生 API。

## 当前实现状态

仓库目前已经具备首个 Android 原型：

- Flutter Android 客户端；
- 书架、详情、章节与阅读器基础流程；
- `flutter_js` 驱动的 JS 源原型；
- 已有真实源适配代码用于验证搜索、详情与章节链路；
- 本地阅读进度与缓存的早期实现。

需要注意：**当前代码中的 JS 运行时属于过渡实现**。目标架构仍要求通过受限 Host API、权限校验和源级隔离执行 JS，而不是允许脚本直接拥有任意网络或系统能力。

## 产品边界

- 主平台：Android 10（API 29）及以上。
- iOS 保留未来兼容可能，但不作为当前 MVP 验收目标。
- Flutter UI，本地优先，无自有后端。
- 本地结构化状态最终使用 SQLite/Drift。
- 漫画源使用 JavaScript，不使用 APK/DEX/JAR/原生动态插件。
- 不提供应用账号、云同步、OCR、AI 翻译或内容站自动登录。
- 不绕过 DRM、验证码、付费墙或访问控制。

## 文档导航

1. [产品需求与范围](docs/00-product-requirements.md)
2. [系统架构](docs/01-architecture.md)
3. [领域模型与本地数据](docs/02-domain-and-data.md)
4. [JavaScript 漫画源 SDK](docs/03-source-sdk.md)
5. [阅读器规范](docs/04-reader.md)
6. [下载与文件存储](docs/05-download-and-storage.md)
7. [安全与发行](docs/06-security-and-distribution.md)
8. [测试与验收](docs/07-testing-and-acceptance.md)
9. [实施路线图](docs/08-roadmap.md)
10. [架构决策记录](docs/09-decisions.md)
11. [当前 MVP 范围](docs/10-mvp-scope.md)
12. [漫画源发现与详情流程](docs/11-source-discovery-flow.md)
13. [书架与批量下载流程](docs/12-library-batch-download.md)

## 文档优先级

发生冲突时按以下顺序解释：

1. `00-product-requirements.md` 的产品范围；
2. `09-decisions.md` 的已接受架构决策；
3. 各模块规范；
4. `README.md` 摘要。
