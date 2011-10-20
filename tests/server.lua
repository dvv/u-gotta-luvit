require('lib/util')
local Stack = require('lib/stack')
local Math = require('math')
local layers
layers = function()
  return {
    Stack.use('route')(Stack.use('sockjs')({
      prefix = '/echo',
      sockjs_url = '/sockjs.js',
      response_limit = 4096,
      onconnection = function(conn)
        return conn:on('message', function(m)
          return conn:send(m)
        end)
      end
    })),
    Stack.use('route')(Stack.use('sockjs')({
      prefix = '/amplify',
      sockjs_url = '/sockjs.js',
      response_limit = 4096,
      onconnection = function(conn)
        return conn:on('message', function(m)
          local n
          status, n = Math.floor(tonumber(m))
          if not status then
            p('MATH FAILED', m, n)
            error(m)
          end
          n = (n > 0 and n < 19) and n or 1
          conn:send(String.rep('x', Math.pow(2, n) + 1))
        end)
      end
    })),
    Stack.use('route')({
      ['GET /$'] = function(self, nxt)
        return self:render('index.html', self.req.context)
      end
    }),
    Stack.use('static')('/', '', { })
  }
end
local s1 = Stack(layers()):run(8080)
print('Point your browser to http://localhost:8080/')
