require('lib/util')
local Stack = require('lib/stack')
local set_timeout, clear_timer
do
  local _table_0 = require('timer')
  set_timeout = _table_0.set_timeout
  clear_timer = _table_0.clear_timer
end
local JSON = require('cjson')
local date, time
do
  local _table_0 = require('os')
  date = _table_0.date
  time = _table_0.time
end
local _error = error
local error
error = function(...)
  return p('FOCKING ERROR', ...)
end
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
local allowed_types = {
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
local closeFrame
closeFrame = function(status, reason)
  return 'c' .. JSON.encode({
    status,
    reason
  })
end
local Transport = {
  CONNECTING = 0,
  OPEN = 1,
  CLOSING = 2,
  CLOSED = 3
}
local sessions = { }
local Session
Session = (function()
  local _parent_0 = nil
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
    emit = function(self, ...)
      return p('EMIT', self.sid, ...)
    end,
    register = function(self, recv)
      p('REGISTER', self.sid)
      if self.recv then
        recv:doSendFrame(closeFrame(2010, 'Another connection still open'))
        return 
      end
      if self.readyState == Transport.CLOSING then
        recv:doSendFrame(self.close_frame)
        self.to_tref = set_timeout(self.disconnect_delay, self.timeout_cb)
        return 
      end
      self.recv = recv
      self.recv.session = self
      if self.readyState == Transport.CONNECTING then
        self.recv:doSendFrame('o')
        self.readyState = Transport.OPEN
        set_timeout(0, self.emit_open)
      end
      if not self.recv then
        return 
      end
      self:tryFlush()
      return 
    end,
    unregister = function(self)
      p('UNREGISTER', self.sid)
      self.recv.session = nil
      self.recv = nil
      if self.to_tref then
        clear_timer(self.to_tref)
      end
      self.to_tref = set_timeout(self.disconnect_delay, self.timeout_cb)
      return 
    end,
    tryFlush = function(self)
      p('TRYFLUSH', self.sid, self.send_buffer)
      if #self.send_buffer > 0 then
        local sb = self.send_buffer
        self.send_buffer = { }
        self.recv:doSendBulk(sb)
      else
        if self.to_tref then
          clear_timer(self.to_tref)
        end
        local x
        x = function()
          if self.recv then
            self.to_tref = set_timeout(self.heartbeat_delay, x)
            return self.recv:doSendFrame('h')
          end
        end
        self.to_tref = set_timeout(self.heartbeat_delay, x)
      end
      return 
    end,
    didTimeout = function(self)
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
    didMessage = function(self, payload)
      p('INCOME', self.sid, payload)
      if self.readyState == Transport.OPEN then
        self:emit('message', payload)
        self:send(payload)
      end
      return 
    end,
    send = function(self, payload)
      p('SEND?', self.sid, payload)
      if self.readyState ~= Transport.OPEN then
        error('INVALID_STATE_ERR')
      end
      p('SEND!', self.sid, payload)
      Table.insert(self.send_buffer, tostring(payload))
      if self.recv then
        return self:tryFlush()
      end
    end,
    close = function(self, status, reason)
      if status == nil then
        status = 1000
      end
      if reason == nil then
        reason = 'Normal closure'
      end
      p('CLOSEORDERLY', self.sid, status)
      if self.readyState ~= Transport.OPEN then
        return false
      end
      self.readyState = Transport.CLOSING
      self.close_frame = closeFrame(status, reason)
      if self.recv then
        self.recv:doSendFrame(self.close_frame)
        if self.recv then
          return self.unregister
        end
      end
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
      self.timeout_cb = function()
        return self:didTimeout()
      end
      self.to_tref = set_timeout(self.disconnect_delay, self.timeout_cb)
      self.emit_open = function()
        self.emit_open = nil
        options.onconnection(self)
        return p('CONNECTION')
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
local GenericReceiver
GenericReceiver = (function()
  local _parent_0 = nil
  local _base_0 = {
    setUp = function(self)
      self.thingy_end_cb = function()
        return self:didClose(1006, 'Connection closed')
      end
      return self.thingy:on('end', self.thingy_end_cb)
    end,
    tearDown = function(self)
      self.thingy:remove_listener('end', self.thingy_end_cb)
      self.thingy_end_cb = nil
    end,
    didClose = function(self, status, reason)
      if self.thingy then
        self:tearDown()
        self.thingy = nil
      end
      if self.session then
        return self.session:unregister(status, reason)
      end
    end,
    doSendBulk = function(self, messages)
      p('SENDBULK', messages)
      return self:doSendFrame('a' .. JSON.encode(messages))
    end
  }
  _base_0.__index = _base_0
  if _parent_0 then
    setmetatable(_base_0, getmetatable(_parent_0).__index)
  end
  local _class_0 = setmetatable({
    __init = function(self, thingy)
      self.thingy = thingy
      return self:setUp()
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
local ResponseReceiver
ResponseReceiver = (function()
  local _parent_0 = GenericReceiver
  local _base_0 = {
    max_response_size = nil,
    doSendFrame = function(self, payload)
      self.curr_response_size = self.curr_response_size + #payload
      p('DOSENDFRAME', payload, self.curr_response_size, self.max_response_size)
      local r = false
      self.response:safe_write(payload)
      r = true
      if self.max_response_size and self.curr_response_size >= self.max_response_size then
        self:didClose()
      end
      return r
    end,
    didClose = function(self)
      p('DIDCLOSE')
      _parent_0.didClose(self)
      self.response:close()
      self.response = nil
    end
  }
  _base_0.__index = _base_0
  if _parent_0 then
    setmetatable(_base_0, getmetatable(_parent_0).__index)
  end
  local _class_0 = setmetatable({
    __init = function(self, response)
      self.response = response
      self.curr_response_size = 0
      _parent_0.__init(self, self.response)
      if self.max_response_size == nil then
        self.max_response_size = 128000
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
local XhrStreamingReceiver
XhrStreamingReceiver = (function()
  local _parent_0 = ResponseReceiver
  local _base_0 = {
    protocol = 'xhr-streaming',
    doSendFrame = function(self, payload)
      return _parent_0.doSendFrame(self, payload .. '\n')
    end
  }
  _base_0.__index = _base_0
  if _parent_0 then
    setmetatable(_base_0, getmetatable(_parent_0).__index)
  end
  local _class_0 = setmetatable({
    __init = function(self, ...)
      if _parent_0 then
        return _parent_0.__init(self, ...)
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
local XhrPollingReceiver
XhrPollingReceiver = (function()
  local _parent_0 = XhrStreamingReceiver
  local _base_0 = {
    protocol = 'xhr',
    max_response_size = 1
  }
  _base_0.__index = _base_0
  if _parent_0 then
    setmetatable(_base_0, getmetatable(_parent_0).__index)
  end
  local _class_0 = setmetatable({
    __init = function(self, ...)
      if _parent_0 then
        return _parent_0.__init(self, ...)
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
local JsonpReceiver
JsonpReceiver = (function()
  local _parent_0 = ResponseReceiver
  local _base_0 = {
    protocol = 'jsonp',
    max_response_size = 1,
    doSendFrame = function(self, payload)
      return _parent_0.doSendFrame(self, self.callback .. '(' .. JSON.encode(payload) .. ');\r\n')
    end
  }
  _base_0.__index = _base_0
  if _parent_0 then
    setmetatable(_base_0, getmetatable(_parent_0).__index)
  end
  local _class_0 = setmetatable({
    __init = function(self, res, callback)
      self.callback = callback
      return _parent_0.__init(self, res)
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
local HtmlFileReceiver
HtmlFileReceiver = (function()
  local _parent_0 = ResponseReceiver
  local _base_0 = {
    protocol = 'htmlfile',
    doSendFrame = function(self, payload)
      return _parent_0.doSendFrame(self, '<script>\np(' .. JSON.encode(payload) .. ');\n</script>\r\n')
    end
  }
  _base_0.__index = _base_0
  if _parent_0 then
    setmetatable(_base_0, getmetatable(_parent_0).__index)
  end
  local _class_0 = setmetatable({
    __init = function(self, ...)
      if _parent_0 then
        return _parent_0.__init(self, ...)
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
local EventSourceReceiver
EventSourceReceiver = (function()
  local _parent_0 = ResponseReceiver
  local _base_0 = {
    protocol = 'eventsource',
    doSendFrame = function(self, payload)
      return _parent_0.doSendFrame(self, 'data: ' .. String.url_encode(payload) .. '\r\n\r\n')
    end
  }
  _base_0.__index = _base_0
  if _parent_0 then
    setmetatable(_base_0, getmetatable(_parent_0).__index)
  end
  local _class_0 = setmetatable({
    __init = function(self, ...)
      if _parent_0 then
        return _parent_0.__init(self, ...)
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
return function(options)
  if options == nil then
    options = { }
  end
  local routes = {
    ['POST ${prefix}/[^./]+/([^./]+)/xhr_send[/]?$' % options] = function(self, nxt, sid)
      handle_xhr_cors(self)
      handle_balancer_cookie(self)
      local data = nil
      local process
      process = function()
        p('BODY', data)
        if data == '' then
          p('-------------------------------------------------------------------------')
        end
        local session = Session.get(sid)
        if not session then
          return self:send(404)
        end
        p('FOUND TARGET!', sid)
        local ctype = self.req.headers['content-type'] or ''
        ctype = String.match(ctype, '[^;]*')
        if not allowed_types.xhr[ctype] then
          data = nil
        end
        p('BODYPREDEC', data, ctype, self.req.headers['content-type'])
        if not data then
          return self:fail('Payload expected.')
        end
        local status
        status, data = pcall(JSON.decode, data)
        p('table', status, data)
        if not status then
          return self:fail('Broken JSON encoding.')
        end
        if not is_array(data) then
          return self:fail('Payload expected.')
        end
        local _list_0 = data
        for _index_0 = 1, #_list_0 do
          local message = _list_0[_index_0]
          session:didMessage(message)
        end
        self:send(204, nil, {
          ['Content-Type'] = 'text/plain'
        })
        return 
      end
      self.req:on('error', function(err)
        p('error', err)
        return 
      end)
      self.req:on('end', process)
      self.req:on('data', function(chunk)
        if data then
          data = data .. chunk
        else
          data = chunk
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
        local session = Session.get(sid)
        if not session then
          return self:send(404)
        end
        local ctype = self.req.headers['content-type'] or ''
        ctype = String.match(ctype, '[^;]*')
        local decoder = allowed_types.jsonp[ctype]
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
        local status
        status, data = pcall(JSON.decode, data)
        if not status then
          return self:fail('Broken JSON encoding.')
        end
        if not is_array(data) then
          return self:fail('Payload expected.')
        end
        local _list_0 = data
        for _index_0 = 1, #_list_0 do
          local message = _list_0[_index_0]
          session:didMessage(message)
        end
        self:send(200, 'ok', {
          ['Content-Length'] = 2
        })
        return 
      end
      self.req:on('error', function(err)
        p('error', err)
        return 
      end)
      self.req:on('end', process)
      self.req:on('data', function(chunk)
        if data then
          data = data .. chunk
        else
          data = chunk
        end
        return 
      end)
      return 
    end,
    ['POST ${prefix}/[^./]+/([^./]+)/xhr[/]?$' % options] = function(self, nxt, sid)
      handle_xhr_cors(self)
      handle_balancer_cookie(self)
      self:send(200, nil, {
        ['Content-Type'] = 'application/javascript; charset=UTF-8'
      }, false)
      local session = Session.get_or_create(sid, options)
      session:register(XhrPollingReceiver(self))
      return 
    end,
    ['POST ${prefix}/[^./]+/([^./]+)/xhr_streaming[/]?$' % options] = function(self, nxt, sid)
      handle_xhr_cors(self)
      handle_balancer_cookie(self)
      local content = String.rep('h', 2049) .. '\n'
      self:send(200, content, {
        ['Content-Type'] = 'application/javascript; charset=UTF-8'
      }, false)
      local session = Session.get_or_create(sid, options)
      session:register(XhrStreamingReceiver(self))
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
      local session = Session.get_or_create(sid, options)
      session:register(JsonpReceiver(self, callback))
      return 
    end,
    ['GET ${prefix}/[^./]+/([^./]+)/htmlfile[/]?$' % options] = function(self, nxt, sid)
      handle_balancer_cookie(self)
      local callback = self.req.uri.query.c or self.req.uri.query.callback
      if not callback then
        return self:fail('"callback" parameter required')
      end
      local content = String.gsub(htmlfile_template, '{{ callback }}', callback)
      self:send(200, content, {
        ['Content-Type'] = 'text/html; charset=UTF-8',
        ['Cache-Control'] = 'no-store, no-cache, must-revalidate, max-age=0'
      }, false)
      local session = Session.get_or_create(sid, options)
      session:register(HtmlFileReceiver(self))
      return 
    end,
    ['GET ${prefix}/[^./]+/([^./]+)/eventsource[/]?$' % options] = function(self, nxt, sid)
      handle_balancer_cookie(self)
      self:send(200, '\r\n', {
        ['Content-Type'] = 'text/event-stream; charset=UTF-8',
        ['Cache-Control'] = 'no-store, no-cache, must-revalidate, max-age=0'
      }, false)
      local session = Session.get_or_create(sid, options)
      session:register(EventSourceReceiver(self))
      return 
    end,
    ['(%w+) ${prefix}/[^./]+/([^./]+)/websocket[/]?$' % options] = function(self, nxt, verb, sid)
      p('WEBSOCKET', self.req)
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
      local shaker
      if ver == '8' or ver == '7' then
        shaker = WebHandshake8
      else
        shaker = WebHandshakeHixie76
      end
      return shaker(options, self.req, self, (head or ''), origin, location)
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
    ['POST /close[/]?'] = function(self, nxt)
      self:send(200, 'c[3000,"Go away!"]\n')
      return 
    end
  }
  for k, v in pairs(routes) do
    p(k)
  end
  return Stack.use('route')(routes)
end
