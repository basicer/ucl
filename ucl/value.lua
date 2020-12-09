local env = require('ucl.env')
local numToStr = env.numToStr

local Value = {}

local ValueType_None   = 0
local ValueType_Number = 1
local ValueType_String = 2
local ValueType_RawString = 3
local ValueType_List = 4
local ValueType_CommandList = 5
local ValueType_CompoundString = 6
local ValueType_Variable = 7
local ValueType_Map = 8
local ValueType_Foreign = 9
local ValueType_Magic = 10


local Scanner = {}
function Scanner:advance()
	local a,b = self:peek()
	self.pos = self.pos + 1
	return a, b
end
function Scanner:peek()
	if self.pos == self.right + 1 then return 'EOF', self.pos end
	if self.pos > self.right + 1 then return nil, self.pos end
	return self.source:sub(self.pos, self.pos), self.pos
end
function Scanner:done()
	return self.pos > self.right + 1
end
function Scanner:consumep(p)
	local m = {string.find(self.source, "^" .. p, self.pos)}
	if not m[1] then return false end
	local v = Value.fromStringView(self.source, m[1], m[2])
	self.pos = m[2] + 1
	return v, select(2, env.unpack(m))
end
function Scanner:reverse()
	self.pos = self.pos - 1
end

local function escapePlan(m)
	if #m == 0 then return '{}' end

	local hasSpecial = nil ~= m:find("[ %[%]$\";%\\\r\n\f\z\v\t]")
	local hasBrace = nil ~= m:find("[{}]")

	if not hasSpecial and not hasBrace then
		return ''
	end

	local complex =  m:sub(1,1) == '{' or m:sub(1,1) == '"'

	local bc, cc = 0, 0
	local prev = ''
	for i=1,#m do
		local c = m:sub(i,i)
		if prev ~= '\\' then
			if c == '{' then
				cc = cc + 1
			elseif c == '[' then
				bc = bc  + 1
			elseif c == '}' then
				cc = cc - 1
				if cc < 0 then return '\\' end
			elseif c == ']' then
				bc = bc - 1
			end
		end
		prev = c
	end


	if bc < 0 or cc ~= 0 then return "\\" end
	if m:sub(-1,-1) == '\\' then return '\\' end
	if m:find("[\\][\n]") then return '\\' end -- not sure on this one
	if not complex and not hasSpecial then return "" end
	return "{}"
end

local function escapeString(m, k)
	local p = escapePlan(m)

	if p == '{}' then
		m = '{' .. m .. '}'
	elseif p == '\\' then
		m = m:gsub("([{}%[%]\"\\\r\v\t\\\n$; ])",function(o)
			if o == '\n' then return '\\n'
			elseif o == '\r' then return '\\r'
			elseif o == '\v' then return '\\v'
			elseif o == '\t' then return '\\t'
			elseif o == '\\' then return '\\\\'
			else return '\\' .. o end
		end)
		if k == 1 and m:sub(1,1) == '#' then
			m = '\\' .. m
		end
	else
		if k == 1 and m:sub(1,1) == '#' then
			m = '{' .. m .. '}'
		end
	end
	return m
end

local function escapeList(list)
	local mapped = {}
	for k,v in ipairs(list) do
		local m = v.string
		mapped[k] = escapeString(m, k)
	end
	return table.concat(mapped, " ")
end

local function tocode(v, ctx)
	if v.kind == ValueType_CompoundString then
		local parts = {}
		for _,v in ipairs(v.parts) do
			if v.kind == ValueType_CommandList then table.insert(parts,'[') end
			table.insert(parts, tocode(v, ctx))
			if v.kind == ValueType_CommandList then table.insert(parts,']') end
		end
		return table.concat(parts, v.seperator)
	elseif v.kind == ValueType_List then
		local ss = {}
		for k,v in ipairs(v.list) do
			if v.kind == ValueType_List or v.kind == ValueType_RawString then
				ss[k] = escapeString(tocode(v, ctx))
			else
				ss[k] = tocode(v, {i=ctx.i})
			end
		end
		return table.concat(ss, " ")
	elseif v.kind == ValueType_CommandList then
		local ss = {}
		for k,v in ipairs(v.cmdlist) do
			ss[k] = tocode(v, {i=ctx.i})
		end
		return "[" .. table.concat(ss, ";") .. "]"
	elseif (v.kind == ValueType_RawString and rawget(v,'cmdlist')) then
		local ss = {}
		local i = (ctx.i or '')
		for k,v in ipairs(v.cmdlist) do
			ss[k] = tocode(v, {i = i .. '  '})
		end
		return "\n" .. i .. table.concat(ss, "\n" .. i) .. "\n" .. i:sub(3)
	elseif v.kind == ValueType_Variable then
		return v.string
	else
		return escapeList({v})
	end
end

function Value.fromStringView(str, left, right, kind)
	assert(type(str) == "string")
	assert(type(left) == "number")
	assert(type(right) == "number")
	assert(left > 0)
	if(right < left) then
		print(debug.traceback())
		os.exit(1)
	end

	return setmetatable({
		kind = kind or ValueType_String,
		string_view = {str, left, right}
	}, Value.metaTable)
end

function Value.fromString(str, kind)
	assert(type(str) == "string")
	return setmetatable({
		kind = kind or ValueType_String,
		string = str
	}, Value.metaTable)
end

function Value.fromXString(str)
	local tokenize = require('ucl.tokenize')
	local list = tokenize.tokenize(str)
	return list[1]
end

function Value.from(v)
	if type(v) == "number" then
		return Value.fromNumber(v)
	elseif type(v) == "string" then
		return Value.fromString(v)
	elseif type(v) == 'nil' then
		return Value.none
	elseif type(v) == 'table' then
		local mt = getmetatable(v)
		if mt == Value.metaTable then return v end
		local mapped = {}
		local isList = true
		for kk,vv in pairs(v) do
			if type(tonumber(kk)) ~= "number" then
				isList = false
			end
			mapped[kk] = Value.from(vv)
		end
		if not isList then
			error("Type from table that wasnt a list")
		end
		return Value.fromList(mapped)

	else
		error("Type from:" .. type(v))
	end
end

function Value.fromList(slist)
	assert(type(slist) == "table")
	return setmetatable({
		kind = ValueType_List,
		list = slist
	}, Value.metaTable)
end

function Value.fromCmdList(slist)
	assert(type(slist) == "table")
	return setmetatable({
		kind = ValueType_CommandList,
		cmdlist = slist
	}, Value.metaTable)
end

function Value.fromNumber(n)
	assert(type(n) == "number")
	return setmetatable({
		kind = ValueType_Number,
		number = n or 0
	}, Value.metaTable)
end

function Value.fromCompoundList(parts, seperator)
	return setmetatable({
		kind = ValueType_CompoundString,
		parts = parts,
		seperator = seperator or ''
	}, Value.metaTable)
end

function Value.fromBoolean(v)
	return setmetatable({
		kind = ValueType_Number,
		number = v and 1 or 0
	}, Value.metaTable)
end

function Value.magic()
	return setmetatable({
		kind = ValueType_Magic,
	}, Value.metaTable)
end


local function unescape(s)
	local changed = false
	s = s:gsub("\\(.)", function(c)
		changed = true
		if false then
		elseif c == 'v' then return '\v'
		elseif c == 'n' then return '\n'
		elseif c == 't' then return '\t'
		elseif c == 'f' then return '\f'
		elseif c == 'r' then return '\r'
		elseif c == '\n' then return ' '
		else return c
		end
	end)
	return s, changed
end

local props = {}

function props.cmdlist(self)
	local tokenize = require('ucl.tokenize')
	local list = tokenize.tokenize(self)
	self.cmdlist = list
	return list
end

function props.code(self)
	return tocode(self, {})
end

function props.string(self)
	local sv = rawget(self,'string_view')
	if self.kind == ValueType_None then
		return ""
	elseif self.kind == ValueType_Number then
		return numToStr(self.number)
	elseif self.kind == ValueType_CompoundString then
		local parts = {}
		for _,v in ipairs(self.parts) do
			if v.kind == ValueType_CommandList then table.insert(parts,'[') end
			table.insert(parts, v.string)
			if v.kind == ValueType_CommandList then table.insert(parts,']') end
		end
		local s = table.concat(parts, self.seperator)
		self.string = s
		return s
	elseif sv then
		local s = string.sub(sv[1], sv[2], sv[3])
		self.string = s
		return s
	elseif self.kind == ValueType_List then
		local s = escapeList(self.list)
		self.string = s
		return self.string
	elseif self.kind == ValueType_CommandList then
		local ss = {}
		for k,v in ipairs(self.cmdlist) do
			ss[k] = v.string
		end
		return table.concat(ss, "\n")
	end
	error("Need a string, have " .. self.type)
end


function props.lua(self)
	local sv = rawget(self,'string_view')
	if self.kind == ValueType_None then
		return nil
	elseif self.kind == ValueType_Number then
		return self.number
	elseif self.kind == ValueType_CompoundString then
		return self.string
	elseif sv then
		local s = string.sub(sv[1], sv[2], sv[3])
		self.string = s
		self.lua = s
		return s
	elseif self.kind == ValueType_List then
		self.lua = {}
		for k,v in ipairs(self.list) do
			self.lua[k] = v.lua
		end
		return self.lua
	else
		return self.string
	end
end

function props.expr_tokens(self)
	local tokens = require('ucl.tokenize').expr(self.string)
	self.expr_tokens = tokens
	return tokens
end

function props.interp(self)
	return function(self, state)
		local dict = state.variables
		if self.kind == ValueType_RawString then
			return self
		elseif self.kind == ValueType_CommandList then
			return state.eval(self)
		elseif self.kind == ValueType_List then
			local rparts = {}
			for k,v in ipairs(self.list) do
				rparts[k] = v:interp(state).string
			end
			return Value.fromString(table.concat(rparts, ' '))
		elseif self.kind == ValueType_CompoundString then
			local rparts = {}
			for k,v in ipairs(self.parts) do
				if v.kind == ValueType_CommandList then
					rparts[k] = state.eval(v)
				else
					rparts[k] = v:interp(state)
				end
			end
			return Value.fromCompoundList(rparts, self.seperator)
		elseif self.kind == ValueType_Variable then
			local o = self.string:sub(2)
			o = o:gsub("(%b{})", function(s) return s:sub(2,-2) end)
			local va, vb = o:find("%(.*%)$")
			if va then
				local idx = o:sub(va+1, vb-1)
				local n = o:sub(1, va-1)
				if not dict[n] then
					error('can\'t read "' .. o .. '": no such variable', 0)
				end
				if not dict[n].array then
					error('can\'t read "' .. o .. '": variable isn\'t an array', 0)
				end
				if not dict[n].array[idx] then
					return Value.none
				end
				return dict[n].array[idx].value
			end
			--print("VAR /" ..  o .. "/", dict[o] and dict[o].value or "?")
			if not dict[o] then
				error('can\'t read "' .. o .. '": no such variable', 0)
			end
			if not dict[o].value then return Value.none end
			return dict[o].value
		end
		local changed
		local s = self.string
		s, changed = unescape(s)

		local function replacer(o)
			changed = true
			if not dict[o] then return "?" .. o .. "?" end
			if not dict[o].value then return "" end
			return dict[o].value.string
		end

		--TODO Remove this
		s = s:gsub("%$([a-zA-Z0-9_]+%([^%)]+%)", replacer)
		s = s:gsub("%$([a-zA-Z0-9_]+)", replacer)
		s = s:gsub("%${([^}]*)}", replacer)

		if changed then
			return Value.fromString(s)
		else
			return self
		end
	end
end

function props.scanner(self)
	if rawget(self, 'string_view') then
		return function(self)
			local sv =  self.string_view
			assert(sv[3]>=sv[2])
			local ss = sv[1]:sub(sv[2],sv[3])
			if(#ss ~= 1 + sv[3] - sv[2]) then
				print(sv[1],sv[2],sv[3])
				os.exit(1)
			end
			return setmetatable({
				source = sv[1],
				left = sv[2],
				pos = sv[2],
				right = sv[3]
			}, {__index=Scanner})
		end
	end
	return function(self)
		return setmetatable({
			source = self.string,
			left = 1,
			pos = 1,
			right = #self.string
		}, {__index=Scanner})
	end
end

Value.metaTable = {
	__index = function(self, name)
		if props[name] then return props[name](self) end
		if name == 'string' then

		elseif name == 'number' then
			local n = tonumber(self.string)
			if type(n) ~= "number" then error("invalid number: " .. self.string, 0) end
			self.number = n
			return n
		elseif name == 'list' then
			local list = {}
			for _,v in ipairs(self.cmdlist) do
				for _,vv in ipairs(v.list) do
					table.insert(list, vv)
				end
			end
			if not list then return {} end
			self.list = list
			return list
		elseif name == 'sub' then
			local s = self.string
			return function(self, ...)
				--Todo: Support string_view
				return Value.fromString(string.sub(s,...))
			end
		elseif name == 'type' then
			local kind = self.kind
			if kind == ValueType_String then return "String"
			elseif kind == ValueType_Number then return "Number"
			elseif kind == ValueType_List then return "List"
			elseif kind == ValueType_CommandList then return "CList"
			elseif kind == ValueType_RawString then return "RawString"
			elseif kind == ValueType_None then return "None"
			elseif kind == ValueType_CompoundString then return "CString"
			elseif kind == ValueType_Variable then return "Variable"
			elseif kind == ValueType_Map then return "Map"
			elseif kind == ValueType_Magic then return "Magic"
			elseif kind == ValueType_Foreign then return "Foreign"
			end
		elseif name == 'execute' then
			local compile = require('ucl.compile')
			local str = compile(self)
			local v, err = env.loadstring(str)
			if v == nil then error(err) end
			local fn = v()(self, Value)
			self.execute = fn
			return fn
		elseif name == 'ipairs' then
			return function() return ipairs(self.list) end
		end
		error("Index value: " .. name)
	end,
	__tostring = function(self)
		return self.string
	end,
	__add = function(self, right)
		return Value.fromNumber(self.number + right.number)
	end,
	__sub = function(self, right)
		return Value.fromNumber(self.number - right.number)
	end,
	__mul = function(self, right)
		return Value.fromNumber(self.number * right.number)
	end,
	__div = function(self, right)
		return Value.fromNumber(self.number / right.number)
	end,
	__eq = function(self, right)
		return self.string == right.string
	end
}

Value.none = Value.fromString("")
Value.True = Value.fromNumber(1)
Value.False = Value.fromNumber(0)

return Value
