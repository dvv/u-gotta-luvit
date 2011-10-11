local module = { }
module.error_handler = function(req, res, err)
  if err then
    local reason = err
    print('\n' .. reason .. '\n')
    return res:send(500, reason, {
      ['Content-Type'] = 'text/plain'
    })
  else
    return res:send(404, nil, {
      ['Content-Type'] = 'text/plain'
    })
  end
end
module.create = function(layers)
  local error_handler = module.error_handler
  local handle = error_handler
  for i = #layers, 1, -1 do
    local layer = layers[i]
    local child = handle
    handle = function(req, res)
      local fn
      fn = function(err)
        if err then
          return error_handler(req, res, err)
        else
          return child(req, res)
        end
      end
      local status, err = pcall(layer, req, res, fn)
      if err then
        return error_handler(req, res, err)
      end
    end
  end
  return handle
end
module.create_server = function(layers, port, host)
  local stack = module.create(layers)
  local server = require('http').create_server(host or '0.0.0.0', port, stack)
  return server
end
setmetatable(module, {
  __index = function(table, key)
    return require('lib/stack/' .. key)
  end
})
return module
