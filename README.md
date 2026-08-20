# Ayanami 漫画阅读器

Ayanami 是一款 Android 优先、兼容 iOS 的本地优先漫画阅读器。应用不提供账号、登录、云同步、OCR 或翻译服务，也不内置内容目录；用户自行安装漫画源，应用在受限 JavaScript 沙箱中执行漫画源规则，完成检索、章节解析、在线阅读和本地下载。

当前仓库已包含首个 Android MVP：使用本地固定 fixture 内容验证发现、详情、书架、阅读器、下载状态和重启恢复闭环。漫画源 JS、QuickJS、`.js/.msrc` 导入和远程源暂未启用，范围见 [MVP 范围决策](docs/10-mvp-scope.md)。

## 已确定的产品边界

- Android 10（API 29）及以上，iOS 16 及以上。
- Flutter UI；QuickJS 原生沙箱；SQLite 本地数据库。
- 无应用账号、无内容站点登录流程、无自有后端、无遥测云服务。
- 无 OCR、AI 翻译、端侧模型和云端模型。
- 网络只用于获取用户指定的源包、源站元数据与漫画图片。
- 开发期允许导入单个 `.js`；正式分发格式为带 Manifest 和签名信息的 `.msrc`。
- 完整版支持用户导入 JavaScript 源；应用商店版按渠道审核规则裁剪能力。
- “JS 源”是与“设置”并列的独立入口，不放入设置页；用户可在该入口输入 HTTPS URL 下载、校验并加载单个 `.js` 源。

## 当前 MVP

- Flutter Android 工程，目标 Android 10+。
- 内置 3 部固定测试漫画，不访问网络、不执行 JS。
- 支持搜索、详情、收藏到书架、纵向阅读、适应宽度/基础缩放。
- 支持本地保存章节页码、下载进度和已完成下载状态；重启后恢复。
- 下载当前是用于闭环验证的本地状态模拟，SQLite/原子文件/WorkManager 属于后续里程碑。

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
12. [JS 源发现与详情流程](docs/11-source-discovery-flow.md)
13. [书架与批量下载流程](docs/12-library-batch-download.md)

## 文档优先级

发生冲突时，按以下顺序解释：

1. `00-product-requirements.md` 中的产品范围和非目标；
2. `09-decisions.md` 中已接受的架构决策；
3. 各模块规范中的接口和验收条件；
4. `README.md` 的摘要。

任何新增能力必须先更新产品范围和相应决策记录，再进入实现。
