--
-- creationix/Stack ported
--

module = {}

--
-- handles errors inside stack, both exceptions and soft errors
--
module.error_handler = (req, res, err) ->
  if err
    reason = err
    print '\n' .. reason .. '\n'
    res\send 500, reason, ['Content-Type']: 'text/plain'
  else
    res\send 404, nil, ['Content-Type']: 'text/plain'

--
-- given table of middleware layers, returns the function
-- suitable to pass as HTTP request handler
--
module.create = (layers) ->
  error_handler = module.error_handler
  handle = error_handler
  for i = #layers,1,-1
    layer = layers[i]
    child = handle
    handle = (req, res) ->
      fn = (err) ->
        if err
          error_handler req, res, err
        else
          child req, res
      status, err = pcall(layer, req, res, fn)
      error_handler req, res, err if err
  handle

--
-- given table of middleware layers, creates and returns listening
-- HTTP server.
-- E.g. create_server({layer1,layer2,...}, 3001, '127.0.0.1')
--
module.create_server = (layers, port, host) ->
  stack = module.create(layers)
  server = require('http').create_server(host or '0.0.0.0', port, stack)
  server

--
-- lazy accessors
--
setmetatable module, {
  __index: (table, key) -> require('lib/stack/' .. key)
}

-- export module
return module
