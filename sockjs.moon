require 'lib/util'
Stack = require 'lib/stack'
JSON = require 'cjson'
import date, time from require 'os'

-- tests
[==[
BaseUrlGreeting
---ChunkingTest
EventSource
HtmlFile
IframePage
JsonPolling
Protocol
SessionURLs
WebsocketHixie76
WebsocketHttpErrors
WebsocketHybi10
XhrPolling
XhrStreaming
]==]

iframe_template = [[
<!DOCTYPE html>
<html>
<head>
  <meta http-equiv="X-UA-Compatible" content="IE=edge" />
  <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
  <script>
    document.domain = document.domain;
    _sockjs_onload = function(){SockJS.bootstrap_iframe();};
  </script>
  <script src="{{ sockjs_url }}"></script>
</head>
<body>
  <h2>Don't panic!</h2>
  <p>This is a SockJS hidden iframe. It's used for cross domain magic.</p>
</body>
</html>
]]

sockjs_url = '/fooooo'
etag = '/fooooo'
allowed_types = {
  ['application/json']: true
  ['text/plain']: true
  ['application/xml']: true
  ['T']: true
  ['']: true
}

Response = require('response')
Response.prototype.xhr_cors = () =>
  origin = @req.headers['origin'] or '*'
  @set_header 'Access-Control-Allow-Origin', origin
  headers = @req.headers['access-control-request-headers']
  if headers
    @set_header 'Access-Control-Allow-Headers', headers
  @set_header 'Access-Control-Allow-Credentials', 'true'

Response.prototype.balancer_cookie = () =>
  cookies = {}
  if @req.headers.cookie
    p('RAW COOKIE', @req.headers.cookie)
    for cookie in String.gmatch(@req.headers.cookie, '[^;]+')
      name, value = String.match cookie, '%s*([^=%s]-)%s*=%s*([^%s]*)'
      cookies[name] = value if name and value
    p('\n\n\ncookie<<<', cookies, '\n\n\n')
  @req.cookies = cookies
  jsid = cookies['JSESSIONID'] or 'dummy'
  @set_header 'Set-Cookie', 'JSESSIONID=' .. jsid .. '; path=/'

sids = {}

layers = () -> {

  -- serve static files
  Stack.use('static')('/public/', 'public/', {
    -- should the `file` contents be cached?
    --is_cacheable = function(file) return file.size <= 65536 end,
    --is_cacheable = function(file) return true end,
  }),

  -- /echo
  Stack.use('route')({

    ['POST /echo/[^./]+/([^./]+)/xhr[/]?$']: (nxt, sid) =>
      @xhr_cors()
      @balancer_cookie()
      p('xhr', sid, @req.cookies)
      -- TODO: don't close here!!!
      @send 200, 'o\n', {
        ['Content-Type']: 'application/javascript; charset=UTF-8'
      }
      -- register session here
      if not sids[sid]
        sids[sid] = {}

    ['POST /echo/[^./]+/([^./]+)/xhr_send[/]?$']: (nxt, sid) =>
      @xhr_cors()
      @balancer_cookie()
      --p('xhr_send', sid, @req.cookies)
      data = ''
      @req\on 'data', (chunk) ->
        --p('chunk', chunk)
        data = data .. chunk
      @req\on 'error', (err) ->
        p('error', err)
      @req\on 'end', () ->
        ctype = @req.headers['content-type'] or ''
        ctype = String.match ctype, '([^;]-)'
        data = nil if not allowed_types[ctype]
        -- get session here
        session = sids[sid]
        return @send 404 if not session
        return @fail 'Payload expected.' if not data
        data, err = pcall JSON.decode, data
        p('json', data, err)
        return @fail 'Broken JSON encoding.' if err
        return @fail 'Payload expected.' if not is_array data
        -- process message
        for message in data
          p('message', message)
        -- respond ok
        @send 204, nil, {
          ['Content-Type']: 'text/plain'
        }
      nil

    ['OPTIONS /echo/[^./]+/([^./]+)/xhr[/]?$']: (nxt, sid) =>
      @xhr_cors()
      @balancer_cookie()
      @send 204, nil, {
        ['Allow']: 'OPTIONS, POST'
        ['Cache-Control']: 'public, max-age=31536000'
        ['Expires']: date('%c', time() + 31536000)
        ['Access-Control-Max-Age']: '31536000'
      }

    ['OPTIONS /echo/[^./]+/([^./]+)/xhr_send[/]?$']: (nxt, sid) =>
      @xhr_cors()
      @balancer_cookie()
      @send 204, nil, {
        ['Allow']: 'OPTIONS, POST'
        ['Cache-Control']: 'public, max-age=31536000'
        ['Expires']: date('%c', time() + 31536000)
        ['Access-Control-Max-Age']: '31536000'
      }

    ['GET /echo/iframe([0-9-.a-z_]*)%.html$']: (nxt, version) =>
      content = String.gsub iframe_template, '{{ sockjs_url }}', sockjs_url
      return @send 304 if @req.headers['if-none-match'] == etag
      @send 200, content, {
        ['Content-Type']: 'text/html; charset=UTF-8'
        ['Content-Length']: #content
        ['Cache-Control']: 'public, max-age=31536000'
        ['Expires']: date('%c', time() + 31536000)
        ['Etag']: etag
      }

    ['GET /echo[/]?$']: (nxt) =>
      @send 200, 'Welcome to SockJS!\n', ['Content-Type']: 'text/plain; charset=UTF-8'
    ['GET /disabled_websocket_echo[/]?$']: (nxt) =>
      @send 200
    -- TODO: close everything?
    ['POST /close[/]?']: (nxt) =>
      @send 200, 'c[3000,"Go away!"]\n'

  })

  -- test serving requested amount of octets
  (req, res, nxt) ->
    n = tonumber(req.url\sub(2), 10)
    return nxt() if not n
    s = (' ')\rep(n)
    res\write_head 200, {
      ['Content-Type']: 'text/plain'
      ['Content-Length']: s:len()
    }
    res\safe_write s, () -> res\finish()

}

Stack(layers())\run(8080)
print('Server listening at http://localhost:65401/')
