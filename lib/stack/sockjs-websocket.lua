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
local slice = String.sub
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
    p('K', k)
    local n = tonumber((String.gsub(k, '[^%d]', '')), 10)
    p('N', n)
    local spaces = #(String.gsub(k, '[^ ]', ''))
    p('S?', spaces)
    if spaces == 0 or n % spaces ~= 0 then
      return false
    end
    n = n / spaces
    p('S!', n, spaces)
    local s = String.char(floor(n / 16777216) % 255, floor(n / 65536) % 255, floor(n / 256) % 255, n % 255)
    md5:update(s)
  end
  md5:update(String.byte(nonce))
  return md5:final()
end
local handshake
handshake = function(self, origin, location)
  p('SHAKE', self, origin, location, self.req.head)
  self.sec = self.req.headers['sec-websocket-key1']
  local wsp = self.sec and self.req.headers['sec-websocket-protocol']
  local prefix = self.sec and 'Sec-' or ''
  local _ = [==[  blob = {
    'HTTP/1.1 101 WebSocket Protocol Handshake'
    'Upgrade: WebSocket'
    'Connection: Upgrade'
    prefix .. 'WebSocket-Origin: ' .. origin
    prefix .. 'WebSocket-Location: ' .. location
  }
  if wsp
    Table.insert blob, ('Sec-WebSocket-Protocol: ' .. @req.headers['sec-websocket-protocol'].split('[^,]*'))
  @write(Table.concat(blob, '\r\n') .. '\r\n\r\n')
  ]==]
  if wsp then
    self:set_header('Sec-WebSocket-Protocol: ', self.req.headers['sec-websocket-protocol'].split('[^,]*'))
  end
  local data = ''
  local ondata
  ondata = function(chunk)
    if chunk then
      data = data .. chunk
    end
    local buf = data
    if buf.length == 0 then
      return 
    end
    if String.byte(buf, 1) == 0 then
      for i = 2, buf.length do
        if String.byte(buf, i) == 255 then
          local payload = String.sub(buf, 1, i)
          data = String.sub(buf, i + 1)
          if self.session and #payload > 0 then
            local status
            status, data = pcall(JSON.decode, payload)
            if not status then
              return self:do_reasoned_close(1002, 'Broken framing.')
            end
            self.session.onmessage(message)
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
  local wait_for_nonce
  wait_for_nonce = function(chunk)
    p('WAIT', chunk)
    data = data .. chunk
    if self.sec == false or #data >= 8 then
      self:remove_listener('data', wait_for_nonce)
      if self.sec then
        local nonce = slice(data, 1, 8)
        data = slice(data, 9)
        local reply = validate_crypto(self.req.headers, nonce)
        if not reply then
          self:do_reasoned_close()
          return 
        end
        self:send(101, reply, {
          ['Upgrade'] = 'WebSocket',
          ['Connection'] = 'Upgrade',
          [prefix .. 'WebSocket-Origin'] = origin,
          [prefix .. 'WebSocket-Location'] = location
        }, false)
      end
      self:on('data', ondata)
    end
    return 
  end
  self:on('data', wait_for_nonce)
  wait_for_nonce(self.req.head or '')
  return self:on('end', function()
    return self:do_reasoned_close(1006, 'Connection closed')
  end)
end
return {
  handshake = handshake
}
