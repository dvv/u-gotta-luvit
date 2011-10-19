--
-- http://tools.ietf.org/html/draft-hixie-thewebsocketprotocol-76
--

import get_digest from require 'openssl'
import floor from require 'math'
import band, bor, rshift, lshift from require 'bit'
slice = String.sub
JSON = require 'cjson'

validate_hixie76_crypto = (req_headers, nonce) ->
  k1 = req_headers['sec-websocket-key1']
  k2 = req_headers['sec-websocket-key2']
  return false if not k1 or not k2
  md5 = get_digest('md5')\init()
  u = ''
  for k in *{k1, k2}
    n = tonumber (String.gsub(k, '[^%d]', '')), 10
    spaces = #(String.gsub(k, '[^ ]', ''))
    return false if spaces == 0 or n % spaces != 0
    n = n / spaces
    -- TODO: use bitop!
    --s = String.char(rshift(n, 24) % 0xFF, rshift(n, 16) % 0xFF, rshift(n, 8) % 0xFF, n % 0xFF)
    s = String.fromhex(String.format '%08x', n)
    p('S!!', n, String.tohex(s), #s)
    u = u .. s
  u = u .. nonce
  p('U', u, String.tohex(u), #u)
  md5\update u
  a = md5\final()
  md5\cleanup()
  p('MD5', String.tohex a)
  a

WebHandshakeHixie76 = (origin, location, cb) =>
  p('SHAKE76', origin, location)
  @sec = @req.headers['sec-websocket-key1']
  wsp = @sec and @req.headers['sec-websocket-protocol']
  prefix = @sec and 'Sec-' or ''
  blob = {
    'HTTP/1.1 101 WebSocket Protocol Handshake'
    'Upgrade: WebSocket'
    'Connection: Upgrade'
    prefix .. 'WebSocket-Origin: ' .. origin
    prefix .. 'WebSocket-Location: ' .. location
  }
  if wsp
    Table.insert blob, ('Sec-WebSocket-Protocol: ' .. @req.headers['sec-websocket-protocol'].split('[^,]*'))

  @write(Table.concat(blob, '\r\n') .. '\r\n\r\n')
  data = ''
  -- parse incoming data
  ondata = (chunk) ->
    p('DATA', chunk)
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
            status, messages = pcall JSON.decode, payload
            p('DECODE', payload, status, messages)
            return @do_reasoned_close(1002, 'Broken framing.') if not status
            -- process messages
            if type(messages) == 'table'
              for message in *messages
                @session\onmessage message
            else
              @session\onmessage messages
          ondata()
          return
      -- wait for more data
      return
    else if String.byte(buf, 1) == 255 and String.byte(buf, 2) == 0
      @do_reasoned_close 1001, 'Socket closed by the client'
    else
      @do_reasoned_close 1002, 'Broken framing'
    return
  wait_for_nonce = (chunk) ->
    p('WAIT', chunk, String.tohex chunk)
    data = data .. chunk
    if @sec == false or #data >= 8
      @remove_listener 'data', wait_for_nonce
      if @sec
        nonce = slice data, 1, 8
        data = slice data, 9
        reply = validate_hixie76_crypto @req.headers, nonce
        if not reply
          p('NOTREPLY')
          @do_reasoned_close()
          return
        p('REPLY', reply, #reply)
        @on 'data', ondata
        status, err = pcall @write, self, reply
        p('REPLYWRITTEN', status, err)
        cb() if cb
    return
  @req\on 'data', wait_for_nonce
  @send_frame = (payload) =>
    p('SEND', payload)
    @write_frame '\000' .. payload .. '\255'
    --@write_frame '\000'
    --@write_frame payload
    --@write_frame '\255'

verify_hybi_secret = (key) ->
  data = (String.match(key, '(%S+)')) .. '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'
  dg = get_digest('sha1')\init()
  dg\update data
  r = dg\final()
  dg\cleanup()
  r

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
  data = ''
  -- parse incoming data
  ondata = (chunk) ->
    p('DATA', chunk)
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
            status, messages = pcall JSON.decode, payload
            p('DECODE', payload, status, messages)
            return @do_reasoned_close(1002, 'Broken framing.') if not status
            -- process messages
            if type(messages) == 'table'
              for message in *messages
                @session\onmessage message
            else
              @session\onmessage messages
          ondata()
          return
      -- wait for more data
      return
    else if String.byte(buf, 1) == 255 and String.byte(buf, 2) == 0
      @do_reasoned_close 1001, 'Socket closed by the client'
    else
      @do_reasoned_close 1002, 'Broken framing'
    return
  @req\on 'data', ondata
  @send_frame = (payload) =>
    p('SEND', payload)
    @write_frame '\000' .. payload .. '\255'
    --@write_frame '\000'
    --@write_frame payload
    --@write_frame '\255'

return {
  WebHandshakeHixie76: WebHandshakeHixie76
  WebHandshake8: WebHandshake8
}
