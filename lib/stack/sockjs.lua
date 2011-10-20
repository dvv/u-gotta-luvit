local EventEmitter = setmetatable({ }, {
  __index = require('emitter').meta
})
local set_timeout, clear_timer
do
  local _table_0 = require('timer')
  set_timeout = _table_0.set_timeout
  clear_timer = _table_0.clear_timer
end
local JSON = require('../cjson')
local date, time
do
  local _table_0 = require('os')
  date = _table_0.date
  time = _table_0.time
end
local Math = require('math')
local _ = [==[BaseUrlGreeting ChunkingTest IframePage WebsocketHttpErrors JsonPolling XhrPolling EventSource HtmlFile XhrStreaming
Protocol SessionURLs
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
local htmlfile_template = [[<!doctype html>
<html><head>
  <meta http-equiv="X-UA-Compatible" content="IE=edge" />
  <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
</head><body><h2>Don't panic!</h2>
  <script>
    document.domain = document.domain;
    var c = parent.{{ callback }};
    c.start();
    function p(d) {c.message(d);};
    window.onload = function() {c.stop();};
  </script>
]]
htmlfile_template = htmlfile_template .. String.rep(' ', 1024 - #htmlfile_template + 14) .. '\r\n\r\n'
local Transport = {
  CONNECTING = 0,
  OPEN = 1,
  CLOSING = 2,
  CLOSED = 3,
  closing_frame = function(status, reason)
    return 'c' .. JSON.encode({
      status,
      reason
    })
  end
}
local allowed_content_types = {
  xhr = {
    ['application/json'] = JSON.decode,
    ['text/plain'] = JSON.decode,
    ['application/xml'] = JSON.decode,
    ['T'] = JSON.decode,
    [''] = JSON.decode
  },
  jsonp = {
    ['application/x-www-form-urlencoded'] = String.parse_query,
    ['text/plain'] = true,
    [''] = true
  }
}
local escape_for_eventsource
escape_for_eventsource = function(str)
  str = String.gsub(str, '%%', '%25')
  str = String.gsub(str, '\r', '%0D')
  str = String.gsub(str, '\n', '%0A')
  return str
end
local sessions = { }
_G.s = function()
  return sessions
end
_G.f = function()
  sessions = { }
end
local Session
Session = (function()
  local _parent_0 = EventEmitter
  local _base_0 = {
    get = function(sid)
      return sessions[sid]
    end,
    get_or_create = function(sid, options)
      local session = Session.get(sid)
      if not session then
        session = Session(sid, options)
      end
      return session
    end,
    bind = function(self, recv)
      p('BIND', self.sid, self.id)
      if self.recv then
        p('ALREADY REGISTERED!!!')
        recv:send_frame(Transport.closing_frame(2010, 'Another connection still open'))
        return 
      end
      if self.readyState == Transport.CLOSING then
        p('STATEISCLOSING', self.close_frame)
        recv:send_frame(self.close_frame)
        if self.to_tref then
          clear_timer(self.to_tref)
        end
        self.to_tref = set_timeout(self.disconnect_delay, self.ontimeout, self)
        self.TO = 'TIMEOUTINREGISTER1'
        return 
      end
      p('DOREGISTER', self.readyState)
      self.recv = recv
      self.recv.session = self
      self.recv:once('closed', function()
        p('CLOSEDEVENT')
        return self:unbind()
      end)
      self.recv:once('end', function()
        p('END')
        return self:unbind()
      end)
      self.recv:once('error', function(err)
        p('ERROR', err)
        return self.recv:close()
      end)
      if self.readyState == Transport.CONNECTING then
        self.recv:send_frame('o')
        self.readyState = Transport.OPEN
        set_timeout(0, self.emit_connection_event)
      end
      if self.to_tref then
        clear_timer(self.to_tref)
        self.TO = 'CLEAREDINREGISTER:' .. self.TO
        self.to_tref = nil
      end
      if self.recv then
        self:flush()
      end
      return 
    end,
    unbind = function(self)
      p('UNREGISTER', self.sid, self.id, not not self.recv)
      if self.recv then
        self.recv.session = nil
        self.recv = nil
      end
      if self.to_tref then
        clear_timer(self.to_tref)
      end
      self.to_tref = set_timeout(self.disconnect_delay, self.ontimeout, self)
      self.TO = 'TIMEOUTINUNREGISTER'
      return 
    end,
    close = function(self, status, reason)
      if status == nil then
        status = 1000
      end
      if reason == nil then
        reason = 'Normal closure'
      end
      if self.readyState ~= Transport.OPEN then
        return false
      end
      self.readyState = Transport.CLOSING
      self.close_frame = Transport.closing_frame(status, reason)
      if self.recv then
        self.recv:send_frame(self.close_frame)
        self:unbind()
      end
      return 
    end,
    ontimeout = function(self)
      p('TIMEDOUT', self.sid, self.recv)
      if self.to_tref then
        clear_timer(self.to_tref)
        self.to_tref = nil
      end
      if self.readyState ~= Transport.CONNECTING and self.readyState ~= Transport.OPEN and self.readyState ~= Transport.CLOSING then
        error('INVALID_STATE_ERR')
      end
      if self.recv then
        error('RECV_STILL_THERE')
      end
      self.readyState = Transport.CLOSED
      self:emit('close')
      if self.sid then
        sessions[self.sid] = nil
        self.sid = nil
      end
      return 
    end,
    onmessage = function(self, payload)
      if self.readyState == Transport.OPEN then
        p('MESSAGE', payload)
        self:emit('message', payload)
      end
      return 
    end,
    send = function(self, payload)
      if self.readyState ~= Transport.OPEN then
        return false
      end
      Table.insert(self.send_buffer, type(payload) == 'table' and Table.concat(payload, ',') or tostring(payload))
      if self.recv then
        self:flush()
      end
      return true
    end,
    flush = function(self)
      p('INFLUSH', self.send_buffer)
      if #self.send_buffer > 0 then
        local messages = self.send_buffer
        self.send_buffer = { }
        self.recv:send_frame('a' .. JSON.encode(messages))
      else
        p('TOTREF?', self.TO, self.to_tref)
        _ = [==[      if @to_tref
        clear_timer @to_tref
        @to_tref = nil
      heart = ->
        p('INHEART', not not @recv)
        if @recv
          @recv\send_frame 'h'
          @to_tref = set_timeout @heartbeat_delay, heart
          @TO = 'TIMEOUTINHEARTX'
        else
          @to_tref = nil
          @TO = 'TIMEOUTINHEARTDOWNED'
      @to_tref = set_timeout @heartbeat_delay, heart
      @TO = 'TIMEOUTINHEART0'
      ]==]
      end
      return 
    end
  }
  _base_0.__index = _base_0
  if _parent_0 then
    setmetatable(_base_0, getmetatable(_parent_0).__index)
  end
  local _class_0 = setmetatable({
    __init = function(self, sid, options)
      self.sid = sid
      self.heartbeat_delay = options.heartbeat_delay
      self.disconnect_delay = options.disconnect_delay
      self.id = options.get_nonce()
      self.send_buffer = { }
      self.readyState = Transport.CONNECTING
      if self.sid then
        sessions[self.sid] = self
      end
      self.to_tref = set_timeout(self.disconnect_delay, self.ontimeout, self)
      self.TO = 'TIMEOUT1'
      self.emit_connection_event = function()
        self.emit_connection_event = nil
        return options.onconnection(self)
      end
    end
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  return _class_0
end)()
local handle_xhr_cors
handle_xhr_cors = function(self)
  local origin = self.req.headers['origin'] or '*'
  self:set_header('Access-Control-Allow-Origin', origin)
  local headers = self.req.headers['access-control-request-headers']
  if headers then
    self:set_header('Access-Control-Allow-Headers', headers)
  end
  return self:set_header('Access-Control-Allow-Credentials', 'true')
end
local handle_balancer_cookie
handle_balancer_cookie = function(self)
  local cookies = { }
  if self.req.headers.cookie then
    for cookie in String.gmatch(self.req.headers.cookie, '[^;]+') do
      local name, value = String.match(cookie, '%s*([^=%s]-)%s*=%s*([^%s]*)')
      if name and value then
        cookies[name] = value
      end
    end
  end
  self.req.cookies = cookies
  local jsid = cookies['JSESSIONID'] or 'dummy'
  return self:set_header('Set-Cookie', 'JSESSIONID=' .. jsid .. '; path=/')
end
local Response = require('response')
Response.prototype.do_reasoned_close = function(self, status, reason)
  p('REASONED_CLOSE', self.session and self.session.sid, status, reason)
  if self.session then
    self.session:unbind()
  end
  self:close()
  return 
end
Response.prototype.write_frame = function(self, payload)
  self.curr_size = self.curr_size + #payload
  self:write(payload)
  if self.max_size and self.curr_size >= self.max_size then
    p('MAX SIZE EXCEEDED')
    self:close()
  end
  return 
end
return function(options)
  if options == nil then
    options = { }
  end
  setmetatable(options, {
    __index = {
      prefix = '/ws',
      sockjs_url = 'http://sockjs.github.com/sockjs-client/sockjs-latest.min.js',
      heartbeat_delay = 25000,
      disconnect_delay = 5000,
      response_limit = 128 * 1024,
      origins = {
        '*:*'
      },
      disabled_transports = { },
      cache_age = 365 * 24 * 60 * 60,
      get_nonce = function()
        return Math.random()
      end
    }
  })
  local routes = {
    ['POST ${prefix}/[^./]+/([^./]+)/xhr[/]?$' % options] = function(self, nxt, sid)
      handle_xhr_cors(self)
      handle_balancer_cookie(self)
      self:send(200, nil, {
        ['Content-Type'] = 'application/javascript; charset=UTF-8'
      }, false)
      self.protocol = 'xhr'
      self.curr_size, self.max_size = 0, 1
      self.send_frame = function(self, payload)
        p('SEND', self.session and self.session.sid, payload)
        return self:write_frame(payload .. '\n')
      end
      local session = Session.get_or_create(sid, options)
      session:bind(self)
      return 
    end,
    ['GET ${prefix}/[^./]+/([^./]+)/jsonp[/]?$' % options] = function(self, nxt, sid)
      handle_balancer_cookie(self)
      local callback = self.req.uri.query.c or self.req.uri.query.callback
      if not callback then
        return self:fail('"callback" parameter required')
      end
      self:send(200, nil, {
        ['Content-Type'] = 'application/javascript; charset=UTF-8',
        ['Cache-Control'] = 'no-store, no-cache, must-revalidate, max-age=0'
      }, false)
      self.protocol = 'jsonp'
      self.curr_size, self.max_size = 0, 1
      self.send_frame = function(self, payload)
        return self:write_frame(callback .. '(' .. JSON.encode(payload) .. ');\r\n')
      end
      local session = Session.get_or_create(sid, options)
      session:bind(self)
      return 
    end,
    ['POST ${prefix}/[^./]+/([^./]+)/xhr_send[/]?$' % options] = function(self, nxt, sid)
      handle_xhr_cors(self)
      handle_balancer_cookie(self)
      local data = nil
      local process
      process = function()
        if self.processed then
          return 
        end
        self.processed = true
        local session = Session.get(sid)
        if not session then
          return self:send(404)
        end
        local ctype = self.req.headers['content-type'] or ''
        ctype = String.match(ctype, '[^;]*')
        if not allowed_content_types.xhr[ctype] then
          data = nil
        end
        if not data then
          return self:fail('Payload expected.')
        end
        local status
        status, data = pcall(JSON.decode, data)
        _ = [==[if not status
          p(status, data)
          error('JSON')]==]
        if not status then
          return self:fail('Broken JSON encoding.')
        end
        if not is_array(data) then
          return self:fail('Payload expected.')
        end
        local _list_0 = data
        for _index_0 = 1, #_list_0 do
          local message = _list_0[_index_0]
          session:onmessage(message)
        end
        self:send(204, nil, {
          ['Content-Type'] = 'text/plain'
        })
        return 
      end
      self.req:on('error', function(err)
        error(err)
        return 
      end)
      self.req:on('end', process)
      local expected_length = tonumber(self.req.headers['content-length'] or '0')
      self.req:on('data', function(chunk)
        if data then
          data = data .. chunk
        else
          data = chunk
        end
        if #data >= expected_length then
          process()
        end
        return 
      end)
      return 
    end,
    ['POST ${prefix}/[^./]+/([^./]+)/jsonp_send[/]?$' % options] = function(self, nxt, sid)
      handle_balancer_cookie(self)
      local data = nil
      local process
      process = function()
        if self.processed then
          return 
        end
        self.processed = true
        local session = Session.get(sid)
        if not session then
          return self:send(404)
        end
        local ctype = self.req.headers['content-type'] or ''
        ctype = String.match(ctype, '[^;]*')
        local decoder = allowed_content_types.jsonp[ctype]
        if not decoder then
          data = nil
        end
        if data and decoder ~= true then
          data = decoder(data).d
        end
        if data == '' then
          data = nil
        end
        if not data then
          return self:fail('Payload expected.')
        end
        local status, messages = pcall(JSON.decode, data)
        _ = [==[if not status
          p(status, messages)
          io = require('io')
          file = io.open('/home/dvv/LUA/u-gotta-luvit/JSON.DUMP', 'w')
          file\write(data)
          file\close()
          error('JSON')]==]
        if not status then
          return self:fail('Broken JSON encoding.')
        end
        if not is_array(messages) then
          return self:fail('Payload expected.')
        end
        local _list_0 = messages
        for _index_0 = 1, #_list_0 do
          local message = _list_0[_index_0]
          session:onmessage(message)
        end
        self:send(200, 'ok', {
          ['Content-Length'] = 2
        })
        return 
      end
      self.req:on('error', function(err)
        error(err)
        return 
      end)
      self.req:on('end', process)
      local expected_length = tonumber(self.req.headers['content-length'] or '0')
      self.req:on('data', function(chunk)
        if data then
          data = data .. chunk
        else
          data = chunk
        end
        if #data >= expected_length then
          process()
        end
        return 
      end)
      return 
    end,
    ['POST ${prefix}/[^./]+/([^./]+)/xhr_streaming[/]?$' % options] = function(self, nxt, sid)
      handle_xhr_cors(self)
      handle_balancer_cookie(self)
      self:set_chunked()
      local content = String.rep('h', 2048) .. '\n'
      self:send(200, content, {
        ['Content-Type'] = 'application/javascript; charset=UTF-8'
      }, false)
      self.protocol = 'xhr-streaming'
      self.curr_size, self.max_size = 0, options.response_limit
      self.send_frame = function(self, payload)
        return self:write_frame(payload .. '\n')
      end
      local session = Session.get_or_create(sid, options)
      session:bind(self)
      return 
    end,
    ['GET ${prefix}/[^./]+/([^./]+)/htmlfile[/]?$' % options] = function(self, nxt, sid)
      handle_balancer_cookie(self)
      self:set_chunked()
      local callback = self.req.uri.query.c or self.req.uri.query.callback
      if not callback then
        return self:fail('"callback" parameter required')
      end
      local content = String.gsub(htmlfile_template, '{{ callback }}', callback)
      self:send(200, content, {
        ['Content-Type'] = 'text/html; charset=UTF-8',
        ['Cache-Control'] = 'no-store, no-cache, must-revalidate, max-age=0'
      }, false)
      self.protocol = 'htmlfile'
      self.curr_size, self.max_size = 0, options.response_limit
      self.send_frame = function(self, payload)
        return self:write_frame('<script>\np(' .. JSON.encode(payload) .. ');\n</script>\r\n')
      end
      local session = Session.get_or_create(sid, options)
      session:bind(self)
      return 
    end,
    ['GET ${prefix}/[^./]+/([^./]+)/eventsource[/]?$' % options] = function(self, nxt, sid)
      handle_balancer_cookie(self)
      self:set_chunked()
      self:send(200, '\r\n', {
        ['Content-Type'] = 'text/event-stream; charset=UTF-8',
        ['Cache-Control'] = 'no-store, no-cache, must-revalidate, max-age=0'
      }, false)
      self.protocol = 'eventsource'
      self.curr_size, self.max_size = 0, options.response_limit
      self.send_frame = function(self, payload)
        return self:write_frame('data: ' .. escape_for_eventsource(payload) .. '\r\n\r\n')
      end
      local session = Session.get_or_create(sid, options)
      session:bind(self)
      return 
    end,
    ['POST ${prefix}/chunking_test[/]?$' % options] = function(self, nxt)
      handle_xhr_cors(self)
      self:set_chunked()
      self:send(200, nil, {
        ['Content-Type'] = 'application/javascript; charset=UTF-8'
      }, false)
      self:write('h\n')
      for k, delay in ipairs({
        1,
        1 + 5,
        25 + 5 + 1,
        125 + 25 + 5 + 1,
        625 + 125 + 25 + 5 + 1,
        3125 + 625 + 125 + 25 + 5 + 1
      }) do
        set_timeout(delay, function()
          if k == 1 then
            return self:write((String.rep(' ', 2048)) .. 'h\n')
          else
            return self:write('h\n')
          end
        end)
      end
      return 
    end,
    ['OPTIONS ${prefix}/chunking_test[/]?$' % options] = function(self, nxt)
      handle_xhr_cors(self)
      handle_balancer_cookie(self)
      self:send(204, nil, {
        ['Allow'] = 'OPTIONS, POST',
        ['Cache-Control'] = 'public, max-age=${cache_age}' % options,
        ['Expires'] = date('%c', time() + options.cache_age),
        ['Access-Control-Max-Age'] = tostring(options.cache_age)
      })
      return 
    end,
    ['OPTIONS ${prefix}/[^./]+/([^./]+)/(xhr_?%w*)[/]?$' % options] = function(self, nxt, sid, transport)
      handle_xhr_cors(self)
      handle_balancer_cookie(self)
      self:send(204, nil, {
        ['Allow'] = 'OPTIONS, POST',
        ['Cache-Control'] = 'public, max-age=${cache_age}' % options,
        ['Expires'] = date('%c', time() + options.cache_age),
        ['Access-Control-Max-Age'] = tostring(options.cache_age)
      })
      return 
    end,
    ['GET ${prefix}/iframe([0-9-.a-z_]*)%.html$' % options] = function(self, nxt, version)
      local content = String.gsub(iframe_template, '{{ sockjs_url }}', options.sockjs_url)
      local etag = tostring(#content)
      if self.req.headers['if-none-match'] == etag then
        return self:send(304)
      end
      self:send(200, content, {
        ['Content-Type'] = 'text/html; charset=UTF-8',
        ['Content-Length'] = #content,
        ['Cache-Control'] = 'public, max-age=${cache_age}' % options,
        ['Expires'] = date('%c', time() + options.cache_age),
        ['Etag'] = etag
      })
      return 
    end,
    ['GET ${prefix}[/]?$' % options] = function(self, nxt)
      self:send(200, 'Welcome to SockJS!\n', {
        ['Content-Type'] = 'text/plain; charset=UTF-8'
      })
      return 
    end,
    ['GET /disabled_websocket_echo[/]?$'] = function(self, nxt)
      self:send(200)
      return 
    end,
    ['(%w+) /close/'] = function(self, nxt, verb)
      self:send(200, 'c[3000,"Go away!"]\n')
      return 
    end,
    ['(%w+) ${prefix}/[^./]+/[^./]+/websocket[/]?$' % options] = function(self, nxt, verb, root)
      if verb ~= 'GET' then
        return self:send(405)
      end
      if String.lower(self.req.headers.upgrade or '') ~= 'websocket' then
        return self:send(400, 'Can "Upgrade" only to "WebSocket".')
      end
      if String.lower(self.req.headers.connection or '') ~= 'upgrade' then
        return self:send(400, '"Connection" must be "Upgrade".')
      end
      local origin = self.req.headers.origin
      local location = ((function()
        if origin and origin[1 .. 5] == 'https' then
          return 'wss'
        else
          return 'ws'
        end
      end)())
      location = location .. '://' .. self.req.headers.host .. self.req.url
      local ver = self.req.headers['sec-websocket-version']
      self:nodelay(true)
      self.protocol = 'websocket'
      self.curr_size, self.max_size = 0, options.response_limit
      local session = Session.get_or_create(nil, options)
      local WebSocket = require('lib/stack/sockjs-websocket')
      local shaker
      if ver == '8' or ver == '7' then
        shaker = WebSocket.WebHandshake8
      else
        shaker = WebSocket.WebHandshakeHixie76
      end
      shaker(self, origin, location, function()
        session:bind(self)
        if root == 'close' then
          return session:close(3000, 'Go away!')
        end
      end)
      return 
    end
  }
  for k, v in pairs(routes) do
    p(k)
  end
  return routes
end
