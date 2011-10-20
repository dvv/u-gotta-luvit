--
-- http://tools.ietf.org/html/draft-hixie-thewebsocketprotocol-76
--

import get_digest from require 'openssl'
import floor, random from require 'math'
import band, bor, bxor, rshift, lshift from require 'bit'
slice = String.sub
byte = String.byte
push = Table.insert
join = Table.concat
JSON = require '../cjson'

validate_hixie76_crypto = (req_headers, nonce) ->
  k1 = req_headers['sec-websocket-key1']
  k2 = req_headers['sec-websocket-key2']
  return false if not k1 or not k2
  dg = get_digest('md5')\init()
  for k in *{k1, k2}
    n = tonumber (String.gsub(k, '[^%d]', '')), 10
    spaces = #(String.gsub(k, '[^ ]', ''))
    return false if spaces == 0 or n % spaces != 0
    n = n / spaces
    dg\update String.char(rshift(n, 24) % 256, rshift(n, 16) % 256, rshift(n, 8) % 256, n % 256)
  dg\update nonce
  r = dg\final()
  dg\cleanup()
  r

WebHandshakeHixie76 = (origin, location, cb) =>
  p('SHAKE76', origin, location)
  @sec = @req.headers['sec-websocket-key1']
  prefix = @sec and 'Sec-' or ''
  blob = {
    'HTTP/1.1 101 WebSocket Protocol Handshake'
    'Upgrade: WebSocket'
    'Connection: Upgrade'
    prefix .. 'WebSocket-Origin: ' .. origin
    prefix .. 'WebSocket-Location: ' .. location
  }
  if @sec and @req.headers['sec-websocket-protocol']
    Table.insert blob, ('Sec-WebSocket-Protocol: ' .. @req.headers['sec-websocket-protocol'].split('[^,]*'))
  @write(Table.concat(blob, '\r\n') .. '\r\n\r\n')
  -- parse incoming data
  data = ''
  ondata = (chunk) ->
    --p('DATA', chunk)
    if chunk
      data = data .. chunk
    buf = data
    return if #buf == 0
    if String.byte(buf, 1) == 0
      for i = 2, #buf
        if String.byte(buf, i) == 255
          payload = String.sub(buf, 2, i - 1)
          data = String.sub(buf, i + 1)
          if @session and #payload > 0
            status, message = pcall JSON.decode, payload
            p('DECODE', payload, status, message)
            return @do_reasoned_close(1002, 'Broken framing.') if not status
            -- process message
            @session\onmessage message
          ondata()
          return
      -- wait for more data
      return
    else if String.byte(buf, 1) == 255 and String.byte(buf, 2) == 0
      @do_reasoned_close 1001, 'Socket closed by the client'
    else
      @do_reasoned_close 1002, 'Broken framing'
    return
  @req\once 'upgrade', (chunk) ->
    --p('WAIT', chunk)
    data = data .. chunk
    if @sec == false or #data >= 8
      if @sec
        nonce = slice data, 1, 8
        data = slice data, 9
        reply = validate_hixie76_crypto @req.headers, nonce
        if not reply
          @do_reasoned_close()
          return
        --p('REPLY', reply, #reply)
        @on 'data', ondata
        --status, err = pcall @write, self, reply
        @write reply
        cb() if cb
    return
  @send_frame = (payload) =>
    p('SEND', payload)
    -- N.B. plain write(), not write_frame(), not not account for max_size
    @write '\000' .. payload .. '\255'
    -- N.B. trade speed for memory usage
    [==[@write '\000'
    @write payload
    @write '\255']==]
  --if @req.upgrade
  --  @req\emit 'upgrade'

verify_hybi_secret = (key) ->
  data = (String.match(key, '(%S+)')) .. '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'
  dg = get_digest('sha1')\init()
  dg\update data
  r = dg\final()
  dg\cleanup()
  r

rand256 = () -> floor(random() * 256)

WebHandshake8 = (origin, location, cb) =>
  p('SHAKE8', origin, location)
  blob = {
    'HTTP/1.1 101 Switching Protocols'
    'Upgrade: WebSocket'
    'Connection: Upgrade'
    'Sec-WebSocket-Accept: ' .. String.base64(verify_hybi_secret(@req.headers['sec-websocket-key']))
  }
  if @req.headers['sec-websocket-protocol']
    Table.insert blob, ('Sec-WebSocket-Protocol: ' .. @req.headers['sec-websocket-protocol'].split('[^,]*'))
  @write(Table.concat(blob, '\r\n') .. '\r\n\r\n')
  -- parse incoming data
  data = ''
  ondata = (chunk) ->
    p('DATA', chunk)
    if chunk
      data = data .. chunk
    buf = data
    -- TODO: support length in framing
    return if #buf < 2
    first = band byte(buf, 2), 0x7F
    if band(byte(buf, 1), 0x80) != 0x80
      error('fin flag not set')
      @do_reasoned_close 1002, 'Fin flag not set'
      return
    opcode = band byte(buf, 1), 0x0F
    if opcode != 1 and opcode != 8
      error('not a text nor close frame', opcode)
      @do_reasoned_close 1002, 'not a text nor close frame'
      return
    if opcode == 8 and first >= 126
      error('wrong length for close frame!!!')
      @do_reasoned_close 1002, 'wrong length for close frame'
      return
    l = 0
    length = 0
    masking = band(byte(buf, 2), 0x80) != 0
    if first < 126
      length = first
      l = 2
    elseif first == 126
      return if #buf < 4
      length = bor lshift(byte(buf, 3), 8), byte(buf, 4)
      l = 4
    elseif first == 127
      if #buf < 10 then return
      length = 0
      for i = 3, 10
        length = bor length, lshift(byte(buf, i), (10 - i) * 8)
      l = 10
    if masking
      return if #buf < l + 4
      key = {}
      key[1] = byte buf, l + 1
      key[2] = byte buf, l + 2
      key[3] = byte buf, l + 3
      key[4] = byte buf, l + 4
      l = l + 4
    if #buf < l + length
      return
    payload = slice l, l + length
    if masking
      tbl = {}
      for i = 1, length
        push tbl, bxor(byte(payload, i), key[(i - 1) % 4])
      payload = join tbl, ''
    data = slice(buf, l + length)
    p('ok', masking, length)
    if opcode == 1
      if @session and #payload > 0
        status, message = pcall JSON.decode, payload
        p('DECODE', payload, status, message)
        return @do_reasoned_close(1002, 'Broken framing.') if not status
        -- process message
        @session\onmessage messages
      ondata()
      return
    elseif opcode == 8
      if #payload >= 2
        status = bor lshift(byte(payload, 1), 8), byte(payload, 2)
      else
        status = 1002
      if #payload > 2
        reason = slice payload, 3
      else
        reason = 'Connection closed by user'
      @do_reasoned_close status, reason
    return
  --@req\once 'uprade', () ->
  @req\on 'data', ondata
  @send_frame = (payload) =>
    p('SEND', payload)
    pl = #payload
    a = {}
    [==[
    push a, 128 + 1
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
    @write_frame join a, ''

return {
  WebHandshakeHixie76: WebHandshakeHixie76
  WebHandshake8: WebHandshake8
}
