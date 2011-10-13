require('lib/util')
local Stack = require('lib/stack')
local JSON = require('cjson')
local date, time
do
  local _table_0 = require('os')
  date = _table_0.date
  time = _table_0.time
end
local _ = [==[BaseUrlGreeting
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
local iframe_template = [[<!DOCTYPE html>
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
local sockjs_url = '/fooooo'
local etag = '/fooooo'
local allowed_types = {
  ['application/json'] = true,
  ['text/plain'] = true,
  ['application/xml'] = true,
  ['T'] = true,
  [''] = true
}
local Response = require('response')
Response.prototype.xhr_cors = function(self)
  local origin = self.req.headers['origin'] or '*'
  self:set_header('Access-Control-Allow-Origin', origin)
  local headers = self.req.headers['access-control-request-headers']
  if headers then
    self:set_header('Access-Control-Allow-Headers', headers)
  end
  return self:set_header('Access-Control-Allow-Credentials', 'true')
end
Response.prototype.balancer_cookie = function(self)
  local cookies = { }
  if self.req.headers.cookie then
    p('RAW COOKIE', self.req.headers.cookie)
    for cookie in String.gmatch(self.req.headers.cookie, '[^;]+') do
      local name, value = String.match(cookie, '%s*([^=%s]-)%s*=%s*([^%s]*)')
      if name and value then
        cookies[name] = value
      end
    end
    p('\n\n\ncookie<<<', cookies, '\n\n\n')
  end
  self.req.cookies = cookies
  local jsid = cookies['JSESSIONID'] or 'dummy'
  return self:set_header('Set-Cookie', 'JSESSIONID=' .. jsid .. '; path=/')
end
local sids = { }
local layers
layers = function()
  return {
    Stack.use('static')('/public/', 'public/', { }),
    Stack.use('route')({
      ['POST /echo/[^./]+/([^./]+)/xhr[/]?$'] = function(self, nxt, sid)
        self:xhr_cors()
        self:balancer_cookie()
        p('xhr', sid, self.req.cookies)
        self:send(200, 'o\n', {
          ['Content-Type'] = 'application/javascript; charset=UTF-8'
        })
        if not sids[sid] then
          sids[sid] = { }
        end
      end,
      ['POST /echo/[^./]+/([^./]+)/xhr_send[/]?$'] = function(self, nxt, sid)
        self:xhr_cors()
        self:balancer_cookie()
        local data = ''
        self.req:on('data', function(chunk)
          data = data .. chunk
        end)
        self.req:on('error', function(err)
          return p('error', err)
        end)
        self.req:on('end', function()
          local ctype = self.req.headers['content-type'] or ''
          ctype = String.match(ctype, '([^;]-)')
          if not allowed_types[ctype] then
            data = nil
          end
          local session = sids[sid]
          if not session then
            return self:send(404)
          end
          if not data then
            return self:fail('Payload expected.')
          end
          local err
          data, err = pcall(JSON.decode, data)
          p('json', data, err)
          if err then
            return self:fail('Broken JSON encoding.')
          end
          if not is_array(data) then
            return self:fail('Payload expected.')
          end
          for message in data do
            p('message', message)
          end
          return self:send(204, nil, {
            ['Content-Type'] = 'text/plain'
          })
        end)
        return nil
      end,
      ['OPTIONS /echo/[^./]+/([^./]+)/xhr[/]?$'] = function(self, nxt, sid)
        self:xhr_cors()
        self:balancer_cookie()
        return self:send(204, nil, {
          ['Allow'] = 'OPTIONS, POST',
          ['Cache-Control'] = 'public, max-age=31536000',
          ['Expires'] = date('%c', time() + 31536000),
          ['Access-Control-Max-Age'] = '31536000'
        })
      end,
      ['OPTIONS /echo/[^./]+/([^./]+)/xhr_send[/]?$'] = function(self, nxt, sid)
        self:xhr_cors()
        self:balancer_cookie()
        return self:send(204, nil, {
          ['Allow'] = 'OPTIONS, POST',
          ['Cache-Control'] = 'public, max-age=31536000',
          ['Expires'] = date('%c', time() + 31536000),
          ['Access-Control-Max-Age'] = '31536000'
        })
      end,
      ['GET /echo/iframe([0-9-.a-z_]*)%.html$'] = function(self, nxt, version)
        local content = String.gsub(iframe_template, '{{ sockjs_url }}', sockjs_url)
        if self.req.headers['if-none-match'] == etag then
          return self:send(304)
        end
        return self:send(200, content, {
          ['Content-Type'] = 'text/html; charset=UTF-8',
          ['Content-Length'] = #content,
          ['Cache-Control'] = 'public, max-age=31536000',
          ['Expires'] = date('%c', time() + 31536000),
          ['Etag'] = etag
        })
      end,
      ['GET /echo[/]?$'] = function(self, nxt)
        return self:send(200, 'Welcome to SockJS!\n', {
          ['Content-Type'] = 'text/plain; charset=UTF-8'
        })
      end,
      ['GET /disabled_websocket_echo[/]?$'] = function(self, nxt)
        return self:send(200)
      end,
      ['POST /close[/]?'] = function(self, nxt)
        return self:send(200, 'c[3000,"Go away!"]\n')
      end
    }),
    function(req, res, nxt)
      local n = tonumber(req.url:sub(2), 10)
      if not n then
        return nxt()
      end
      local s = (' '):rep(n)
      res:write_head(200, {
        ['Content-Type'] = 'text/plain',
        ['Content-Length'] = {
          s = len()
        }
      })
      return res:safe_write(s, function()
        return res:finish()
      end)
    end
  }
end
Stack(layers()):run(8080)
print('Server listening at http://localhost:65401/')
