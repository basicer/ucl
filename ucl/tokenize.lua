local ValueType_None   = 0
local ValueType_Number = 1
local ValueType_String = 2
local ValueType_RawString = 3
local ValueType_List = 4
local ValueType_CommandList = 5
local ValueType_CompoundString = 6
local ValueType_Variable = 7

local Value = require('ucl/value')

local function isSpace(c) 
	return c == ' ' or c == '\n' or c == '\t' or c == '\v' or c == '\r' or c == '\f'
end

local function isSeprator(c) 
	return c == ' ' or c == '\n' or c == '\t' or 
		c == '\v' or c == '\r' or c == '\f' or
		c == ';' or c == 'EOF'
end

local function isSpecial(c)
	return c == ' ' or c == '\n' or c == '\t' or 
		c == '\v' or c == '\r' or c == '\f' or
		c == ';' or c == '#' or ']' or '}'
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

	if s.pos - 2 >= left then
		return Value.fromStringView(s.source, left, s.pos - 2, ValueType_RawString)	
	else
		return Value.none
	end
end

local readTCL
local function readVariable(s)
	local left = s.pos
	local paren = 0
	local brace = 0
	assert(s:advance() == '$')

	if not s:peek():match("^[{a-zA-Z0-9_]") then
		return false
	elseif s:peek() == '{' then
		while s:advance() ~= '}' do end
	else
		repeat
			local c = s:peek()
			if paren > 0 then
				if c == ')' then paren = paren - 1 end
			else
				if c == '(' then paren = paren + 1
				elseif not c:match("^[a-zA-Z0-9_]$") then break end
			end
			s:advance()
		until false
	end

	return Value.fromStringView(s.source, left, s.pos - 1, ValueType_Variable)	
end

local function readBrackedString(s)
	assert(s:advance() == '[')
	local left = s.pos
	local list = readTCL(s)
	if s:advance() ~= ']' then
		error('missing close-bracket', 0) 
	end
	return Value.fromStringView(s.source, left, s.pos - 2, ValueType_CommandList)	
end

local function readQuotedString(s)

	assert(s:advance() == '"')
	local left = s.pos
	local n = 1
	local c
	local parts = {}
	repeat
		c = s:peek()
		if c == "\\" then
			s:advance()
			s:advance()
		elseif c == '[' then
			if s.pos-1 >= left then
				table.insert(parts, Value.fromStringView(s.source, left, s.pos - 1))
			end
			table.insert(parts, readBrackedString(s))
			left = s.pos - 1
		elseif s:done() then
			error("unterminated quote", 0)
		else
			s:advance()
		end
		
	until c == '"'

	if s.pos - 2 >= left then
		table.insert(parts, Value.fromStringView(s.source, left, s.pos - 2))
	end
	if #parts == 0 then
		return Value.none
	elseif #parts == 1 then
		return parts[1]
	else
		return Value.fromCompoundList(parts)
	end
end

local function continueReadingCompositeString(s, left)
	local result = {}
	if s.pos - 1 >= left then
		table.insert(result, Value.fromStringView(s.source, left, s.pos - 1))
	end
	left = s.pos
	while not isSeprator(s:peek()) and not s:done() do
		local c = s:peek()
		if c == ']' then break end
		if
				c == '['
				or c == '$'
		then
			if left < s.pos then
				table.insert(result, Value.fromStringView(s.source, left, s.pos - 1))
			end
			if c == '[' then
				table.insert(result, readBrackedString(s))
				left = s.pos
			elseif c == '$' then
				local v = readVariable(s)
				if v then
					table.insert(result, v)
					left = s.pos
				end
			end
		else
			local f = s:advance()
			if f == '\\' then
				if s:peek() ~= 'EOF' then s:advance() end
			end
		end
	end
	if s:done() then return nil end
	if left < s.pos then
		table.insert(result, Value.fromStringView(s.source, left, s.pos - 1))
	end
	
	--print('pCPS', #result)
	if #result > 1 then
		return Value.fromCompoundList(result)
	else
		return result[1]
	end
end

local function readBareWord(s)
	local left = s.pos
	local bare = true
	while not isSeprator(s:peek()) and not s:done() do 
		local c = s:peek()
		if c == ']' then break end
		if c == '[' or c == '$' then
			return continueReadingCompositeString(s,left)
		end
		if c == '\\' then bare = false end
		local f = s:advance()
		if f == '\\' then
			if s:peek() ~= 'EOF' then s:advance() end
		end
	 end
	if s:done() then return nil end
	--if s.pos - 1 <= left then return nil end

	if left > s.pos - 1 then
		return Value.fromString("") -- wat?
	elseif bare then
		--print("Source is", s.source)
		return Value.fromStringView(s.source, left, s.pos - 1, ValueType_RawString)
	else
		return Value.fromStringView(s.source, left, s.pos - 1)
	end
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
		if not isSpecial(s:peek()) then error('extra characters after close-quote', 0) end 
	else
		r = readBareWord(s)
	end
	return r
end

readTCL = function(s)
	local lines = {}
	local line = {}
	while not s:done() do
		while s:peek() ~= '\n' and isSpace(s:peek()) and not s:done() do s:advance() end
		if s:peek() == ']' then break end
		if s:peek() == '\n' or s:peek() == ';' or s:peek() == 'EOF' then
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
	return lines
end

local function tok(inp)
	if type(inp) ~= "table" then inp = Value.fromString(inp) end

	if false then return tokenize(inp) end

	local s = inp:scanner()
	local lines = readTCL(s)

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

local function expr(code)
	local i = 1
	local tokens = {}
	while i <= #code do
		local a, b

		local sa, sb = code:find('^[%s\n]+', i)
		if sa then 
			i = sb + 1
		end

		local a, b = code:find("^[a-z][a-z0-9]*%(", i)
		if a then
			table.insert(tokens, {type='function', name=code:sub(a,b-1)})
			i = b + 1
		elseif code:sub(i,i) == "$" then
			a, b = code:find("^%$[a-z0-9()_]+", i)
			table.insert(tokens, {type='variable', name=code:sub(a+1,b)})
			i = b + 1
		elseif code:sub(i,i) == "[" then
			local yikes = Value.fromStringView(code, i, #code)
			local s = yikes:scanner()
			table.insert(tokens, {type='cmd', value=readBrackedString(s)})
			i = s.pos
		else
			if not a then a,b = code:find('^,', i) end
			if not a then a,b = code:find('^0[xo][0-9A-Fa-f]+', i) end
			if not a then a,b = code:find('^[0-9]*%.[0-9]*', i) end
			if not a then a,b = code:find('^[0-9%.]+e%+?[0-9]+', i) end
			if not a then a,b = code:find('^[0-9]+', i) end
			if not a then a,b = code:find('^%*%*?', i) end
			if not a then a,b = code:find('^[&|][&|]?', i) end
			if not a then a,b = code:find('^eq', i) end
			if not a then a,b = code:find('^ne', i) end
			if not a then a,b = code:find('^[~!+%-%*/<>=()%%][<>=]?', i) end
			if not a then a,b = code:find('^[^%s]+', i) end

			if a then
				table.insert(tokens, code:sub(a,b))
				i = b + 1
			end
		end

	end
	return tokens
end


return {tokenize = tok, expr = expr}
