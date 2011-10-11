--[[

local templateSettings = {
  evaluate    = /<%([\s\S]+?)%>/g,
  interpolate = /<%=([\s\S]+?)%>/g,
}

-- Lua micro-templating, similar to John Resig's implementation.
function String.template = function(str, data, settings)
  local c  = settings or templateSettings
  local tmpl = 'local __p={};' ..
    "obj = obj or {} __p:insert('" ..
    str:gsub('[\]', '\\\\')
       :gsub("'", "\\'")
       :gsub(c.interpolate, function(match, code)
         return "'," .. code:replace(/\\'/g, "'") .. ",'"
       end)
  if c.evaluate then
    tmpl = tmpl:gsub(c.evaluate, function(code)
      return "');" .. code:gsub(/\\'/g, "'")
                 :gsub('%s', ' ') .. "__p.insert('";
    end)
  end
  tmpl = tmpl:gsub(/\r/g, '\\r')
       .replace(/\n/g, '\\n')
       .replace(/\t/g, '\\t')
       .. "') return __p.join('')"
  return tmpl
  --local func = new Function('obj', tmpl)
  --return data and func(data) or func
end

]]--



--[[

ocal special = {
    ['a']  = "\a",
    ['b']  = "\b",
    ['f']  = "\f",
    ['n']  = "\n",
    ['r']  = "\r",
    ['t']  = "\t",
    ['v']  = "\v",
    ['\\'] = '\\',
    ['"']  = '"',
    ["'"]  = "'",
}

local function unescape(str)
    str = str:gsub([[\(%d+)]], function (s)
                                      local n = tonumber(s:sub(1, 3))
                                      return string.char(n % 256) .. s:sub(4)
                                  end
    )
    return str:gsub([[\([abfnrtv\"'])]], special)
end


function eval(str, name)
local f, err = loadstring("return function (arg) " .. str .. " end", name or str)
  if f then return f() else return f, err end
end
print( loadstring("return function(x) return x + 1 end")()(1) )

---
---
---
function myFunc() return aaa end
local newgt = {} -- new environment
newgt.aaa = 'foo'
setmetatable(newgt, {__index = _G})
setfenv(myFunc, newgt)
print(myFunc())

]]--


--[[

-- from http://lua-users.org/wiki/StringTrim
function string:trim()
    local a = self:match('^%s*()')
    local b = self:match('()%s*$', a)
    return self:sub(a,b-1)
end

-- from http://lua-users.org/wiki/SplitJoin
function string:split(sep)
    local sep, fields = sep or " ", {}
    local pattern = string.format("([^%s]+)", sep)
    self:gsub(pattern, function(c) fields[#fields+1] = c end)
    return fields
end


-- escape html
function escape_html(s)
    local replacement = {"<", "&lt;", 
                         ">", "&gt;", 
                         "{{", "\n<span>{{</span>\n",
                         "{%%", "\n<span>{%%</span>\n",
                         "%%}", "\n<span>%%}</span>\n",
                         "}}", "\n<span>}}</span>\n"}
    local str, n = s, 0;
    for i=1, #replacement, 2 do
        str, n = str:gsub(replacement[i], replacement[i+1]);
    end
    return str
end

-- Complete clone of a table
function clone(u, copied)
    copied = copied or {}
    local new = {}
    copied[u] = new
    for k, v in pairs(u) do
        if type(v) ~= "table" then
            new[k] = v
        elseif copied[v] then
            new[k] = copied[v]
        else
            copied[v] = clone(v, copied)
            new[k] = setmetatable(copied[v], getmetatable(v))
        end
    end
    setmetatable(new, getmetatable(u))
    return new
end
]]--


--[[

parseQuery = function(str)
    local allvars = {}
    for pair in tostring(str):gmatch("[^&]+") do
        local key, value = pair:match("([^=]*)=(.*)")
        if key then
            allvars[key] = value
        end
    end
    return allvars
end

]]--


