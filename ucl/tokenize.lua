local ValueType_None   = 0
local ValueType_Number = 1
local ValueType_String = 2
local ValueType_RawString = 3
local ValueType_List = 4
local ValueType_CommandList = 5

local Value = require('ucl/value')

local function isSpace(c) 
	return c == ' ' or c == '\n' or c == '\t' or c == '\v' or c == '\r' or c == '\f'
end
local function isSpecial(c) 
	return c == ' ' or c == '\n' or c == '\t' or 
		c == '\v' or c == '\r' or c == '\f' or
		c == ';' or c == '#'
end

local function readBracedString(s)

	assert(s:advance() == '{')
	local left = s.pos
	local n = 1
	repeat
		local c = s:advance()
		if c == "\\" then
			s:advance()
		elseif c == '{' then
			n = n + 1
		elseif c == '}' then
			n = n - 1
			if n == 0 then break end
		end
	until s:done()

	return Value.fromStringView(s.source, left, s.pos - 2, ValueType_RawString)	
end

local function readBrackedString(s)

	assert(s:advance() == '[')
	local left = s.pos
	local n = 1
	local c
	repeat
		c = s:advance()
		if s:done() then
			error("unterminated bracket", 0)
		end
	until c == ']'

	return Value.fromStringView(s.source, left, s.pos - 2, ValueType_CommandList)	
end

local function readQuotedString(s)

	assert(s:advance() == '"')
	local left = s.pos
	local n = 1
	local c
	repeat
		c = s:advance()
		if c == "\\" then
			s:advance()
		elseif s:done() then
			error("unterminated quote", 0)
		end
	until c == '"'


	return Value.fromStringView(s.source, left, s.pos - 2)	
end

local function readBareWord(s)
	local left = s.pos
	while not isSpecial(s:peek()) and not s:done() do 
		local f = s:advance()
		if f == '\\' then s:advance() end
	 end
	if s:done() then return nil end
	--if s.pos - 1 <= left then return nil end

	return Value.fromStringView(s.source, left, s.pos - 1)
end

local function readToken(s)
	local c = s:peek()
	local r
	if c == '{' then
		r = readBracedString(s)
	elseif c == '[' then
		r = readBrackedString(s)
	elseif c == '"' then
		r = readQuotedString(s)
	else
		r = readBareWord(s)
	end
	return r
end

local function tok(inp)
	if type(inp) ~= "table" then inp = Value.fromString(inp) end

	if false then return tokenize(inp) end

	local s = inp:scanner()
	local lines = {}
	local line = {}
	while not s:done() do
		while s:peek() ~= '\n' and isSpace(s:peek()) and not s:done() do s:advance() end
		if s:peek() == '#' then
			while s:peek() ~= '\n' do s:advance() end
		elseif s:peek() == '\n' or s:peek() == ';' then
			s:advance()
			if #line > 0 then table.insert(lines, Value.fromList(line)) end
			line = {}
		else
			local t = readToken(s)
			if t then 
				table.insert(line, t)
			end
		end
	end

	if false then 
		print("Parsed " .. #lines .. " lines")
		for k,v in ipairs(lines) do 
			print(k,#v.list, v.string)
			for kk,vv in ipairs(v.list) do
				print('\t', kk, #vv.string, '//' .. vv.string .. '(' .. vv.type .. ')//')
			end
		end
		print("--")
	end
	return lines
end


return tok
