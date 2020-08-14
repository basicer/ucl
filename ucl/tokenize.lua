local ValueType_None   = 0
local ValueType_Number = 1
local ValueType_String = 2
local ValueType_RawString = 3
local ValueType_List = 4
local ValueType_CommandList = 5



local function tokenize(inp)
	local Value = require('ucl/value')
	local scanner = inp:scanner()
	local str = inp.string
	local state = 0
	local line = 1
	local left = 0
	local level = 0
	local skip = 0
	local results = {}
	local lines = {}
	while true do
		local c, i = scanner:advance()
		if c == nil then break end
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


return tokenize