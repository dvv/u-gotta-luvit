--
-- http://tools.ietf.org/html/draft-hixie-thewebsocketprotocol-76
--

import get_digest from require 'openssl'
import floor from require 'math'
slice = String.sub

validate_crypto = (req_headers, nonce) ->
  k1 = req_headers['sec-websocket-key1']
  k2 = req_headers['sec-websocket-key2']

  if not k1 or not k2
    return false

  md5 = get_digest('md5')\init()
  for k in *{k1, k2}
    p('K', k)
    n = tonumber (String.gsub(k, '[^%d]', '')), 10
    p('N', n)
    spaces = #(String.gsub(k, '[^ ]', ''))
    p('S?', spaces)
    if spaces == 0 or n % spaces != 0
      return false
    n = n / spaces
    p('S!', n, spaces, floor(n/16777216)%255, floor(n/65536)%255, floor(n/256)%255, n%255)
    s = String.char(floor(n/16777216)%255, floor(n/65536)%255, floor(n/256)%255, n%255)
    md5\update s
  md5\update nonce
  md5\final()

handshake = (origin, location, cb) =>
  p('SHAKE', origin, location, @req.head)
  @sec = @req.headers['sec-websocket-key1']
  wsp = @sec and @req.headers['sec-websocket-protocol']
  prefix = @sec and 'Sec-' or ''
  blob = {
    'HTTP/1.1 101 WebSocket Protocol Handshake'
    'Upgrade: WebSocket'
    'Connection: Upgrade'
    --'Transfer-Encoding: chunked'
    prefix .. 'WebSocket-Origin: ' .. origin
    prefix .. 'WebSocket-Location: ' .. location
  }
  if wsp
    Table.insert blob, ('Sec-WebSocket-Protocol: ' .. @req.headers['sec-websocket-protocol'].split('[^,]*'))

  @write(Table.concat(blob, '\r\n') .. '\r\n\r\n')
  --@set_chunked()
  data = ''
  -- parse incoming data
  ondata = (chunk) ->
    p('DATA', chunk)
    if chunk
      data = data .. chunk
    buf = data
    return if buf.length == 0
    if String.byte(buf, 1) == 0
      for i = 2, buf.length
        if String.byte(buf, i) == 255
          payload = String.sub(buf, 1, i)
          data = String.sub(buf, i + 1)
          if @session and #payload > 0
            status, data = pcall JSON.decode, payload
            return @do_reasoned_close(1002, 'Broken framing.') if not status
            @session.onmessage message
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
    p('WAIT', chunk)
    data = data .. chunk
    if @sec == false or #data >= 8
      @remove_listener 'data', wait_for_nonce
      if @sec
        nonce = slice data, 1, 8
        data = slice data, 9
        reply = validate_crypto @req.headers, nonce
        if not reply
          p('NOTREPLY')
          @do_reasoned_close()
          return
        p('REPLY', reply)
        @on 'data', ondata
        status, err = pcall @write, self, reply
        p('REPLYWRITTEN', status, err)
        cb() if cb
    return
  @on 'data', wait_for_nonce
  wait_for_nonce(@req.head or '')

--return WebHandshakeHixie76
return {
  handshake: handshake
}
