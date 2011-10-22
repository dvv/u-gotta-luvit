require './lib/util'
Stack = require './lib/stack'
SockJS = require './lib/sockjs'

_error = error
error = (...) -> p('BADBADBAD ERROR', ...)

http_stack_layers = () -> {


  -- serve chrome page
  Stack.use('route')({{
    'GET /$'
    (nxt) =>
      @render 'index.html', @req.context
  }})

  -- serve static files
  Stack.use('static')('/public/', 'public/', {
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

s1 = Stack(http_stack_layers!)\run 8080
print 'Server listening at http://localhost:8080/'
require('repl')
