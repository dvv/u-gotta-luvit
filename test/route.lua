local String = require('string')
local Table = require('table')

--[[
local s = '/iframe-12.34234.html'
local params = {}
p(String.gsub(s, '/iframe(.*).html', function(prm)
  if prm then Table.insert(params, prm) end
end))
p('gsub', s, params)

local s = '/iframe-12.34234.html'
p('match', String.match(s, '/iframe(.-)%.(.-)%.html'))
]]--

for cookie in String.gmatch(' ; JSESSIONID = foo', '[^;]+') do
  local name, value = String.match(cookie, '%s*([^=%s]-)%s*=%s*([^%s]*)')
  p(name, value)
end
