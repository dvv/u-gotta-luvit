--
-- ReST resource routing
--

local String = require('lib/string')
local Table = require('table')
local JSON = require('cjson')

function is_array(obj)
  return type(obj) == 'table' and Table.maxn(obj) > 0
end

function is_hash(obj)
  return type(obj) == 'table' and Table.maxn(obj) == 0
end

function setup(mount, options)

  -- defaults
  if not mount then mount = '/rpc/' end
  if not options then options = {} end

  -- mount should end with '/'
  if mount:sub(#mount) ~= '/' then mount = mount .. '/' end
  local mlen = #mount

  -- whether PUT /Foo/_new means POST /Foo
  -- useful to free POST verb for pure PRC calls
  local brand_new_id = options.put_new and options.put_new or {}

  -- handler
  return function(req, res, nxt)

    -- defaults
    if not req.uri then req.uri = req.url:url_parse() end

    -- none of our business unless url starts with `mount`
    local path = req.uri.pathname
    if path:sub(1, mlen) ~= mount then return nxt() end

    -- split pathname into resource name and id
    local resource, id
    path:sub(mlen + 1):gsub('[^/]+', function(part)
      if not resource then resource = part:url_decode()
      elseif not id then id = part:url_decode()
      end
    end)
--p('parts', resource, id)

    --
    -- determine handler method and its parameters
    --

    -- N.B. support X-HTTP-Method-Override: to ease REST for dumb clients
    local verb = req.headers['X-HTTP-Method-Override'] or req.method
    local method, params

    -- query
    if verb == 'GET' then
      method = 'get'
      -- get by ID
      if id and id ~= brand_new_id then
        params = {id}
      -- query
      else
        method = 'query'
        -- bulk get via POST X-HTTP-Method-Override: GET
        if is_array(req.body) then
          params = {req.body}
        -- query by RQL
        else
          params = {req.uri.search}
        end
      end

    -- create new / update resource
    elseif verb == 'PUT' then
      method = 'update'
      if id then
        -- add new
        if id == brand_new_id then
          method = 'add'
          params = {req.body}
        -- update by ID
        else
          params = {id, req.body}
        end
      else
        -- bulk update via POST X-HTTP-Method-Override: PUT
        if is_array(req.body) and is_array(req.body[1]) then
          params = {req.body[1], req.body[2]}
        -- update by RQL
        else
          params = {req.uri.search, req.body}
        end
      end

    -- remove resource
    elseif verb == 'DELETE' then
      method = 'remove'
      if id and id ~= brand_new_id then
        params = {id}
      else
        -- bulk remove via POST X-HTTP-Method-Override: DELETE
        if is_array(req.body) then
          params = {req.body}
        -- remove by RQL
        else
          params = {req.uri.search}
        end
      end

    -- arbitrary RPC to resource
    elseif verb == 'POST' then
      -- if creation is via PUT, POST is solely for RPC
      -- if `req.body` has truthy `jsonrpc` key -- try RPC
      if options.put_new or req.body.jsonrpc then
        -- RPC
        method = req.body.method
        params = req.body.params
      -- else POST is solely for creation
      else
        -- add
        method = 'add'
        params = {req.body}
      end

    -- unsupported verb
    else
    end
--p('PARSED', resource, method, params)

    -- called after handler finishes
    function respond(err, result)
--p('RPC!', err, result, options, req.body)
      local response
      -- JSON-RPC response
      if options.jsonrpc or req.body.jsonrpc then
        response = {}
        if err then
          response.error = err
        elseif result == nil then
          response.result = true
        else
          response.result = result
        end
        res:write_head(200, {['Content-Type'] = 'application/json'})
      -- plain response
      else
        if err then
          res:write_head(type(err) == 'number' and err or 406, {})
        elseif result == nil then
          res:write_head(404, {})
        else
          response = result
          res:write_head(200, {['Content-Type'] = 'application/json'})
        end
      end
--p('RPC!!', response)
      if response then res:write(JSON.encode(response)) end
      res:finish()
    end

    --
    -- find the handler
    --

    -- bail out unless resource is found
    local context = req.context or options.context or {}
    resource = context[resource]
    if not resource then
      respond(404)
      return
    end
    -- bail out unless resource method is supported
    if not resource[method] then
      respond(405)
      return
    end

    --
    -- call the handler. signature is fn(params..., step)
    --

    if options.pass_context then Table.insert(params, 1, context) end
    Table.insert(params, respond)
--p('RPC?', params)
    resource[method](unpack(params));

  end

end

return setup
