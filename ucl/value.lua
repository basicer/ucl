local Value = {}

local ValueType_None   = 0
local ValueType_Number = 1
local ValueType_String = 2
local ValueType_RawString = 3
local ValueType_List = 4
local ValueType_CommandList = 5
local ValueType_CompoundString = 6
local ValueType_Variable = 7


local Scanner = {}
function Scanner:advance()
	local a,b = self:peek()
	self.pos = self.pos + 1
	return a, b
end
function Scanner:peek()
	if self.pos == self.right + 1 then return '\n', self.pos end
	if self.pos > self.right + 1 then return nil, self.pos end
	return self.source:sub(self.pos, self.pos), self.pos
end
function Scanner:done()
	return self.pos > self.right + 2
end
function Scanner:reverse()
	self.pos = self.pos - 1
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
	local tokenize = require('ucl/tokenize')
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
	else
		error("Type from:" .. type(v))
	end
end

function Value.fromList(slist)
	return setmetatable({
		kind = ValueType_List,
		list = slist
	}, Value.metaTable)
end

function Value.fromNumber(n)
	assert(type(n) == "number")
	return setmetatable({
		kind = ValueType_Number,
		number = n or 0
	}, Value.metaTable)
end

function Value.fromCompoundList(parts)
	return setmetatable({
		kind = ValueType_CompoundString,
		parts = parts
	}, Value.metaTable)
end

function Value.fromBoolean(v)
	return setmetatable({
		kind = ValueType_Number,
		number = v and 1 or 0
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
	local tokenize = require('ucl/tokenize')
	local list = tokenize.tokenize(self)
	self.cmdlist = list
	return list
end

function props.string(self)
	local sv = rawget(self,'string_view')
	if self.kind == ValueType_None then
		return ""
	elseif self.kind == ValueType_Number then
		return "" .. self.number
	elseif self.kind == ValueType_CompoundString then
		local parts = {}
		for k,v in ipairs(self.parts) do
			if v.kind == ValueType_CommandList then table.insert(parts,'[') end
			table.insert(parts, v.string)
			if v.kind == ValueType_CommandList then table.insert(parts,']') end
		end
		return table.concat(parts,'')
	elseif sv then
		local s = string.sub(sv[1], sv[2], sv[3])
		self.string = s
		return s
	elseif self.kind == ValueType_List then
		local mapped = {}
		for k,v in ipairs(self.list) do
			local m = v.string
			
			if m:find("[ %$\r\n\t%[]") or #m == 0 then
				m = "{" .. m:gsub("([{}\\])", "\\%1") .. "}"
			else
				m = m:gsub("([{}%[%]\"\\])","\\%1")
				m = m:gsub("\\{([^}]*)\\}", "{%1}")
			end
			mapped[k] = m
		end
		return table.concat(mapped, " ")
	end
	error("Need a string")
end

function props.interp(self)
	return function(self, state)
		local dict = state.variables
		if self.kind == ValueType_RawString then 
			return self
		elseif self.kind == ValueType_CommandList then
			return state:eval(self)
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
					rparts[k] = state:eval(v)
				else
					rparts[k] = v:interp(state)
				end
			end
			return Value.fromCompoundList(rparts)
		elseif self.kind == ValueType_Variable then
			local o = self.string:sub(2)
			o = o:gsub("(%b{})", function(s) print(o, s:sub(2,-2)) return s:sub(2,-2) end)
			--print("VAR /" ..  o .. "/", dict[o] and dict[o].value or "?")
			if not dict[o] then return "?" .. o .. "?" end
			if not dict[o].value then return "" end
			return dict[o].value
		end
		local s = self.string
		local s, changed = unescape(s)

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
			local list = self.cmdlist[1]
			if not list then return {} end
			self.list = list.list
			return list.list
		elseif name == 'sub' then
			local s = self.string
			return function(self, ...)
				--Todo: Support string_view
				return Value.fromString(string.sub(s,...))
			end
		elseif name == 'scanner' then
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

		elseif name == 'type' then
			local kind = self.kind
			if kind == ValueType_String then return "String"
			elseif kind == ValueType_List then return "List"
			elseif kind == ValueType_CommandList then return "CList"
			elseif kind == ValueType_RawString then return "RawString"
			elseif kind == ValueType_None then return "None"
			elseif kind == ValueType_CompoundString then return "CString"
			elseif kind == ValueType_Variable then return "Variable"
			end
		elseif name == 'execute' then
			local compile, x = require('ucl/compile')
			local str = compile(self)
			local v, err = loadstring(str)
			if v == nil then error(err) end
			local fn = v()(self, Value)
			self.execute = fn
			return fn
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