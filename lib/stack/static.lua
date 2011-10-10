--
-- static file server
--

local UV = require('uv')
local FS = require('fs')
local OS = require('os')
local Table = require('table')
local MIME = require('lib/mime')

--
-- open file `path`, seek to `offset` octets from beginning and
-- read `size` subsequent octets.
-- call `progress` on each read chunk
--
local CHUNK_SIZE = 16384 --4096
local function noop() end
function stream_file(path, offset, size, progress, callback)
  UV.fs_open(path, 'r', '0666', function (err, fd)
    if err then return callback(err) end
    local function readchunk()
      local chunk_size = size < CHUNK_SIZE and size or CHUNK_SIZE
      UV.fs_read(fd, offset, chunk_size, function (err, chunk)
        if err or #chunk == 0 then
          callback(err)
          UV.fs_close(fd, noop)
        else
          chunk_size = #chunk
          offset = offset + chunk_size
          size = size - chunk_size
          if progress then
            progress(chunk, function()
              readchunk()
            end)
          end
        end
      end)
    end
    readchunk()
  end)
end

--
-- setup request handler
--
function exports(mount, root, options)

  if not options then options = {} end
  local max_age = options.max_age or 0

  -- given Range: header, return start, end numeric pair
  function parse_range(range, size)
    local start, stop, partial
    partial = false
    if range then
      -- parse bytes=start-stop
      start, stop = range:match('bytes=(%d*)-?(%d*)')
      partial = true
    end
    start = tonumber(start) or 0
    stop = tonumber(stop) or size - 1
    return start, stop, partial
  end

  -- serve 404 error
  function serve_not_found(res)
    res:write_head(404, {})
    res:finish()
  end

  -- serve 304 not modified
  function serve_not_modified(res, file)
    res:write_head(304, file.headers)
    res:finish()
  end

  -- serve 416 invalid range
  function serve_invalid_range(res, file)
    res:write_head(416, {
      ['Content-Range'] = 'bytes=*/' .. file.size
    })
    res:finish()
  end

  -- cache entries table
  local cache = {}

  -- handler for 'change' event of all file watchers
  function invalidate_cache_entry(status, event, path)
d("on_change", {status=status,event=event,path=path}, self)
    -- invalidate cache entry and free the watcher
    if cache[path] then
      cache[path].watch:close()
      cache[path] = nil
    end
  end

--[[
debugging stuff. wanna know how many concurrent requests do some things
before cache entry is set
]]--
local NUM1 = 0
local NUM2 = 0

  -- given file, serve contents, honor Range: header
  function serve(res, file, range, cache_it)
    -- adjust headers
    local headers = clone(file.headers)
    headers['Date'] = OS.date('%c')
    --
    local size = file.size
    local start = 0
    local stop = size - 1
    -- range specified? adjust headers and http status for response
    if range then
      start, stop = parse_range(range, size)
      -- limit range by file size
      if stop >= size then stop = size - 1 end
      -- check range validity
      if stop < start then
        serve_invalid_range(res, file)
        return
      end
      -- adjust Content-Length:
      headers['Content-Length'] = stop - start + 1
      -- append Content-Range:
      headers['Content-Range'] = ('bytes=%d-%d/%d'):format(start, stop, size)
      res:write_head(206, headers)
    else
      res:write_head(200, headers)
    end
    -- serve from cache, if available
--d("serve", headers)
    if file.data then
      res:safe_write(range and file.data.sub(start + 1, stop - start + 1) or file.data, function(...)
--d('write', ...)
        res:finish()
      end)
    -- otherwise stream and possibly cache
    else
      -- N.B. don't cache if range specified
      if range then cache_it = false end
      local index = 1
      local parts = {}
      stream_file(file.name, start, stop - start + 1,
        -- progress
        function(chunk, cb)
          if cache_it then
            parts[index] = chunk
            index = index + 1
          end
          res:safe_write(chunk, cb)
        end,
        -- eof
        function(err)
          res:finish()
          if cache_it then
NUM2 = NUM2 + 1
d("cached", NUM2, {path=filename, headers=file.headers})
            file.data = Table.concat(parts, '')
          end
        end
      )
    end
  end

  --
  -- request handler
  --
  return function(req, res, nxt)

    -- none of our business unless method is GET
    -- and url starts with `mount`
    local mount_found_at = req.url:find(mount)
    if req.method ~= 'GET' or mount_found_at ~= 1 then nxt() return end

    -- map url to local filesystem filename
    -- TODO: Path.normalize(req.url)
    local filename = root .. req.url:sub(mount_found_at + #mount)

    -- stream file, possibly caching the contents for later reuse
    local file = cache[filename]

    -- no need to serve anything if file is cached at client side
    if file and file.headers['Last-Modified'] == req.headers['if-modified-since'] then
      serve_not_modified(res, file)
      return
    end

    if file then
      serve(res, file, req.headers.range, false)
    else
      FS.stat(filename, function(err, stat)
        if err then
          serve_not_found(res)
          return
        end
        -- create cache entry, even for files which contents are not
        -- gonna be cached
        -- collect information on file
        file = {
          name = filename,
          size = stat.size,
          mtime = stat.mtime,
          -- FIXME: finer control client-side caching
          headers = {
            ['Content-Type'] = MIME.by_filename(filename),
            ['Content-Length'] = stat.size,
            ['Cache-Control'] = 'public, max-age=' .. (max_age / 1000),
            ['Last-Modified'] = OS.date('%c', stat.mtime),
            ['Etag'] = stat.size .. '-' .. stat.mtime,
          },
        }
        -- allocate cache entry
        cache[filename] = file
        -- should any changes in this file occur, invalidate cache entry
        file.watch = UV.new_fs_watcher(filename)
        file.watch:set_handler('change', invalidate_cache_entry)
NUM1 = NUM1 + 1
d("stat", NUM1, file)
        -- shall we cache file contents?
        local cache_it = options.is_cacheable
          and options.is_cacheable(file)
        serve(res, file, req.headers.range, cache_it)
      end)
    end

  end

end

-- export module
return exports
