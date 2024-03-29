local Server = require('server')
local SockJS = require('sockjs-luvit')
local _error = error
local error
error = function(...)
  return p('BADBADBAD ERROR', ...)
end
local _ = [==[  (req, res, continue) ->
    p(req.method)
    continue()
]==]
local http_stack_layers
http_stack_layers = function()
  return {
    Server.use('route')({
      {
        'GET /$',
        function(self, nxt)
          p('FOO')
          return self:render('index.html', self.req.context)
        end
      }
    }),
    Server.use('static')('/public/', 'public/', { }),
    SockJS()
  }
end
SockJS('/echo', {
  sockjs_url = '/public/sockjs.js',
  onconnection = function(conn)
    p('CONNE', conn.sid, conn.id)
    return conn:on('message', function(m)
      return conn:send(m)
    end)
  end
})
SockJS('/close', {
  sockjs_url = '/public/sockjs.js',
  onconnection = function(conn)
    p('CONNC', conn.sid, conn.id)
    return conn:close(3000, 'Go away!')
  end
})
SockJS('/amplify', {
  sockjs_url = '/public/sockjs.js',
  onconnection = function(conn)
    p('CONNA', conn.sid, conn.id)
    return conn:on('message', function(m)
      return conn:send({
        m = rep(2)
      })
    end)
  end
})
local s1 = Server.run(http_stack_layers(), 8080)
print('Server listening at http://localhost:8080/')
require('repl')
