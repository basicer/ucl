local ValueType_None   = 0
local ValueType_Number = 1
local ValueType_String = 2
local ValueType_RawString = 3
local ValueType_List = 4
local ValueType_CommandList = 5
local ValueType_CompoundString = 6
local ValueType_Variable = 7

local Value = require('ucl.value')

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

local tokenizer_mt = {}

function tokenizer_mt:readBracedString(s)

	assert(s:advance() == '{')
	local left = s.pos
	local n = 1
	repeat
		local c = s:peek()
		if c == "\\" then
			s:advance()
		elseif c == '{' then
			n = n + 1
		elseif c == '}' then
			n = n - 1
			if n == 0 then break end
		end
		s:advance()
	until s:done()

	if s:advance() ~= '}' then
		self:error('missing close-brace')
	end

	if s.pos - 2 >= left then
		return Value.fromStringView(s.source, left, s.pos - 2, ValueType_RawString)
	else
		return Value.none
	end
end


function tokenizer_mt:readVariable(s)
	local left = s.pos
	local paren = 0
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

function tokenizer_mt:readBrackedString(s)
	assert(s:advance() == '[')
	local left = s.pos
	local parts = self:readTCL(s)
	if s:advance() ~= ']' then
		self:error('missing close-bracket')
	end
	local r = Value.fromStringView(s.source, left, s.pos - 2, ValueType_CommandList)
	rawset(r, "cmdlist", parts)
	return r
end

function tokenizer_mt:readQuotedString(s)
	assert(s:advance() == '"')
	local left = s.pos
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
			table.insert(parts, self:readBrackedString(s))
			left = s.pos - 1
		elseif s:done() then
			self:error("unterminated quote")
			break
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

function tokenizer_mt:continueReadingCompositeString(s, left)
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
				table.insert(result, self:readBrackedString(s))
				left = s.pos
			elseif c == '$' then
				local v = self:readVariable(s)
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

function tokenizer_mt:readBareWord(s)
	local left = s.pos
	local bare = true
	while not isSeprator(s:peek()) and not s:done() do
		local c = s:peek()
		if c == ']' then break end
		if c == '[' or c == '$' then
			return self:continueReadingCompositeString(s,left)
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

function tokenizer_mt:readToken(s)
	local c = s:peek()
	local r
	if c == '{' then
		r = self:readBracedString(s)
	elseif c == '[' then
		r = self:readBrackedString(s)
	elseif c == '"' then
		r = self:readQuotedString(s)
		if not isSpecial(s:peek()) then
			self:error('extra characters after close-quote')
		end
	else
		r = self:readBareWord(s)
	end
	return r
end

function tokenizer_mt:readTCL(s)
	local lines = {}
	local line = {}
	while not s:done() do
		while s:peek() ~= '\n' and isSpace(s:peek()) and not s:done() do s:advance() end
		if s:peek() == ']' then break end
		if s:peek() == 'EOF' then break end
		if s:peek() == '\n' or s:peek() == ';' then
			s:advance()
			if #line > 0 then table.insert(lines, Value.fromList(line)) end
			line = {}
		else
			local t = self:readToken(s)
			if t then
				table.insert(line, t)
			end
		end
	end
	if #line > 0 then table.insert(lines, Value.fromList(line)) end
	return lines
end

function tokenizer_mt:expr(code)
	local i = 1
	local tokens = {}
	while i <= #code do
		local a, b

		local sa, sb = code:find('^[%s\n]+', i)
		if sa then
			i = sb + 1
		end

		a, b = code:find("^[a-z][a-z0-9]*%(", i)
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
			table.insert(tokens, {type='cmd', value=self:readBrackedString(s)})
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

function tokenizer_mt:error(str)
	table.insert(self.errors, str)
end

local function new()
	local t = setmetatable({
		s = s,
		progress = {},
		errors = {}
	}, {__index=tokenizer_mt})
	return t
end

local function load(inp)
	if type(inp) ~= "table" then
		inp = Value.fromString(inp)
	end

	local s = inp:scanner()
	local t = new()
	local lines = t:readTCL(s)
	return t, lines
end

local function value(inp)
	local r
	if #inp > 0 then
		r = Value.fromStringView(inp, 1, #inp, ValueType_CommandList)
	else
		r = Value.fromString("", ValueType_CommandList)
	end
	local t,lines = load(r)
	rawset(r, "cmdlist", lines)
	return t, r
end

local function tok(inp)
	local t, lines = load(inp)
	if #t.errors > 0 then
		error(t.errors[1], 0)
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

local function expr(s)
	local t = setmetatable({s = s}, {__index=tokenizer_mt})
	return t:expr(s)
end

return {
	tokenize = tok,
	expr = expr,
	new=new,
	load=load,
	value=value
}
