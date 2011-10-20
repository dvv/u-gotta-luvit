local get_digest
do
  local _table_0 = require('openssl')
  get_digest = _table_0.get_digest
end
local floor, random
do
  local _table_0 = require('math')
  floor = _table_0.floor
  random = _table_0.random
end
local band, bor, bxor, rshift, lshift
do
  local _table_0 = require('bit')
  band = _table_0.band
  bor = _table_0.bor
  bxor = _table_0.bxor
  rshift = _table_0.rshift
  lshift = _table_0.lshift
end
local slice = String.sub
local byte = String.byte
local push = Table.insert
local join = Table.concat
local JSON = require('../cjson')
local validate_hixie76_crypto
validate_hixie76_crypto = function(req_headers, nonce)
  local k1 = req_headers['sec-websocket-key1']
  local k2 = req_headers['sec-websocket-key2']
  if not k1 or not k2 then
    return false
  end
  local dg = get_digest('md5'):init()
  local _list_0 = {
    k1,
    k2
  }
  for _index_0 = 1, #_list_0 do
    local k = _list_0[_index_0]
    local n = tonumber((String.gsub(k, '[^%d]', '')), 10)
    local spaces = #(String.gsub(k, '[^ ]', ''))
    if spaces == 0 or n % spaces ~= 0 then
      return false
    end
    n = n / spaces
    dg:update(String.char(rshift(n, 24) % 256, rshift(n, 16) % 256, rshift(n, 8) % 256, n % 256))
  end
  dg:update(nonce)
  local r = dg:final()
  dg:cleanup()
  return r
end
local WebHandshakeHixie76
WebHandshakeHixie76 = function(self, origin, location, cb)
  p('SHAKE76', origin, location)
  self.sec = self.req.headers['sec-websocket-key1']
  local prefix = self.sec and 'Sec-' or ''
  local blob = {
    'HTTP/1.1 101 WebSocket Protocol Handshake',
    'Upgrade: WebSocket',
    'Connection: Upgrade',
    prefix .. 'WebSocket-Origin: ' .. origin,
    prefix .. 'WebSocket-Location: ' .. location
  }
  if self.sec and self.req.headers['sec-websocket-protocol'] then
    Table.insert(blob, ('Sec-WebSocket-Protocol: ' .. self.req.headers['sec-websocket-protocol'].split('[^,]*')))
  end
  self:write(Table.concat(blob, '\r\n') .. '\r\n\r\n')
  local data = ''
  local ondata
  ondata = function(chunk)
    if chunk then
      data = data .. chunk
    end
    local buf = data
    if #buf == 0 then
      return 
    end
    if String.byte(buf, 1) == 0 then
      for i = 2, #buf do
        if String.byte(buf, i) == 255 then
          local payload = String.sub(buf, 2, i - 1)
          data = String.sub(buf, i + 1)
          if self.session and #payload > 0 then
            local status, message = pcall(JSON.decode, payload)
            p('DECODE', payload, status, message)
            if not status then
              return self:do_reasoned_close(1002, 'Broken framing.')
            end
            self.session:onmessage(message)
          end
          ondata()
          return 
        end
      end
      return 
    else
      if String.byte(buf, 1) == 255 and String.byte(buf, 2) == 0 then
        self:do_reasoned_close(1001, 'Socket closed by the client')
      else
        self:do_reasoned_close(1002, 'Broken framing')
      end
    end
    return 
  end
  self.req:once('upgrade', function(chunk)
    data = data .. chunk
    if self.sec == false or #data >= 8 then
      if self.sec then
        local nonce = slice(data, 1, 8)
        data = slice(data, 9)
        local reply = validate_hixie76_crypto(self.req.headers, nonce)
        if not reply then
          self:do_reasoned_close()
          return 
        end
        self:on('data', ondata)
        self:write(reply)
        if cb then
          cb()
        end
      end
    end
    return 
  end)
  self.send_frame = function(self, payload)
    p('SEND', payload)
    self:write('\000' .. payload .. '\255')
    return [==[@write '\000'
    @write payload
    @write '\255']==]
  end
end
local verify_hybi_secret
verify_hybi_secret = function(key)
  local data = (String.match(key, '(%S+)')) .. '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'
  local dg = get_digest('sha1'):init()
  dg:update(data)
  local r = dg:final()
  dg:cleanup()
  return r
end
local rand256
rand256 = function()
  return floor(random() * 256)
end
local WebHandshake8
WebHandshake8 = function(self, origin, location, cb)
  p('SHAKE8', origin, location)
  local blob = {
    'HTTP/1.1 101 Switching Protocols',
    'Upgrade: WebSocket',
    'Connection: Upgrade',
    'Sec-WebSocket-Accept: ' .. String.base64(verify_hybi_secret(self.req.headers['sec-websocket-key']))
  }
  if self.req.headers['sec-websocket-protocol'] then
    Table.insert(blob, ('Sec-WebSocket-Protocol: ' .. self.req.headers['sec-websocket-protocol'].split('[^,]*')))
  end
  self:write(Table.concat(blob, '\r\n') .. '\r\n\r\n')
  local data = ''
  local ondata
  ondata = function(chunk)
    p('DATA', chunk)
    if chunk then
      data = data .. chunk
    end
    local buf = data
    if #buf < 2 then
      return 
    end
    local first = band(byte(buf, 2), 0x7F)
    if band(byte(buf, 1), 0x80) ~= 0x80 then
      error('fin flag not set')
      self:do_reasoned_close(1002, 'Fin flag not set')
      return 
    end
    local opcode = band(byte(buf, 1), 0x0F)
    if opcode ~= 1 and opcode ~= 8 then
      error('not a text nor close frame', opcode)
      self:do_reasoned_close(1002, 'not a text nor close frame')
      return 
    end
    if opcode == 8 and first >= 126 then
      error('wrong length for close frame!!!')
      self:do_reasoned_close(1002, 'wrong length for close frame')
      return 
    end
    local l = 0
    local length = 0
    local masking = band(byte(buf, 2), 0x80) ~= 0
    if first < 126 then
      length = first
      l = 2
    elseif first == 126 then
      if #buf < 4 then
        return 
      end
      length = bor(lshift(byte(buf, 3), 8), byte(buf, 4))
      l = 4
    elseif first == 127 then
      if #buf < 10 then
        return 
      end
      length = 0
      for i = 3, 10 do
        length = bor(length, lshift(byte(buf, i), (10 - i) * 8))
      end
      l = 10
    end
    if masking then
      if #buf < l + 4 then
        return 
      end
      local key = { }
      key[1] = byte(buf, l + 1)
      key[2] = byte(buf, l + 2)
      key[3] = byte(buf, l + 3)
      key[4] = byte(buf, l + 4)
      l = l + 4
    end
    if #buf < l + length then
      return 
    end
    local payload = slice(l, l + length)
    if masking then
      local tbl = { }
      for i = 1, length do
        push(tbl, bxor(byte(payload, i), key[(i - 1) % 4]))
      end
      payload = join(tbl, '')
    end
    data = slice(buf, l + length)
    p('ok', masking, length)
    if opcode == 1 then
      if self.session and #payload > 0 then
        local status, message = pcall(JSON.decode, payload)
        p('DECODE', payload, status, message)
        if not status then
          return self:do_reasoned_close(1002, 'Broken framing.')
        end
        self.session:onmessage(messages)
      end
      ondata()
      return 
    elseif opcode == 8 then
      if #payload >= 2 then
        local status = bor(lshift(byte(payload, 1), 8), byte(payload, 2))
      else
        local status = 1002
      end
      if #payload > 2 then
        local reason = slice(payload, 3)
      else
        local reason = 'Connection closed by user'
      end
      self:do_reasoned_close(status, reason)
    end
    return 
  end
  self.req:on('data', ondata)
  self.send_frame = function(self, payload)
    p('SEND', payload)
    local pl = #payload
    local a = { }
    local _ = [==[    push a, 128 + 1
    push a, 128
    if pl < 126
      a[2] = bor a[2], pl
    elseif pl < 65536
      a[2] = bor a[2], 126
      push a, rshift(pl, 8) % 256
      push a, pl % 256
    else
      pl2 = pl
      a[2] = bor a[2], 127
      for i in 7, -1, -1
        a[l+i] = pl2 % 256
        pl2 = rshift pl2, 8
    key = {rand256(), rand256(), rand256(), rand256()}
    push a, key[1]
    push a, key[2]
    push a, key[3]
    push a, key[4]
    for i in 0, pl
      push a, bxor(byte(payload, i + 1), key[i % 4 + 1])
    --
    ]==]
    return self:write_frame(join(a, ''))
  end
end
return {
  WebHandshakeHixie76 = WebHandshakeHixie76,
  WebHandshake8 = WebHandshake8
}
