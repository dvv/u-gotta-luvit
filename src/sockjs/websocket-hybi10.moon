--
-- http://tools.ietf.org/html/draft-ietf-hybi-thewebsocketprotocol-10
--

import get_digest from require 'openssl'
import floor, random from require 'math'
import band, bor, bxor, rshift, lshift from require 'bit'
slice = String.sub
byte = String.byte
push = Table.insert
join = Table.concat
JSON = require 'cjson'

verify_secret = (key) ->
  data = (String.match(key, '(%S+)')) .. '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'
  dg = get_digest('sha1')\init()
  dg\update data
  r = dg\final()
  dg\cleanup()
  r

rand256 = () -> floor(random() * 256)

return (origin, location, cb) =>
  p('SHAKE8', origin, location)
  @write_head 101, {
    ['Upgrade']: 'WebSocket'
    ['Connection']: 'Upgrade'
    ['Sec-WebSocket-Accept']: String.base64(verify_secret(@req.headers['sec-websocket-key']))
    --TODO['Sec-WebSocket-Protocol']: @req.headers['sec-websocket-protocol'].split('[^,]*')
  }
  @has_body = true -- override bodyless assumption on 101
  -- parse incoming data
  data = ''
  ondata = (chunk) ->
    p('DATA', chunk, chunk and #chunk, chunk and chunk\tohex())
    if chunk
      data = data .. chunk
    -- TODO: support length in framing
    return if #data < 2
    --
    buf = data
    status = nil
    reason = nil
    first = band byte(buf, 2), 0x7F
    if band(byte(buf, 1), 0x80) != 0x80
      error('fin flag not set')
      @do_reasoned_close 1002, 'Fin flag not set'
      return
    opcode = band byte(buf, 1), 0x0F
    p('OPCODE', opcode)
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
    key = {}
    masking = band(byte(buf, 2), 0x80) != 0
    p('MASKING', masking)
    p('FIRST', first)
    if first < 126
      length = first
      l = 2
    else if first == 126
      return if #buf < 4
      length = bor lshift(byte(buf, 3), 8), byte(buf, 4)
      l = 4
    else if first == 127
      if #buf < 10 then return
      length = 0
      for i = 3, 10
        length = bor length, lshift(byte(buf, i), (10 - i) * 8)
      l = 10
    if masking
      return if #buf < l + 4
      key[1] = byte(buf, l + 1)
      key[2] = byte(buf, l + 2)
      key[3] = byte(buf, l + 3)
      key[4] = byte(buf, l + 4)
      l = l + 4
    if #buf < l + length
      return
    payload = slice buf, l + 1, l + length
    p('PAYLOAD?', payload, #payload, payload\tohex(), length)
    tbl = {}
    if masking
      for i = 1, length
        push tbl, bxor(byte(payload, i), key[(i - 1) % 4 + 1])
      payload = String.char unpack tbl
    p('PAYLOAD!', payload, #payload, tbl, #tbl)
    data = slice buf, l + length + 1
    p('ok', masking, length)
    if opcode == 1
      if @session and #payload > 0
        status, message = pcall JSON.decode, payload
        p('DECODE', payload, status, message)
        return @do_reasoned_close(1002, 'Broken framing.') if not status
        -- process message
        @session\onmessage message
      ondata()
      return
    else if opcode == 8
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
  @req\on 'data', ondata
  @send_frame = (payload) =>
    p('SEND', payload)
    pl = #payload
    a = {}
    push a, 128 + 1
    push a, 0x80 -- N.B. masking 0x80?
    if pl < 126
      a[2] = bor a[2], pl
    else if pl < 65536
      a[2] = bor a[2], 126
      push a, rshift(pl, 8) % 256
      push a, pl % 256
    [==[
    else
      pl2 = pl
      a[2] = bor a[2], 127
      for i in 7, -1, -1
        a[l+i] = pl2 % 256
        pl2 = rshift pl2, 8
    ]==]
    key = {rand256(), rand256(), rand256(), rand256()}
    push a, key[1]
    push a, key[2]
    push a, key[3]
    push a, key[4]
    for i = 1, pl
      push a, bxor(byte(payload, i), key[(i - 1) % 4 + 1])
    -- N.B. plain write(), not write_frame(), not not account for max_size
    a = String.char unpack a
    p('WRITE', a, a\tohex())
    @write a
  cb() if cb
