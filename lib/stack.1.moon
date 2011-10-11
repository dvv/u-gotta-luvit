--
-- creationix/Stack ported
--

class A

  --
  -- given table of middleware layers, returns the function
  -- suitable to pass as HTTP request handler
  --
  new: (layers) =>
    error_handler = @error_handler
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
  -- handles errors inside stack, both exceptions and soft errors
  --
  error_handler: (req, res, err) ->
    if err
      reason = err
      print '\n' .. reason .. '\n'
      res\send 500, reason, ['Content-Type']: 'text/plain'
    else
      res\send 404, nil, ['Content-Type']: 'text/plain'

  --
  -- given table of middleware layers, creates and returns listening
  -- HTTP server.
  -- E.g. create_server({layer1,layer2,...}, 3001, '127.0.0.1')
  --
  server: (layers, port, host) =>
    stack = @create layers
    server = require('http').create_server(host or '0.0.0.0', port, stack)
    server

--
-- lazy accessors
--
setmetatable Stack, {
  __index: (table, key) -> require('lib/stack/' .. key)
}

-- export module
return Stack
