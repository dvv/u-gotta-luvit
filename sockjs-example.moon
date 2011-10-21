require 'lib/util'
Stack = require 'lib/stack/'

_error = error
error = (...) -> p('BADBADBAD ERROR', ...)

layers = () -> {

  -- /echo
  Stack.use('route')(Stack.use('sockjs')({
    prefix: '/echo'
    sockjs_url: '/public/sockjs.js'
    onconnection: (conn) ->
      p('CONN', conn.sid)
      conn\on 'message', (m) -> conn\send m
  }))

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

}

s1 = Stack(layers!)\run 8080
print 'Server listening at http://localhost:8080/'
