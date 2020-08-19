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
					if not pos then return result end
				until not pos.optional or nOptional > 0

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

local function test(tpl, str)
	print(str)
	local f = argparse(tpl)
	local ucl = require('ucl')
	local cl = ucl.Value.fromString(str)
	local o = f(unpack(cl.list))
	for k,v in pairs(o) do
		print("->", k, v)
	end
	print()
end

test('test name desc ?flags? body', 'a b c')
test('test name desc ?flags? body', '-body b -name n -retCode 2')

test('test name ?desc? ?-match? ?-returnCodes? ?constraints? body result', [[expr-old-38.1 {Verify Tcl_ExprString's basic operation} -constraints {fails testexprstring} -body {
    list [testexprstring "1+4"] [testexprstring "2*3+4.2"] \
	    [catch {testexprstring "1+"} msg] $msg
} -match glob -result {5 10.2 1 *}
test expr-old-38.2 {Tcl_ExprString} {fails} testexprstring {
    # This one is "magical"
    testexprstring {} {fails}
} 0
test expr-old-38.3 {Tcl_ExprString} {fails} -constraints testexprstring -body {
    testexprstring { } {fails}
} -returnCodes error -match glob -result *
]])

--test('regexp ?-nocase? ?-line? ?-indices? ?-start offset? ?-all? ?-inline? ?--? exp string ?matchVar? ?subMatchVar...?', 'e s')

return argparse