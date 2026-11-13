/**
 * HOA 博客列表（RSS 备用）与三校区通知列表。
 */
import { util, xml } from '@kit.ArkTS';
import { http } from '@kit.NetworkKit';
import { webview } from '@kit.ArkWeb';
import { EasCampus } from '../eas/EasSession';

const BASE_URL: string = 'https://today.hit.edu.cn';
const SHENZHEN_URL: string = 'http://info.hitsz.edu.cn';
const WEIHAI_URL: string = 'http://today.hitwh.edu.cn';
const BLOG_LIST_URL: string = 'https://hoa.moe/blog';
const BLOG_FEED_URL: string = 'https://hoa.moe/blog/rss.xml';
const DESKTOP_UA: string =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36';

export class NewsCategory {
  id: string;
  name: string;

  constructor(id: string, name: string) {
    this.id = id;
    this.name = name;
  }
}

export class NewsItem {
  url: string = '';
  title: string = '';
  department: string = '';
  date: string = '';
  /** Blog excerpt; campus notice lists only publish titles. */
  summary: string = '';
  /** Blog tags without the leading "#". */
  tags: string[] = [];
}

export class NewsPage {
  items: NewsItem[] = [];
  ok: boolean = false;
  hasMore: boolean = false;
  message: string = '';
  sourceUrl: string = '';
}

export class NewsService {
  static readonly CATEGORIES: NewsCategory[] = [
    new NewsCategory('blog', '博客'),
    new NewsCategory('10', '通知')
  ];

  static async fetchCategory(categoryId: string, page: number,
    campus: EasCampus = EasCampus.BENBU): Promise<NewsPage> {
    const result: NewsPage = new NewsPage();
    const blog: boolean = categoryId === 'blog';
    if ((!blog && categoryId !== '10') || page < 0 || !Number.isInteger(page)) {
      result.message = '暂时无法获取资讯，请稍后重试';
      return result;
    }
    // The HOA blog list contains all posts; it has no next-page endpoint.
    if (blog && page > 0) {
      result.ok = true;
      return result;
    }
    if (blog) {
      return NewsService.fetchBlogCategory();
    }
    const url: string = NewsService.noticeUrl(campus, page);
    result.sourceUrl = NewsService.noticeUrl(campus, 0);
    const header: Record<string, string> = {
      'User-Agent': DESKTOP_UA,
      'Accept': 'text/html,application/xhtml+xml'
    };
    const request: http.HttpRequest = http.createHttp();
    try {
      if (campus === EasCampus.SHENZHEN) {
        // Only use this site's browser cookies, never the EAS session cookie map.
        const cookie: string = await NewsService.noticeCookie(url);
        if (cookie.length > 0) { header['Cookie'] = cookie; }
      }
      const resp: http.HttpResponse = await request.request(url, {
        method: http.RequestMethod.GET,
        header: header,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 20000,
        usingCache: false
      });
      if (resp.responseCode === 401 || resp.responseCode === 403) {
        result.message = '通知网站需要认证，请打开通知网站完成认证后返回重试';
        return result;
      }
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        result.message = '暂时无法获取资讯，请稍后重试';
        return result;
      }
      const body: string = resp.result === undefined || resp.result === null ? '' : String(resp.result);
      if (/<title[^>]*>[^<]*(?:统一身份认证|用户登录)|<form\b[^>]*action=["'][^"']*authserver\/login/i.test(body)) {
        result.message = '通知网站需要认证，请打开通知网站完成认证后返回重试';
        return result;
      }
      try {
        result.items = NewsService.parseList(body, campus);
        if (campus !== EasCampus.BENBU && result.items.length === 0 &&
          !/暂无(?:通知|信息|内容)|没有相关(?:信息|内容)|(?:共|总共)\s*(?:&nbsp;|<[^>]+>|\s)*0\s*(?:<[^>]+>|\s)*(?:条|记录)/.test(body)) {
          throw new Error('Unrecognized notice list');
        }
      } catch (e) {
        result.message = '暂时无法解析资讯，请稍后重试';
        return result;
      }
      result.ok = true;
      result.hasMore = result.items.length > 0 && NewsService.hasNextPage(body, campus, page);
      if (result.items.length === 0) {
        result.message = '暂无可显示的资讯';
      }
    } catch (e) {
      result.message = '网络异常，请检查网络后重试';
    } finally {
      request.destroy();
    }
    return result;
  }

  private static async fetchBlogCategory(): Promise<NewsPage> {
    const result: NewsPage = new NewsPage();
    try {
      result.items = NewsService.parseBlogList(await NewsService.blogBody(BLOG_LIST_URL, 'text/html'));
    } catch (e) {
      try {
        result.items = NewsService.parseBlogFeed(await NewsService.blogBody(BLOG_FEED_URL,
          'application/rss+xml,application/xml,text/xml'));
      } catch (feedError) {
        result.message = '博客刷新失败，请稍后重试';
        return result;
      }
    }
    result.ok = true;
    if (result.items.length === 0) {
      result.message = '暂无可显示的资讯';
    }
    return result;
  }

  private static async blogBody(url: string, accept: string): Promise<string> {
    const request: http.HttpRequest = http.createHttp();
    try {
      const resp: http.HttpResponse = await request.request(url, {
        method: http.RequestMethod.GET,
        header: { 'User-Agent': DESKTOP_UA, 'Accept': accept },
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: url === BLOG_LIST_URL ? 15000 : 30000,
        usingCache: false
      });
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        throw new Error('Blog request failed');
      }
      return resp.result === undefined || resp.result === null ? '' : String(resp.result);
    } finally {
      request.destroy();
    }
  }

  static parseBlogList(html: string): NewsItem[] {
    const items: NewsItem[] = [];
    const seen: Set<string> = new Set<string>();
    const card: RegExp = /<a\b([^>]*)>\s*<span\b[^>]*class=["'][^"']*\bsr-only\b[^"']*["'][^>]*>[\s\S]*?<\/span>\s*<\/a>([\s\S]*?)<time\b([^>]*)>[\s\S]*?<\/time>/gi;
    let match: RegExpExecArray | null = card.exec(html);
    while (match !== null) {
      const path: string = NewsService.attribute(match[1], 'href');
      const titleMatch: RegExpExecArray | null = /<h2\b[^>]*>([\s\S]*?)<\/h2>/i.exec(match[2]);
      const title: string = titleMatch === null ? '' : NewsService.cleanText(titleMatch[1]);
      if (/^\/blog\/[^/?#\s<>]+$/.test(path) && path !== '/blog/tags' && path !== '/blog/rss.xml' &&
        title.length > 0 && !seen.has(path)) {
        const item: NewsItem = new NewsItem();
        item.url = 'https://hoa.moe' + path;
        item.title = title;
        item.department = 'HOA';
        const summary: RegExpExecArray | null = /<p\b[^>]*>([\s\S]*?)<\/p>/i.exec(match[2]);
        item.summary = summary === null ? '' : NewsService.cleanText(summary[1]);
        item.tags = NewsService.blogTags(match[2]);
        const date: string = NewsService.attribute(match[3], 'datetime');
        const dateMatch: RegExpExecArray | null = /^(\d{4}-\d{2}-\d{2})/.exec(date);
        item.date = dateMatch === null ? '' : dateMatch[1];
        seen.add(path);
        items.push(item);
      }
      match = card.exec(html);
    }
    if (items.length === 0) {
      throw new Error('Unrecognized blog list');
    }
    return items;
  }

  /** HOA renders tags as same-site links whose text is "#" + name. */
  private static blogTags(card: string): string[] {
    const tags: string[] = [];
    const links: RegExp = /<a\b([^>]*)>([\s\S]*?)<\/a>/gi;
    let link: RegExpExecArray | null = links.exec(card);
    while (link !== null) {
      const href: string = NewsService.attribute(link[1], 'href');
      const name: string = NewsService.cleanText(link[2]).replace(/^#\s*/, '');
      if (href.startsWith('/blog/tags/') && name.length > 0 && tags.indexOf(name) < 0) {
        tags.push(name);
      }
      link = links.exec(card);
    }
    return tags;
  }

  static noticeUrl(campus: EasCampus, page: number): string {
    if (campus === EasCampus.SHENZHEN) {
      // PAGENUM is one-based. The site's totalpage value changes as notices are published.
      return SHENZHEN_URL + '/list.jsp?PAGENUM=' + (page + 1).toString() +
        '&urltype=tree.TreeTempUrl&wbtreeid=1053';
    }
    if (campus === EasCampus.WEIHAI) {
      return WEIHAI_URL + '/1024/list' + (page > 0 ? (page + 1).toString() : '') + '.htm';
    }
    return BASE_URL + '/category/10' + (page > 0 ? '?page=' + page.toString() : '');
  }

  private static noticeCookie(url: string): Promise<string> {
    return new Promise<string>((resolve) => {
      const timer: number = setTimeout(() => resolve(''), 3000);
      try {
        webview.WebCookieManager.fetchCookie(url).then((value: string) => {
          clearTimeout(timer);
          resolve(value || '');
        }).catch(() => {
          clearTimeout(timer);
          resolve('');
        });
      } catch (e) {
        clearTimeout(timer);
        resolve('');
      }
    });
  }

  private static hasNextPage(html: string, campus: EasCampus, page: number): boolean {
    if (campus === EasCampus.BENBU) { return true; }
    const total: RegExpExecArray | null = campus === EasCampus.WEIHAI ?
      /<em\b[^>]*class=["']all_pages["'][^>]*>\s*(\d+)\s*<\/em>/i.exec(html) :
      /totalpage=(\d+)|共\s*(\d+)\s*页/i.exec(html);
    if (total !== null) { return page + 1 < Number(total[1] || total[2]); }
    // A disabled next link has no HTTP destination; never re-fetch the last page.
    const links: RegExp = /<a\b([^>]*)>([\s\S]*?)<\/a>/gi;
    let match: RegExpExecArray | null = links.exec(html);
    while (match !== null) {
      const href: string = NewsService.attribute(match[1], 'href');
      if ((NewsService.cleanText(match[2]).includes('下页') ||
        NewsService.cleanText(match[2]).includes('下一页')) &&
        (campus === EasCampus.SHENZHEN ? /[?&]PAGENUM=\d+/i.test(href) : /\/1024\/list\d+\.htm/.test(href))) {
        return true;
      }
      match = links.exec(html);
    }
    return false;
  }

  static parseBlogFeed(feed: string): NewsItem[] {
    const data: Uint8Array = new util.TextEncoder().encodeInto(feed);
    const parser: xml.XmlPullParser = new xml.XmlPullParser(data.buffer as ArrayBuffer, 'UTF-8');
    const items: NewsItem[] = [];
    const seen: Set<string> = new Set<string>();
    const path: string[] = [];
    let channelFound: boolean = false;
    let current: NewsItem = new NewsItem();
    let fieldText: string = '';
    parser.parseXml({
      supportDoctype: false,
      ignoreNameSpace: true,
      tokenValueCallbackFunction: (event: xml.EventType, info: xml.ParseInfo): boolean => {
        if (event === xml.EventType.DOCDECL) {
          throw new Error('Unsupported feed document type');
        }
        if (event === xml.EventType.START_TAG) {
          path.push(info.getName());
          if (path.length === 2 && path[0] === 'rss' && path[1] === 'channel') {
            channelFound = true;
          }
          if (path.length === 3 && path[0] === 'rss' && path[1] === 'channel' && path[2] === 'item') {
            current = new NewsItem();
          }
          if (path.length === 4) {
            fieldText = '';
          }
        } else if (event === xml.EventType.TEXT || event === xml.EventType.CDSECT ||
          event === xml.EventType.ENTITY_REFERENCE || event === xml.EventType.WHITESPACE) {
          if (path.length === 4 && path[0] === 'rss' && path[1] === 'channel' && path[2] === 'item' &&
            ['title', 'link', 'pubDate', 'author', 'creator', 'dc:creator', 'description'].includes(path[3])) {
            fieldText += info.getText();
          }
        } else if (event === xml.EventType.END_TAG) {
          if (path[0] === 'rss' && path[1] === 'channel' && path[2] === 'item') {
            if (path.length === 4) {
              const value: string = fieldText.replace(/\s+/g, ' ').trim();
              switch (path[3]) {
                case 'title':
                  current.title = value;
                  break;
                case 'link':
                  current.url = value.startsWith('/blog/') ? 'https://hoa.moe' + value : value;
                  break;
                case 'pubDate':
                  // pubDate holds a date at 00:00 GMT; its UTC date is the post's date in every time zone.
                  const timestamp: number = Date.parse(value);
                  current.date = Number.isFinite(timestamp) ? new Date(timestamp).toISOString().substring(0, 10) : '';
                  break;
                case 'author':
                case 'creator':
                case 'dc:creator':
                  if (value.length > 0) {
                    current.department += (current.department.length > 0 ? '、' : '') + value;
                  }
                  break;
                case 'description':
                  // The excerpt may carry inline markup; keep plain text only.
                  current.summary = NewsService.cleanText(value);
                  break;
              }
            } else if (path.length === 3 && current.title.length > 0 &&
              /^https:\/\/hoa\.moe\/blog\/[^\s<>]+$/.test(current.url) && !seen.has(current.url)) {
              seen.add(current.url);
              if (current.department.length === 0) {
                current.department = 'HOA';
              }
              items.push(current);
            }
          }
          path.pop();
        }
        return true;
      }
    });
    if (!channelFound || path.length > 0) {
      throw new Error('Invalid blog feed');
    }
    return items;
  }

  static parseList(html: string, campus: EasCampus = EasCampus.BENBU): NewsItem[] {
    if (campus !== EasCampus.BENBU) {
      return NewsService.parseCampusList(html, campus);
    }
    const out: NewsItem[] = [];
    const seen: Set<string> = new Set<string>();
    const itemPattern: RegExp = /<li>\s*<div class="pull-right">([\s\S]*?)<\/li>/g;
    let match: RegExpExecArray | null = itemPattern.exec(html);
    while (match !== null) {
      const block: string = match[1];
      match = itemPattern.exec(html);
      const article: RegExpExecArray | null = /<a href="(\/article\/[^"]+)"[^>]*>([\s\S]*?)<\/a>/.exec(block);
      if (article === null || seen.has(article[1])) {
        continue;
      }
      const title: string = NewsService.cleanText(article[2]);
      if (title.length === 0) {
        continue;
      }
      seen.add(article[1]);
      const item: NewsItem = new NewsItem();
      item.url = BASE_URL + article[1];
      item.title = title;
      const department: RegExpExecArray | null = /<a href="\/department\/\d+"[^>]*>([^<]+)<\/a>/.exec(block);
      item.department = department === null ? '' : NewsService.cleanText(department[1]);
      const pathDate: RegExpExecArray | null = /\/article\/(\d{4})\/(\d{2})\/(\d{2})\//.exec(article[1]);
      const relative: RegExpExecArray | null = /<span class="date">([^<]+)<\/span>/.exec(block);
      item.date = pathDate !== null ? pathDate[1] + '-' + pathDate[2] + '-' + pathDate[3] :
        (relative === null ? '' : NewsService.cleanText(relative[1]));
      out.push(item);
    }
    return out;
  }

  private static parseCampusList(html: string, campus: EasCampus): NewsItem[] {
    const out: NewsItem[] = [];
    const seen: Set<string> = new Set<string>();
    const content: string = html.replace(/<!--[\s\S]*?-->|<script\b[^>]*>[\s\S]*?<\/script>/gi, '');
    // VSB uses li or table rows; WebPlus uses li with news-time2 and a full title attribute.
    const patterns: RegExp[] = [/<li\b[^>]*>([\s\S]*?)<\/li>/gi, /<tr\b[^>]*>([\s\S]*?)<\/tr>/gi];
    for (let i: number = 0; i < patterns.length && out.length === 0; i++) {
      let row: RegExpExecArray | null = patterns[i].exec(content);
      while (row !== null) {
        const block: string = row[1];
        row = patterns[i].exec(content);
        const links: RegExp = /<a\b([^>]*)>([\s\S]*?)<\/a>/gi;
        let link: RegExpExecArray | null = links.exec(block);
        while (link !== null) {
          const url: string = NewsService.articleUrl(NewsService.attribute(link[1], 'href'), campus);
          const title: string = NewsService.cleanText(NewsService.attribute(link[1], 'title') || link[2]);
          link = links.exec(block);
          if (url.length === 0 || title.length === 0 || seen.has(url)) { continue; }
          seen.add(url);
          const item: NewsItem = new NewsItem();
          item.url = url;
          item.title = title;
          // Dates mentioned in the article title are not its publication date.
          const metadata: string = block.replace(/<a\b[^>]*>[\s\S]*?<\/a>/gi, '');
          const date: RegExpExecArray | null = /(\d{4})[-/.年](\d{1,2})[-/.月](\d{1,2})/.exec(
            NewsService.cleanText(metadata));
          item.date = date === null ? '' : date[1] + '-' + date[2].padStart(2, '0') + '-' + date[3].padStart(2, '0');
          out.push(item);
        }
      }
    }
    return out;
  }

  private static articleUrl(href: string, campus: EasCampus): string {
    const origin: string = campus === EasCampus.SHENZHEN ? SHENZHEN_URL : WEIHAI_URL;
    let path: string = href.trim();
    const absolute: RegExpExecArray | null = /^(?:https?:)?\/\/([^/]+)(\/.*)$/i.exec(path);
    let base: string = origin;
    if (absolute !== null) {
      if (absolute[1].toLowerCase() !== origin.substring(7)) { return ''; }
      base = path.startsWith('https://') ? origin.replace('http:', 'https:') : origin;
      path = absolute[2];
    }
    path = '/' + path.replace(/^(?:\.\/|\.\.\/)+/, '').replace(/^\//, '');
    const valid: boolean = campus === EasCampus.SHENZHEN ?
      /^\/info\/\d+\/\d+\.htm(?:[?#][^\s<>]*)?$/.test(path) ||
        /^\/content\.jsp\?[^\s<>]*\bwbnewsid=\d+(?:&[^\s<>]*)?$/.test(path) :
      /^\/\d{4}\/\d{4}\/c\d+a\d+\/page\.htm(?:[?#][^\s<>]*)?$/.test(path);
    return valid ? base + path : '';
  }

  private static attribute(attributes: string, name: string): string {
    const match: RegExpExecArray | null = new RegExp('(?:^|\\s)' + name + '\\s*=\\s*([\"\'])([\\s\\S]*?)\\1', 'i')
      .exec(attributes);
    return match === null ? '' : match[2].replace(/&amp;/g, '&');
  }

  private static cleanText(raw: string): string {
    return raw.replace(/<[^>]+>/g, '')
      .replace(/&nbsp;/g, ' ')
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&apos;|&#0?39;/g, '\'')
      .replace(/\s+/g, ' ')
      .trim();
  }
}
