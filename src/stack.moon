--
-- creationix/Stack ported
--

class Stack

  --
  -- lazily load specified library layer and return its setup function
  --
  -- N.B. static method
  use: (lib_layer_name) ->
    require('lib/stack/' .. lib_layer_name)

  --
  -- given table of middleware layers, returns the function
  -- suitable to pass as HTTP request handler
  --
  new: (layers) =>
    error_handler = @error_handler
    handler = error_handler
    for i = #layers,1,-1
      layer = layers[i]
      child = handler
      handler = (req, res) ->
        fn = (err) ->
          if err
            error_handler req, res, err
          else
            child req, res
        status, err = pcall(layer, req, res, fn)
        error_handler req, res, err if err
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

-----------------------------------------------------------
--
-- augment Request and Response
--
-----------------------------------------------------------

Request = require 'request'
Response = require 'response'
FS = require 'fs'

noop = () ->

Response.prototype.safe_write = (chunk, cb = noop) =>
  @write chunk, (err, result) ->
    return cb err, result if not err
    -- retry on EBUSY
    if err == 16
      @safe_write chunk, cb
    else
      p('WRITE FAILED', err)
      cb err

Response.prototype.send = (code, data, headers) =>
  h = @headers or {}
  for k, v in pairs(headers or {})
    h[k] = v
  p('send', code, data, h, '\n')
  @write_head code, h or {}
  [==[
  if data
    @safe_write data, () -> @close()
  else
    @close()
  ]==]
  if data
    @write data
  @close()

-- defines response header
Response.prototype.set_header = (name, value) =>
  @headers = {} if not @headers
  -- TODO: multiple values should glue
  @headers[name] = value

-- serve 500 error and reason
Response.prototype.fail = (reason) =>
  @send 500, reason, ['Content-Type']: 'text/plain; charset=UTF-8'

-- serve 404 error
Response.prototype.serve_not_found = () =>
  @send 404

-- serve 304 not modified
Response.prototype.serve_not_modified = (headers) =>
  @send 304, nil, headers

-- serve 416 invalid range
Response.prototype.serve_invalid_range = (size) =>
  @send 416, nil, {
    ['Content-Range']: 'bytes=*/' .. size
  }

-- render file named `template` with data from `data` table
-- and serve it with status 200 as text/html
Response.prototype.render = (template, data = {}, options = {}) =>
  d('render', template, data)

  FS.read_file template, (err, text) ->
    if err
      @serve_not_found()
    else
      html = (text % data)
      @send 200, html, {
        ['Content-Type']: 'text/html; charset=UTF-8'
        ['Content-Length']: #html
      }

-- export module
return Stack

