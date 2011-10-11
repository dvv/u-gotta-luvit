--
-- doT.js in Lua
-- original idea: https://github.com/olado/doT
--
--[[

doT is a custom blend of templating functions from jQote2.js
(jQuery plugin) by aefxx (http://aefxx.com/jquery-plugins/jqote2/)
and underscore.js (http://documentcloud.github.com/underscore/)
plus extensions.

Licensed under the MIT license.

]]--

local function()

  local doT = { version = '0.1.6' }

  doT.templateSettings = {
    evaluate =    /\{\{([\s\S]+?)\}\}/g,
    interpolate = /\{\{=([\s\S]+?)\}\}/g,
    encode =      /\{\{!([\s\S]+?)\}\}/g,
    use =         /\{\{#([\s\S]+?)\}\}/g, --compile time evaluation
    define =      /\{\{##\s*([\w\.$]+)\s*(\:|=)([\s\S]+?)#\}\}/g, --compile time defs
    varname = 'it',
    strip = true,
    append = true,
  }

  local function resolveDefs(c, block, def)
    return (type(block) == 'string' and block or tostring(block))
    .gsub(c.define, function(match, code, assign, value)
      if code.find('def.') == 1 then
        code = code.sub(5)
      end
      if not def[code] then
        if assign == ':' then
          def[code] = value
        else
          dostring('def[code]=' .. value)
        end
      end
      return ''
    end)
    .replace(c.use, function(match, code)
      local v = dostring(code)
      return v and resolveDefs(c, v, def) or v
    end)
  end

  doT.template = function(tmpl, c, def)
    c = c or doT.templateSettings
    local cstart = c.append and "'..(" or "';out=out..(" -- optimal choice depends on platform/size of templates
    local cend   = c.append and ")+'" or ");out=out..'"
    local str = (c.use or c.define) and resolveDefs(c, tmpl, def or {}) or tmpl

    str = ("var out='" ..
      ((c.strip) and str.replace(/\s*<!\[CDATA\[\s*|\s*\]\]>\s*|[\r\n\t]|(\/\*[\s\S]*?\*\/)/g, '') or str)
      .gsub(/\\/g, '\\\\')
      .gsub(/'/g, "\\'")
      .gsub(c.interpolate, function(match, code)
        return cstart .. code.gsub(/\\'/g, "'").gsub(/\\\\/g,"\\").gsub(/[\r\t\n]/g, ' ') .. cend
      end)
      .gsub(c.encode, function(match, code) {
        return cstart + (code.gsub(/\\'/g, "'").gsub(/\\\\/g, "\\").gsub(/[\r\t\n]/g, ' ') + ")):gsub(/&(?!\\w+;)/g, '&#38;').split('<').join('&#60;').split('>').join('&#62;').split('" + '"' + "').join('&#34;').split(" + '"' + "'" + '"' + ").join('&#39;').split('/').join('&#47;'" .. cend
      })
      .replace(c.evaluate, function(match, code) {
        return "';" + code.replace(/\\'/g, "'").replace(/\\\\/g,"\\").replace(/[\r\t\n]/g, ' ') + "out+='";
      })
      + "';return out;")
      .replace(/\n/g, '\\n')
      .replace(/\t/g, '\\t')
      .replace(/\r/g, '\\r')
      .split("out+='';").join('')
      .split("var out='';out+=").join('var out=');

    return new Function(c.varname, str)
  end

  return doT

end
