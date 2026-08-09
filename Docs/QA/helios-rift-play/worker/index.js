const MIME_BY_EXT = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.png': 'image/png',
  '.json': 'application/json',
};

function contentTypeForPath(pathname) {
  if (pathname === '/' || pathname.endsWith('/')) return MIME_BY_EXT['.html'];
  const dot = pathname.lastIndexOf('.');
  if (dot === -1) return null;
  return MIME_BY_EXT[pathname.slice(dot)] ?? null;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === '/play') url.pathname = '/';

    const assetRequest = new Request(url, request);
    const response = await env.ASSETS.fetch(assetRequest);
    if (!response.ok) return response;

    const type = contentTypeForPath(url.pathname);
    if (!type) return response;

    const headers = new Headers(response.headers);
    headers.set('Content-Type', type);
    headers.delete('Content-Disposition');
    return new Response(response.body, { status: response.status, headers });
  },
};
