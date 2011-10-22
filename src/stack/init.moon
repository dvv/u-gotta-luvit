--
-- creationix/Stack ported
--

require './request'
require './response'

library = {
  auth: require './auth'
  body: require './body'
  health: require './health'
  rest: require './rest'
  route: require './route'
  session: require './session'
  static: require './static'
  sockjs: require './../sockjs/'
}

class Stack

  --
  -- lazily load specified library layer and return its setup function
  --
  -- N.B. static method
  use: (lib_layer_name) -> library[lib_layer_name]
  --  require('./' .. lib_layer_name)

  --
  -- given table of middleware layers, returns the function
  -- suitable to pass as HTTP request handler
  --
  new: (layers) =>
    error_handler = @error_handler
    handler = error_handler
    for i = #layers, 1, -1
      layer = layers[i]
      child = handler
      handler = (req, res) ->
        fn = (err) ->
          if err
            error_handler req, res, err
          else
            child req, res
        status, err = pcall(layer, req, res, fn)
        error_handler req, res, err if not status
    @handler = handler

  --
  -- handle errors inside stack, both exceptions and soft errors
  --
  error_handler: (req, res, err) ->
    if err
      reason = err
      print '\n' .. reason .. '\n'
      res\fail reason
    else
      res\send 404

  --
  -- creates and returns listening HTTP server
  --
  run: (port = 80, host = '0.0.0.0') =>
    server = require('http').create_server(host, port, @handler)
    server

-- export module
return Stack
