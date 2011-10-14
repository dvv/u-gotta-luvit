require('lib/util')
local Stack = require('lib/stack')
local Math = require('math')
local _ = [==[BaseUrlGreeting
---ChunkingTest
EventSource
HtmlFile
IframePage
JsonPolling
Protocol
SessionURLs
WebsocketHixie76
WebsocketHttpErrors
WebsocketHybi10
XhrPolling
XhrStreaming
]==]
local layers
layers = function()
  return {
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
        return p('CONN', conn)
      end
    }),
    Stack.use('route')({
      ['GET /$'] = function(self, nxt)
        return self:render('index.html', self.req.context)
      end
    }),
    Stack.use('static')('/public/', 'public/', {
      is_cacheable = function(file)
        return true
      end
    })
  }
end
local s1 = Stack(layers()):run(8080)
print('Server listening at http://localhost:8080/')
