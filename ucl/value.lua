local Value = {}

local ValueType_None   = 0
local ValueType_Number = 1
local ValueType_String = 2
local ValueType_RawString = 3
local ValueType_List = 4
local ValueType_CommandList = 5

local function tokenize(str)
	local state = 0
	local line = 1
	local left = 0
	local level = 0
	local skip = 0
	local results = {}
	local lines = {}
	for i=1,#str+1 do
		local c = i > #str and '\n' or str:sub(i,i)
		if c == '\n' then line = line + 1 end
		if skip > 0 then
			skip = skip - 1
		elseif c == '\\' then
			skip = 1
		elseif ( (c == '\n' or c == ';') and state ~= 2 and state ~= 3 ) then
			if state == 6 then
				state = 0
			elseif state ~= 0 and i-1 >= left then
				table.insert(results, Value.fromStringView(str, left, i-1, ValueType_String))
			end
			if #results > 0 then 
				table.insert(lines, Value.fromList(results))
				results = {}
				state = 0
			end
			left = i + 1
		elseif state == 6 then
			left = i+1
		elseif state == 0 then
			if c == '{' then
				left = i+1
				state = 2
				level = 0
			elseif c == '"' then
				left = i+1
				state = 3
			elseif c == '[' then
				left = i+1
				state = 4
			elseif c == '#' then
				state = 6
			elseif c == ' ' or c == '\t' or c == '\v' or c == '\f' or c == '\r' then
				left = i+1
			else
				left = i
				state = 1
			end
		elseif state == 1 then
			if c == '#' then
				table.insert(results,Value.fromStringView(str, left, i-1, ValueType_String))
				state = 6
			elseif c  == ' ' or c == '\t' or c == '\v' or c == '\f' or c == '\r' then
				table.insert(results,Value.fromStringView(str, left, i-1, ValueType_String))
				state = 0
			elseif c == '"' then
				state = 3
			end
		elseif state == 2 then
			if c == '{' then level = level + 1 end
			if c == '}' then
				if level == 0 then
					table.insert(results,Value.fromStringView(str, left, i-1, ValueType_RawString))
					left = i+1
					state = 5
				else
					level = level - 1
				end
			end
		elseif state == 3 then
			if c == '"' then
				table.insert(results,Value.fromStringView(str, left, i-1, ValueType_String))
				left = i+1
				state = 5
			end
		elseif state == 4 then
			if c == ']' then
				table.insert(results,Value.fromStringView(str, left, i-1, ValueType_CommandList))
				left = i+1
				state = 5
			end
		elseif state == 5 then
			if c ~= ' ' and c ~= '\t' then
				error("Invalid character after string: " .. c .. " on line " .. line)
			else
				state = 0
			end
		end
	end

	if #results > 0 then
		table.insert(lines, Value.fromList(results))
	end
	return lines
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
			local list = tokenize(self.string)
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
					elseif c == '"' then return '"'
					elseif c == '\\' then return '\\'
					else return '\\' .. c
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