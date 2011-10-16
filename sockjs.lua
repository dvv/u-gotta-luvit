local EventEmitter = setmetatable({ }, {
  __index = require('emitter').meta
})
require('lib/util')
local Stack = require('lib/stack')
local Math = require('math')
local _ = [==[BaseUrlGreeting IframePage Protocol SessionURLs ChunkingTest XhrPolling JsonPolling EventSource HtmlFile XhrStreaming
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
local layers
layers = function()
  return {
    function(req, res, nxt)
      res.req = req
      return nxt()
    end,
    Stack.use('sockjs')({
      prefix = '/echo',
      sockjs_url = '/public/sockjs.js',
      heartbeat_delay = 25000,
      disconnect_delay = 5000,
      response_limit = 128 * 1024,
      origins = {
        '*:*'
      },
      disabled_transports = { },
      cache_age = 365 * 24 * 60 * 60,
      get_nonce = function()
        return Math.random()
      end,
      onconnection = function(conn)
        p('CONN')
        return conn:on('message', function(m)
          return conn:send(m)
        end)
      end
    }),
    Stack.use('route')({
      ['GET /$'] = function(self, nxt)
        return self:render('index.html', self.req.context)
      end
    }),
    Stack.use('static')('/public/', 'public/', { })
  }
end
local s1 = Stack(layers()):run(8080)
print('Server listening at http://localhost:8080/')
