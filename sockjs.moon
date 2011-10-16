EventEmitter = setmetatable({}, {__index: require('emitter').meta})

require 'lib/util'
Stack = require 'lib/stack'
Math = require 'math'


-- tests
[==[
BaseUrlGreeting IframePage Protocol SessionURLs ChunkingTest XhrPolling JsonPolling EventSource HtmlFile XhrStreaming
BaseUrlGreeting
---ChunkingTest
IframePage
XhrPolling
JsonPolling
Protocol
SessionURLs
EventSource
HtmlFile
XhrStreaming
WebsocketHixie76
WebsocketHttpErrors
WebsocketHybi10
]==]


layers = () -> {

  (req, res, nxt) ->
    res.req = req
    nxt()

  -- /echo
  Stack.use('sockjs')({
    prefix: '/echo'
    sockjs_url: '/public/sockjs.js' -- TODO: no default
    heartbeat_delay: 25000
    disconnect_delay: 5000
    response_limit: 128*1024
    origins: {'*:*'}
    disabled_transports: {}
    cache_age: 365 * 24 * 60 * 60 -- one year
    get_nonce: () -> Math.random()
    onconnection: (conn) ->
      p('CONN') --, conn)
      conn\on 'message', (m) -> conn\send m
  })

  -- serve chrome page
  Stack.use('route')({
    ['GET /$']: (nxt) =>
      @render 'index.html', @req.context
  })

  -- serve static files
  Stack.use('static')('/public/', 'public/', {
    -- should the `file` contents be cached?
    --is_cacheable: (file) file.size <= 65536
    --is_cacheable: (file) -> true
  })

}

s1 = Stack(layers())\run(8080)
print('Server listening at http://localhost:8080/')
