local Value = {}

local ValueType_None   = 0
local ValueType_Number = 1
local ValueType_String = 2
local ValueType_RawString = 3
local ValueType_List = 4
local ValueType_CommandList = 5

local tokenize = require('ucl/tokenize')

local Scanner = {}
function Scanner:advance()
	self.pos = self.pos + 1
	if self.pos == self.right + 1 then return '\n', self.pos end
	if self.pos > self.right + 1 then return nil, self.pos end
	return self.source:sub(self.pos, self.pos), self.pos

end

function Value.fromStringView(str, left, right, kind)
	assert(type(left) == "number")
	assert(type(right) == "number")

	return setmetatable({
		kind = kind or ValueType_String,
		string_view = {str, left, right}
	}, Value.metaTable)
end

function Value.fromString(str, kind)
	return setmetatable({
		kind = kind or ValueType_String,
		string = str
	}, Value.metaTable)
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

function Value.fromBoolean(v)
	return setmetatable({
		kind = ValueType_Number,
		number = v and 1 or 0
	}, Value.metaTable)
end

Value.metaTable = {
	__index = function(self, name)
		if name == 'cmdlist' then
			local list = tokenize(self)
			self.cmdlist = list
			return list
		elseif name == 'string' then
			local sv = rawget(self,'string_view')
			if self.kind == ValueType_None then
				return ""
			elseif self.kind == ValueType_Number then
				return "" .. self.number
			elseif sv then
				local s = string.sub(sv[1], sv[2], sv[3])
				self.string = s
				return s
			elseif self.kind == ValueType_List then
				local mapped = {}
				for k,v in ipairs(self.list) do
					mapped[k] = v.string
					if mapped[k]:find(" ") then
						mapped[k] = "{" .. mapped[k] .. "}"
					end
				end
				return table.concat(mapped, " ")
			end
			error("Need a string")
		elseif name == 'number' then
			local n = tonumber(self.string)
			if type(n) ~= "number" then error("invalid number: " .. self.string, 0) end
			self.number = n
			return n
		elseif name == 'list' then
			local list = self.cmdlist[1]
			self.list = list.list
			return list.list
		elseif name == 'interp' then
			return function(self, dict)
				if self.kind == ValueType_RawString then 
					return self
				end
				local s = self.string
				local changed = false
				s = s:gsub("\\(.)", function(c)
					changed = true
					if false then
					elseif c == 'v' then return '\v'
					elseif c == 'n' then return '\n'
					elseif c == 't' then return '\t'
					elseif c == 'f' then return '\f'
					elseif c == 'r' then return '\r'
					else return c
					end
				end)
				s = s:gsub("%$([a-zA-Z0-9]+)", function(o)
					changed = true
					if not dict[o] then return "?" .. o .. "?" end
					if not dict[o].value then return "" end
					return dict[o].value.string
				end)
				if changed then
					return Value.fromString(s)
				else
					return self
				end
			end
		elseif name == 'sub' then
			local s = self.string
			return function(self, ...)
				--Todo: Support string_view
				return Value.fromString(string.sub(s,...))
			end
		elseif name == 'scanner' then
			--Todo: Support string_view
			return function(self)
				return setmetatable({
					source = self.string,
					left = 0,
					pos = 0,
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
			end
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


return Value