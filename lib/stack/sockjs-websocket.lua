local get_digest
do
  local _table_0 = require('openssl')
  get_digest = _table_0.get_digest
end
local floor
do
  local _table_0 = require('math')
  floor = _table_0.floor
end
local validate_crypto
validate_crypto = function(req_headers, nonce)
  local k1 = req_headers['sec-websocket-key1']
  local k2 = req_headers['sec-websocket-key2']
  if not k1 or not k2 then
    return false
  end
  local md5 = get_digest('md5'):init()
  local _list_0 = {
    k1,
    k2
  }
  for _index_0 = 1, #_list_0 do
    local k = _list_0[_index_0]
    local n = tonumber(String.gsub(k, '[^%d]', ''))
    local spaces = #String.gsub(k, '[^ ]', '')
    if spaces == 0 or n % spaces ~= 0 then
      return false
    end
    n = n / spaces
    local s = String.char(floor(n / 16777216) % 255, floor(n / 65536) % 255, floor(n / 256) % 255, n % 255)
    md5.update(s)
  end
  md5.update(String.byte(nonce))
  return md5:final()
end
local WebHandshakeHixie76
WebHandshakeHixie76 = (function()
  local _parent_0 = nil
  local _base_0 = {
    _cleanup = function(self)
      self.connection:remove_listener('end', self.close_cb)
      self.connection:remove_listener('data', self.data_cb)
      self.close_cb = nil
      self.data_cb = nil
    end,
    didClose = function(self)
      if self.connection then
        self:_cleanup()
        self.connection:close()
        self.connection = nil
      end
    end,
    didMessage = function(self, bin_data)
      self.buffer = self.buffer .. bin_data
      if self.sec == false or #self.buffer >= 8 then
        return self:gotEnough()
      end
    end,
    gotEnough = function(self)
      self:_cleanup()
      if self.sec then
        local nonce = String.sub(self.buffer, 1, 8)
        self.buffer = String.sub(self.buffer, 9)
        local reply = validate_crypto(self.req.headers, nonce)
        if reply == false then
          self:didClose()
          return false
        end
        self.connection:write(reply)
      end
      local session = Session.get_or_create(nil, self.options)
      return session.register(WebSocketReceiver(self.connection))
    end
  }
  _base_0.__index = _base_0
  if _parent_0 then
    setmetatable(_base_0, getmetatable(_parent_0).__index)
  end
  local _class_0 = setmetatable({
    __init = function(self, options, req, connection, head, origin, location)
      self.options, self.req, self.connection = options, req, connection
      self.sec = self.req.headers['sec-websocket-key1']
      local wsp = self.sec and self.req.headers['sec-websocket-protocol']
      local prefix
      if self.sec then
        prefix = 'Sec-'
      else
        prefix = ''
      end
      local blob = {
        'HTTP/1.1 101 WebSocket Protocol Handshake',
        'Upgrade: WebSocket',
        'Connection: Upgrade',
        prefix .. 'WebSocket-Origin: ' .. origin,
        prefix .. 'WebSocket-Location: ' .. location
      }
      if wsp then
        Table.insert(blob, ('Sec-WebSocket-Protocol: ' .. self.req.headers['sec-websocket-protocol'].split('[^,]*')))
      end
      self.close_cb = function()
        return self:didClose()
      end
      self.connection:on('end', self.close_cb)
      self.data_cb = function(data)
        return self:didMessage(data)
      end
      self.connection:on('data', self.data_cb)
      self.connection:write(Table.concat(blob, '\r\n') .. '\r\n\r\n')
      self.buffer = ''
      self:didMessage(head)
      return 
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
local _ = [==[class WebSocketReceiver extends ConnectionReceiver
  protocol: 'websocket'

  new: =>
    @recv_buffer = ''
    super!

  setUp: =>
    @data_cb = (data) -> @didMessage data
    @connection\on 'data', @data_cb
    super!

  tearDown: =>
    @connection\remove_listener 'data', @data_cb
    @data_cb = nil
    super!

  didMessage: (bin_data) =>
    if bin_data
      @recv_buffer = utils.buffer_concat(@recv_buffer, new Buffer(bin_data, 'binary'))
    buf = @recv_buffer
    -- TODO: support length in framing
    if buf.length is 0
      return
    if buf[0] is 0x00
      for i in [1...buf.length]
        if buf[i] is 0xff
          payload = buf.slice(1, i).toString('utf8')
          @recv_buffer = buf.slice(i+1)
          if @session and payload.length > 0
            try
              message = JSON.decode payload
            catch x
              return @didClose(1002, 'Broken framing.')
            @session.didMessage(message)
          return @didMessage()
      # wait for more data
      return
    else if buf[0] is 0xff and buf[1] is 0x00
      @didClose(1001, "Socket closed by the client")
    else
      @didClose(1002, "Broken framing")
    return

  doSendFrame: (payload) =>
    -- 6 bytes for every char shall be enough for utf8
    a = new Buffer((payload.length+2)*6)
    l = 0
    l = l + a.write('\u0000', l, 'binary')
    l = l + a.write('' + payload, l, 'utf-8')
    l = l + a.write('\uffff', l, 'binary')
    super String.sub a, 1, l

]==]
return WebHandshakeHixie76
