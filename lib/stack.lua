--
-- creationix/Stack ported
--

local exports = {}

--
-- handles errors inside stack, both exceptions and soft errors
--
function exports.error_handler(req, res, err)
  if err then
    local reason = err
    print('\n' .. reason .. '\n')
    res:send(500, reason, {['Content-Type'] = 'text/plain'})
  else
    res:send(404, nil, {['Content-Type'] = 'text/plain'})
  end
end

--
-- given table of middleware layers, returns the function
-- suitable to pass as HTTP request handler
--
function exports.create(layers)
  local error_handler = exports.error_handler
  local handle = error_handler
  for i = #layers,1,-1 do
    local layer = layers[i]
    local child = handle
    handle = function(req, res)
      local status, err = pcall(layer, req, res, function(err)
        if err then return error_handler(req, res, err) end
        child(req, res)
      end)
      if err then error_handler(req, res, err) end
    end
  end
  return handle
end

--
-- given table of middleware layers, creates and returns listening
-- HTTP server.
-- E.g. create_server({layer1,layer2,...}, 3001, '127.0.0.1')
--
function exports.create_server(layers, port, host)
  local stack = exports.create(layers)
  local server = require('http').create_server(host or '0.0.0.0', port, stack)
  return server
end

--
--
exports.health = require('lib/stack/health')
exports.static = require('lib/stack/static')
exports.session = require('lib/stack/session').session
exports.auth = require('lib/stack/session').auth
exports.body = require('lib/stack/body')
exports.rest = require('lib/stack/rest')
exports.route = require('lib/stack/route')

-- export module
return exports
