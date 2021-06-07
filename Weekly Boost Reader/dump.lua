--[[
Copyright (c) Jérôme Vuarand

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
-- ]]

local _M = {}
local _NAME = ... or 'test'

local tostring = tostring
local io = require 'io'
local os = require 'os'
local math = require 'math'
local table = require 'table'
local string = require 'string'

_M.groupsize = 10000

local dumptablecontent

local tkeys = {
	boolean = true,
	number = true,
	string = true,
}
local tvalues = {
	boolean = true,
	number = true,
	string = true,
	table = true,
}

local function dumptable(table, write, level, refs, format)
	-- prefix and suffix
	local mt = getmetatable(table)
	local prefix = mt and mt.__dump_prefix
	local suffix = mt and mt.__dump_suffix
	if type(prefix)=='function' then
		prefix = prefix(table)
	end
	prefix = prefix or ""
	if type(suffix)=='function' then
		suffix = suffix(table)
	end
	suffix = suffix or ""
	
	-- count keys
	local nkeys = 0
	for k,v in pairs(table) do
		nkeys = nkeys + 1
		local tk,tv = type(k),type(v)
		if not tkeys[tk] then
			return nil,"unsupported key type '"..tk.."'"
		end
		if not (tvalues[tv] or getmetatable(v) and getmetatable(v).__dump) then
			return nil,"unsupported value type '"..tv.."'"
		end
	end
	
	-- if too many keys, use multiple closures
	if nkeys > _M.groupsize then
		local success,err
		if format=='compact' then
			success,err = write(prefix.."(function()local t={function()return{")
		else
			success,err = write(((prefix..[[
(function()
	local t = { function() return {
]]):gsub("\n", "\n"..("\t"):rep(level))))
		end
		if not success then return nil,err end
		local groupsep
		if format=='compact' then
			groupsep = '}end,function()return{'
		else
			groupsep = ("\t"):rep(level+1)..'} end, function() return {\n'
		end
		success,err = dumptablecontent(table, write, level+2, _M.groupsize, groupsep, refs, format)
		if not success then return nil,err end
		if format=='compact' then
			success,err = write("}end}local r={}for _,f in ipairs(t) do for k,v in pairs(f()) do r[k]=v end end return r end)()"..suffix)
		else
			success,err = write((([[
	} end }
	local result = {}
	for _,f in ipairs(t) do
		for k,v in pairs(f()) do
			result[k] = v
		end
	end
	return result
end)()]]..suffix):gsub("\n", "\n"..("\t"):rep(level))))
		end
		if not success then return nil,err end
		return true
	elseif nkeys==0 then
		local success,err
		if format=='compact' then
			success,err = write(prefix.."{}"..suffix)
		else
			success,err = write(prefix.."{ }"..suffix)
		end
		if not success then return nil,err end
		return true
	else
		local success,err
		if format=='compact' then
			success,err = write(prefix.."{")
		else
			success,err = write(prefix.."{\n")
		end
		if not success then return nil,err end
		success,err = dumptablecontent(table, write, level+1, nil, nil, refs, format)
		if not success then return nil,err end
		if format=='compact' then
			success,err = write("}"..suffix)
		else
			success,err = write(("\t"):rep(level).."}"..suffix)
		end
		if not success then return nil,err end
		return true
	end
end

local function dumpvalue(v, write, level, refs, format, iskey)
	local mt = getmetatable(v)
	local dump = mt and mt.__dump
	if type(dump)=='function' then
		dump = dump(v)
	end
	if dump~=nil then
		return write(dump)
	end
	local t = type(v)
	if t=='string' then
		if not iskey and v:match('\n.*\n') and not v:match('[\000-\008\011-\031\127]') and format~='compact' then
			local eq
			for i=0,math.huge do
				eq = string.rep('=', i)
				if not v:match('%]'..eq..'%]') then
					break
				end
			end
			return write('['..eq..'[\n'..v..']'..eq..']')
		else
			return write('"'..v:gsub('[%z\1-\31\127"\\]', function(c)
				if c=='\\' then
					return '\\\\'
				elseif c=='"' then
					return '\\"'
				elseif c=='\t' then
					return '\\t'
				elseif c=='\n' then
					return '\\n'
				elseif c=='\r' then
					return '\\r'
				else
					return string.format('\\%03d', string.byte(c))
				end
			end)..'"')
		end
	elseif t=='number' then
		if v~=v then -- nan
			return write('0/0')
		elseif v==1/0 then -- +inf
			return write('1/0')
		elseif v==-1/0 then -- -inf
			return write('-1/0')
		elseif v==math.floor(v) then
			return write(tostring(v))
		else
			local s = tostring(v)
			if tonumber(s)~=v then
				s = string.format('%.18f', v):gsub('(%..-)0*$', '%1')
			end
			if tonumber(s)~=v then
				s = string.format("%a", v) -- Lua 5.3.1
			end
			if tonumber(s)~=v then
				s = string.format("%.13a", v) -- Lua 5.3.0
			end
			return write(s)
		end
	elseif t=='boolean' then
		if v then
			return write('true')
		else
			return write('false')
		end
	elseif t=='nil' then
		return write('nil')
	elseif t=='table' then
		return dumptable(v, write, level, refs, format)
	else
		return nil,"unsupported value type '"..t.."'"
	end
end

local lua_keywords = {
	['and'] = true,
	['break'] = true,
	['do'] = true,
	['else'] = true,
	['elseif'] = true,
	['end'] = true,
	['false'] = true,
	['for'] = true,
	['function'] = true,
	['if'] = true,
	['in'] = true,
	['local'] = true,
	['nil'] = true,
	['not'] = true,
	['or'] = true,
	['repeat'] = true,
	['return'] = true,
	['then'] = true,
	['true'] = true,
	['until'] = true,
	['while'] = true,
}

local function dumppair(k, v, write, level, refs, format, last_key)
	if refs and refs[v] and refs[v].link then
		v = refs[v].link
	end
	local success,err,assignment
	if format=='compact' then
		assignment = "="
	else
		success,err = write(("\t"):rep(level))
		if not success then return nil,err end
		assignment = " = "
	end
	local tk = type(k)
	if tk=='string' and k:match("^[_a-zA-Z][_a-zA-Z0-9]*$") and not lua_keywords[k] then
		success,err = write(k)
		if not success then return nil,err end
	elseif tk=='string' or tk=='number' or tk=='boolean' then
		success,err = write('[')
		if not success then return nil,err end
		success,err = dumpvalue(k, write, level, refs, format, true)
		if not success then return nil,err end
		success,err = write(']')
		if not success then return nil,err end
	elseif tk=='nil' then
		-- we are in the array part
		assignment = ""
	else
		error("unsupported key type '"..type(k).."'")
	end
	success,err = write(assignment)
	if not success then return nil,err end
	success,err = dumpvalue(v, write, level, refs, format, false)
	if not success then return nil,err end
	if format=='compact' then
		if last_key then
			success,err = true
		else
			success,err = write(",")
		end
	else
		success,err = write(",\n")
	end
	if not success then return nil,err end
	return true
end

local function keycomp(a, b)
	local ta,tb = type(a),type(b)
	if ta==tb then
		return a < b
	else
		return ta=='string'
	end
end

local tsort = table.sort
local function ksort(keys)
	local skeys = {}
	for k in pairs(keys) do skeys[#skeys+1] = k end
	tsort(skeys, keycomp)
	return skeys
end

local function dumptablesection(table, write, level, keys, state, refs, format, last_key)
	for _,k in ipairs(keys) do
		local v = table[k]
		if state then
			state.i = state.i + 1
			if state.i % state.size == 0 then
				local success,err = write(state.sep)
				if not success then return nil,err end
			end
		end
		local success,err = dumppair(k, v, write, level, refs, format, k==last_key or state and state.i % state.size == state.size - 1)
		if not success then return nil,err end
	end
	return true
end

local function dumptableimplicitsection(table, write, level, state, refs, format, last_key)
	for k,v in ipairs(table) do
		if state then
			state.i = state.i + 1
			if state.i % state.size == 0 then
				local success,err = write(state.sep)
				if not success then return nil,err end
				state.explicit = true
			end
		end
		local success,err
		if state and state.explicit then
			success,err = dumppair(k, v, write, level, refs, format, k==last_key or state.i % state.size == state.size - 1)
		else
			success,err = dumppair(nil, v, write, level, refs, format, k==last_key or state and state.i % state.size == state.size - 1)
		end
		if not success then return nil,err end
	end
	return true
end

function dumptablecontent(table, write, level, groupsize, groupsep, refs, format)
	-- order of groups:
	-- - explicit keys
	--   - keys with simple values
	--   - keys with structure values (table with only explicit keys)
	--   - keys with mixed values (table with both exiplicit and implicit keys)
	--   - keys with array values (table with only implicit keys)
	-- - set part (explicit key with boolean value)
	-- - implicit keys
	-- order within a group:
	-- - string keys in lexicographic order
	-- - numbers in increasing order
	-- :TODO: handle tables as keys
	-- :TODO: handle sets
	
	-- extract implicit keys
	local implicit = {}
	local last_implicit_key
	for k,v in ipairs(table) do
		implicit[k] = true
		last_implicit_key = k
	end
	-- categorize explicit keys
	local simples = {}
	local structures = {}
	local mixeds = {}
	local arrays = {}
	for k,v in pairs(table) do
		if not implicit[k] then
			if type(v)=='table' then
				if v[1]==nil then
					structures[k] = true
				else
					local implicit = {}
					for k in ipairs(v) do
						implicit[k] = true
					end
					local mixed = false
					for k in pairs(v) do
						if not implicit[k] then
							mixed = true
							break
						end
					end
					if mixed then
						mixeds[k] = true
					else
						arrays[k] = true
					end
				end
			else
				simples[k] = true
			end
		end
	end
	-- sort keys
	simples = ksort(simples)
	structures = ksort(structures)
	mixeds = ksort(mixeds)
	arrays = ksort(arrays)
	-- find last key
	local last_key = last_implicit_key
	if last_key==nil then last_key = arrays[#arrays] end
	if last_key==nil then last_key = mixeds[#mixeds] end
	if last_key==nil then last_key = structures[#structures] end
	if last_key==nil then last_key = simples[#simples] end
	
	local success,err,state
	if groupsize and groupsep then
		state = {
			i = 0,
			size = groupsize,
			sep = groupsep,
		}
	end
	success,err = dumptablesection(table, write, level, simples, state, refs, format, last_key)
	if not success then return nil,err end
	success,err = dumptablesection(table, write, level, structures, state, refs, format, last_key)
	if not success then return nil,err end
	success,err = dumptablesection(table, write, level, mixeds, state, refs, format, last_key)
	if not success then return nil,err end
	success,err = dumptablesection(table, write, level, arrays, state, refs, format, last_key)
	if not success then return nil,err end
	success,err = dumptableimplicitsection(table, write, level, state, refs, format, last_key)
	if not success then return nil,err end
	return true
end

local function ref_helper(processed, pending, cycles, refs, value, parent, key, path)
	if type(value)=='table' then
		local vrefs = refs[value]
		if not vrefs then
			vrefs = {
				value = value,
			}
			refs[value] = vrefs
		end
		table.insert(vrefs, {parent=parent, key=key})
		if pending[value] then
			cycles[value] = {pending[value], {key, path}}
			return
		end
		if not processed[value] then
			local path = {key, path}
			processed[value] = true
			pending[value] = path
			for k,v in pairs(value) do
				ref_helper(processed, pending, cycles, refs, k, value, nil, path)
				ref_helper(processed, pending, cycles, refs, v, value, k, path)
			end
			pending[value] = nil
			-- only assign an index once the children have one
			refs.last = refs.last + 1
			vrefs.index = refs.last
		end
	end
end

local prefixes = {
	table = 't',
	['function'] = 'f',
	thread = 'c',
	userdata = 'u',
}

local function check_refs(root)
	local processed = {}
	local pending = {}
	local cycles = {}
	local refs = {last=0}
	ref_helper(processed, pending, cycles, refs, root, nil, nil)
	refs.last = nil
	for value,vrefs in pairs(refs) do
		if #vrefs==1 then
			refs[value] = nil
		end
	end
	return cycles,refs
end

local function dumprefs(refs, file, last)
	if not last then last = {0} end
	if next(refs) then
		-- order the values from last to first discovered according to .index
		local refs2 = {}
		for value,vrefs in pairs(refs) do
			assert(vrefs.value == value)
			table.insert(refs2, vrefs)
		end
		table.sort(refs2, function(a, b) return a.index < b.index end)
		-- check all references
		for _,vrefs in ipairs(refs2) do
			for _,ref in ipairs(vrefs) do
				assert(ref.parent, "reference has no parent") -- this should trigger a cycle error earlier
				assert(ref.key~=nil, "not yet implemented") -- tables as keys
			end
		end
		-- generate an id and a link
		for i,vrefs in ipairs(refs2) do
			vrefs.id = prefixes[type(vrefs.value)]..tostring(i)
			vrefs.link = setmetatable({}, {__dump=vrefs.id})
		end
		-- dump shared values
		for _,vrefs in ipairs(refs2) do
			local success,err = file:write("local "..vrefs.id.." = ")
			if not success then return nil,err end
			success,err = dumpvalue(vrefs.value, function(...) return file:write(...) end, 0, refs, 'default', false)
			if not success then return nil,err end
			success,err = file:write("\n")
			if not success then return nil,err end
		end
	end
	return true
end

local function cycle_paths(cycles)
	local paths = {}
	for _,path_pair in pairs(cycles) do
		local top,bottom = path_pair[1],path_pair[2]
		local root = {}
		local cycle = {}
		local it = bottom
		while it~=top do
			table.insert(cycle, 1, it[1])
			it = it[2]
		end
		while it and it[1] do
			table.insert(root, 1, it[1])
			it = it[2]
		end
		table.insert(paths, {root, cycle})
	end
	return paths
end

function _M.tostring(value, format, ignore_refs)
	if type(format)=='boolean' then ignore_refs,format = format,ignore_refs end
	if not format then format = 'default' end
	local cycles,refs = check_refs(value)
	if next(cycles) then
		return nil,"cycles in value",cycle_paths(cycles)
	end
	if next(refs) and not ignore_refs then
		return nil,"mutable values (tables) with multiple references"
	end
	local t = {}
	local success,err = dumpvalue(value, function(str) table.insert(t, str); return true end, 0, refs, format, false)
	if not success then return nil,err end
	return table.concat(t)
end

function _M.tofile(value, file)
	local cycles,refs = check_refs(value)
	if next(cycles) then
		return nil,"cycles in value",cycle_paths(cycles)
	end
	local filename
	if type(file)=='string' then
		filename = file
		file = nil
	end
	local success,err
	if filename then
		file,err = io.open(filename, 'wb')
		if not file then return nil,err end
	end
	success,err = dumprefs(refs, file)
	if not success then return nil,err end
	success,err = file:write"return "
	if not success then return nil,err end
	success,err = dumpvalue(value, function(...) return file:write(...) end, 0, refs, 'default', false)
	if not success then return nil,err end
	success,err = file:write("\n-- v".."i: ft=lua\n")
	if not success then return nil,err end
	if filename then
		success,err = file:close()
		if not success then return nil,err end
	end
	return true
end

function _M.toscript(value)
	local file = {}
	function file:write(str)
		self[#self+1] = str
		return true
	end
	local success,err,extra = _M.tofile(value, file)
	if not success then return nil,err,extra end
	return table.concat(file)
end

function _M.tofile_safe(value, filename, oldsuffix)
	local lfs = require 'lfs'
	
	if oldsuffix and lfs.attributes(filename, 'mode') then
		local i,suffix = 0,oldsuffix
		while io.open(filename..suffix, "rb") do
			i = i+1
			suffix = oldsuffix..i
		end
		assert(os.rename(filename, filename..suffix))
	end
	local tmpfilename = filename..'.new'
	local err,file,success
	file,err = io.open(tmpfilename, "wb")
	if not file then return nil,err end
	success,err,extra = _M.tofile(value, file)
	if not success then
		file:close()
		os.remove(tmpfilename)
		return nil,err,extra
	end
	success,err = file:close()
	if not success then
		os.remove(tmpfilename)
		return nil,err
	end
	if lfs.attributes(filename, 'mode') then
		assert(os.remove(filename))
	end
	assert(os.rename(tmpfilename, filename))
	return true
end

if _NAME=='test' then
	require 'test'
	local load_
	if _VERSION=="Lua 5.1" then
		load_ = function(str) return assert(loadstring(str))() end
	elseif _VERSION=="Lua 5.2" or _VERSION=="Lua 5.3" then
		load_ = function(str) return assert(load(str))() end
	else
		error("unsupported Lua version")
	end
	
	-- some simple values
	expect([["\000\001\007\t\n\r\014\031 !~\127]].."\128\129\254\255"..[["]],
		_M.tostring(string.char(0, 1, 7, 9, 10, 13, 14, 31, 32, 33, 126, 127, 128, 129, 254, 255)))
	expect('0/0', _M.tostring(0/0))
	expect('1/0', _M.tostring(1/0))
	expect('-1/0', _M.tostring(-1/0))
	expect("[[\nfoo\nbar\nbaz]]", _M.tostring("foo\nbar\nbaz"))
	expect("[[\nfoo\n\tbar\nbaz]]", _M.tostring("foo\n\tbar\nbaz"))
	expect("[=[\nfoo\nbar[bar[bar]]\nbaz]=]", _M.tostring("foo\nbar[bar[bar]]\nbaz"))
	
	local value = -0.00223606797749979
	expect(value, tonumber(_M.tostring(value)))
	
	-- some numbers get damaged by the regular tostring
	local value = 0.05 * math.cos(math.pi / 2)
	assert(tonumber(tostring(value))~=value)
	expect(value, tonumber(_M.tostring(value)))
	
	-- decimal approximations should be shown as decimal
	local value = 51.6409
	expect("51.6409", _M.tostring(value))
	
	-- a complete file showing key ordering
	local str = [[
return {
	Abc = false,
	FOO = 42,
	Foo = "42",
	abc = true,
	["f O"] = 42,
	fOO = 42,
	foo = "42",
	[-1] = 37,
	[0] = 37,
	[42] = 37,
	Bar = {
		foo = 142,
	},
	bar = {
		foo = 142,
	},
	Baz = {
		foo = 242,
		237,
	},
	baz = {
		foo = 242,
		237,
	},
	Baf = {
		337,
	},
	baf = {
		337,
	},
	37,
}
-- v]]..[[i: ft=lua
]]
	local t = load_(str)
	
	local filename = os.tmpname()
	if pcall(require, 'lfs') then
		assert(_M.tofile_safe(t, filename))
	else
		assert(_M.tofile(t, filename))
	end
	local file = assert(io.open(filename, "rb"))
	local content = assert(file:read"*a")
	assert(file:close())
	expect(str, content)
	local str2 = assert(_M.tostring(t))
	expect(content:sub(8, -16), str2)
	
	-- compact tostring
	expect([[{Abc=false,FOO=42,Foo="42",abc=true,["f O"]=42,fOO=42,foo="42",[-1]=37,[0]=37,[42]=37,Bar={foo=142},bar={foo=142},Baz={foo=242,237},baz={foo=242,237},Baf={337},baf={337},37}]], _M.tostring(t, 'compact'))
	
	-- toscript
	expect(str, _M.toscript(t))
	
	-- cycle detection
	local t = {}
	t[1] = t
	local value,msg,extra = _M.tostring(t)
	expect(nil, value)
	expect('string', type(msg))
	expect({{{}, {1}}}, extra)
	local value,msg,extra = _M.toscript(t)
	expect(nil, value)
	expect('string', type(msg))
	expect({{{}, {1}}}, extra)
	
	local t = {}
	t[1] = {}
	t[1].a = {}
	t[1].a[true] = t[1]
	local value,msg,extra = _M.tostring(t)
	expect({{{1}, {'a', true}}}, extra)
	local value,msg,extra = _M.toscript(t)
	expect({{{1}, {'a', true}}}, extra)
	
	local t = {}
	t[1] = {}
	t[1].a = {}
	t[1].a[true] = t
	local value,msg,extra = _M.tostring(t)
	expect({{{}, {1, 'a', true}}}, extra)
	local value,msg,extra = _M.toscript(t)
	expect({{{}, {1, 'a', true}}}, extra)
	
	-- shared refs support
	local t1 = {}
	local t = {t1, t1}
	local value,msg = _M.tostring(t)
	expect(nil, value)
	expect('string', type(msg))
	local value,msg = _M.toscript(t)
	expect('string', type(value))
	local value,msg = _M.tostring(t, true)
	expect('string', type(value))
	
	-- BFS correctness
	local t1 = {"foo"}
	local t2 = {{t1}}
	local t = {t1, t2, t2}
	local filename = os.tmpname()
	assert(_M.tofile(t, filename))
	local T = dofile(filename)
	expect("foo", T[2][1][1][1])
	assert(T[2]==T[3])
	assert(T[2][1][1]==T[1])
	
	-- the original data should be preserved
	local t1 = {"foo"}
	local t2 = {{t1}}
	local t = {t1, t2, t2}
	local filename = os.tmpname()
	assert(_M.tofile(t, filename))
	assert(t[2])
	assert(t[2][1])
	assert(t[2][1][1])
	expect("foo", t[2][1][1][1])
	assert(t[2]==t[3])
	assert(t[2][1][1]==t[1])
	
	-- long tables
	local t = {}
	for i=1,_M.groupsize + 1 do
		t[i] = 0
	end
	local str = _M.tostring(t)
	assert(type(str)=='string')
	local t2 = load_("return "..str)
	expect(_M.groupsize + 1, #t2)
	for i=1,_M.groupsize + 1 do
		expect(0, t2[i])
	end
	local str = _M.tostring(t, 'compact')
	assert(type(str)=='string')
	local t2 = load_("return "..str)
	expect(_M.groupsize + 1, #t2)
	for i=1,_M.groupsize + 1 do
		expect(0, t2[i])
	end
	expect("(function()local t={function()return{"..string.rep("0,", _M.groupsize-2).."0}end,function()return{[".._M.groupsize.."]=0,["..(_M.groupsize+1).."]=0}end}local r={}for _,f in ipairs(t) do for k,v in pairs(f()) do r[k]=v end end return r end)()", str)
	
	print("all tests passed successfully")
end

return _M
