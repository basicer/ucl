local function argparse(template)
	local alist = {}
	local atab = {}

	local required = 0
	local i = -1
	for m in template:gmatch("[^%s]+") do
		i = i + 1
		if i > 0 then 
			if m:match("^%?.*%?$") then
				local t = {name=m:sub(2,-2), optional=true}
				if ( t.name:sub(1,1) == "-" ) then 
					t.name = t.name:sub(2)
				else
					table.insert(alist, t)
				end
				atab[t.name] = t
			else
				required = required + 1
			local t = {name=m, optional=false}
				table.insert(alist, t)
				atab[t.name] = t
			end
		end
	end

	return function(...)
		local ar = {...}
		local result = {}
		local nOptional = #ar - required
		if nOptional < 0 then
			error('wrong # args: should be "' .. template .. '"', 0)
		end
		local ak = 0

		local k = 1
		while k <= #ar do
			local v = ar[k]
			local pos
			while true do
				if v.string:sub(1,1) == '-' then
					local name = v.string:sub(2)
					if atab[name] then
						result[name] = ar[k+1]
						k = k + 1
						break
					end
				end

				repeat
					ak = ak + 1
					pos = alist[ak]
					if not pos then break end
				until not pos.optional or nOptional > 0

				if not pos then
					error('wrong # args: should be "' .. template .. '"', 0)
				end

				if pos.optional then
					nOptional = nOptional - 1
				end

				result[pos.name] = v
				break
			end
			k = k + 1
		end
		return result
	end
end



return argparse