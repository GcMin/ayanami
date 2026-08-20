// Ayanami sourceApiVersion 1 - 漫蛙示例源。
// 宿主只暴露受限的 JS 运行时；网络请求由 Dart Host API 执行。
const manifest = {
  id: 'com.ayanami.source.manwa',
  name: '漫蛙',
  version: '0.1.0',
  sourceApiVersion: 1,
  languages: ['zh-CN'],
  baseUrl: 'https://manwaqb.cc',
  author: 'Ayanami 示例源',
  description: '从漫蛙搜索漫画并读取公开详情。',
  contentRating: 'mature',
  capabilities: ['search', 'details', 'chapters', 'reader'],
  permissions: ['network'],
  domains: ['manwa.me', 'manwaqb.cc', 'mwappimgs.cc'],
};

function search(input) {
  return { path: '/search', query: { keyword: input.keyword } };
}

function getMangaDetails(ref) {
  return { path: '/book/' + encodeURIComponent(ref.id) };
}

function getChapters(manga) {
  return { path: '/book/' + encodeURIComponent(manga.id) };
}

function getChapterPages(chapter) {
  return { path: '/chapter/' + encodeURIComponent(chapter.id) };
}

function clean(value) {
  return String(value || '')
    .replace(/<br\s*\/?\s*>/gi, ' ')
    .replace(/<[^>]*>/g, ' ')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/\s+/g, ' ')
    .trim();
}

function parseAttributes(tag) {
  const result = {};
  const pattern = /([:\w-]+)\s*=\s*["']([^"']*)["']/g;
  let match;
  while ((match = pattern.exec(tag)) !== null) result[match[1]] = match[2];
  return result;
}

function parseSearch(input) {
  const response = input.response || '';
  const items = [];
  const pattern = /<a[^>]*href=["']\/book\/([0-9]+)["'][^>]*>([\s\S]*?)<\/a>/gi;
  let match;
  const seen = {};
  while ((match = pattern.exec(response)) !== null && items.length < 50) {
    const id = match[1];
    if (seen[id]) continue;
    const body = match[2];
    const image = (body.match(/<img\b([^>]*)>/i) || [null, ''])[1];
    const attrs = parseAttributes(image);
    const title = clean((body.match(/<p[^>]*>([\s\S]*?)<\/p>/i) || [null, attrs.alt || body])[1]);
    seen[id] = true;
    items.push({
      id: id,
      title: title || ('漫蛙漫画 #' + id),
      url: manifest.baseUrl + '/book/' + id,
      coverUrl: attrs['data-src'] || attrs['data-original'] || attrs.src || '',
      subtitle: clean(body).slice(0, 240),
      extra: { source: 'manwa' },
    });
  }
  return { items: items, hasNextPage: /下一页|next-page|page=2/i.test(response) };
}

function parseDetails(input) {
  const response = input.response || '';
  const id = input.id || '';
  const title = clean((response.match(/<h1[^>]*>([\s\S]*?)<\/h1>/i) || [null, ''])[1]);
  const aliases = clean((response.match(/别名：\s*([\s\S]*?)<\/p>/i) || [null, ''])[1]);
  const authors = clean((response.match(/作者：\s*([\s\S]*?)<\/p>/i) || [null, ''])[1]);
  const status = clean((response.match(/更新状态：\s*([\s\S]*?)<\/p>/i) || [null, ''])[1]);
  const latest = clean((response.match(/最新章节：\s*([\s\S]*?)<\/p>/i) || [null, ''])[1]);
  const meta = (response.match(/<meta\b[^>]*name=["']description["'][^>]*>/i) || [''])[0];
  const metaAttrs = parseAttributes(meta);
  const description = clean((metaAttrs.content || '').replace(/^.*漫画简介：/i, ''));
  const cover = (response.match(/<div\s+class=["']detail-main-cover["'][\s\S]*?<img\b([^>]*)>/i) || [null, ''])[1];
  const coverAttrs = parseAttributes(cover);
  return {
    id: String(id),
    title: title || ('漫蛙漫画 #' + id),
    url: manifest.baseUrl + '/book/' + id,
    coverUrl: coverAttrs['data-src'] || coverAttrs['data-original'] || coverAttrs.src || '',
    alternativeTitles: aliases ? aliases.split(/[、,，]/).map(clean).filter(Boolean) : [],
    authors: authors ? authors.split(/[、,，]/).map(clean).filter(Boolean) : [],
    description: description,
    status: /完结|完結/.test(status) ? 'completed' : 'ongoing',
    latestChapter: latest,
    extra: { source: 'manwa', rawStatus: status },
  };
}

function parseChapters(input) {
  const response = input.response || '';
  const mangaId = input.mangaId || '';
  const items = [];
  const pattern = /<a\b([^>]*href=["']\/chapter\/([0-9]+)["'][^>]*)>([\s\S]*?)<\/a>/gi;
  let match;
  const seen = {};
  while ((match = pattern.exec(response)) !== null) {
    const id = match[2];
    if (seen[id]) continue;
    seen[id] = true;
    const title = clean(match[3]);
    if (!title) continue;
    items.push({
      id: id,
      mangaId: String(mangaId),
      title: title,
      url: manifest.baseUrl + '/chapter/' + id,
      chapterNumber: (title.match(/(?:第|话|話)\s*([0-9]+(?:\.[0-9]+)?)/i) || [null, ''])[1],
      language: 'zh-CN',
    });
  }
  // 漫蛙页面通常按正序输出；宿主详情页按最新章节优先展示。
  return items.reverse();
}

function parseChapterPages(input) {
  const response = input.response || '';
  const items = [];
  const pattern = /<img\b([^>]*)>/gi;
  let match;
  const seen = {};
  while ((match = pattern.exec(response)) !== null && items.length < 1000) {
    const attrs = parseAttributes(match[1]);
    const url = attrs['data-r-src'] || attrs['data-original'] || attrs.src || '';
    if (!url || /\/static\/images\//i.test(url) || seen[url]) continue;
    if (!/^https:\/\/(?:mwappimgs\.cc|manwaqb\.cc|manwa\.me)\//i.test(url)) continue;
    seen[url] = true;
    items.push({
      id: String(input.chapterId || items.length + 1),
      url: url,
      index: items.length,
    });
  }
  return items;
}
