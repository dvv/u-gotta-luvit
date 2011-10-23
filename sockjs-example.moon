Server = require 'server'
SockJS = require 'sockjs-luvit'

_error = error
error = (...) -> p('BADBADBAD ERROR', ...)

[==[
  (req, res, continue) ->
    p(req.method)
    continue()
]==]

http_stack_layers = () -> {

  -- serve chrome page
  Server.use('route')({{
    'GET /$'
    (nxt) =>
      p('FOO')
      @render 'index.html', @req.context
  }})

  -- serve static files
  Server.use('static')('/public/', 'public/', {
    --is_cacheable: (file) -> true
  })

  -- SockJS servers handlers
  SockJS()

}

-- /echo
SockJS('/echo', {
  sockjs_url: '/public/sockjs.js'
  onconnection: (conn) ->
    p('CONNE', conn.sid, conn.id)
    conn\on 'message', (m) -> conn\send m
})

-- /close
SockJS('/close', {
  sockjs_url: '/public/sockjs.js'
  onconnection: (conn) ->
    p('CONNC', conn.sid, conn.id)
    conn\close 3000, 'Go away!'
})

-- /amplify
SockJS('/amplify', {
  sockjs_url: '/public/sockjs.js'
  onconnection: (conn) ->
    p('CONNA', conn.sid, conn.id)
    conn\on 'message', (m) -> conn\send m:rep(2)
})

s1 = Server.run http_stack_layers(), 8080
print 'Server listening at http://localhost:8080/'
require('repl')
