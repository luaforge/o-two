-- *********************************************************************************
-- * Copyright 2002 Noemi Rodriquez & Roberto Ierusalimschy.  All rights reserved. *
-- *********************************************************************************
-- $Id: idl.lua,v 1.1 2004-07-21 03:15:57 rmello Exp $

local basictypes = {"short", "long", "ushort", "ulong", "float", "double",
"char", "string", "boolean", "octet", "TypeCode",  "any", "null", "void"}

local unitypes = {"array", "sequence"}

IDL = {}

for i=1,table.getn(basictypes) do
  local t = basictypes[i]
  IDL[t] = {_type = t}
end

for i=1,table.getn(unitypes) do
  local t = unitypes[i]
  IDL[t] = function (o)
             o._type = t
             o.elementtype = o.elementtype or o[1]
             return o
           end
end

for _,t in { "union", "const", "attribute", "module"} do
  local t = t
  IDL[t] = function (o) o._type = t; return o end
end

local validtype = function (t) return type(t) == 'table' and t._type end


local checkfield = function (f)
  if type(f.name) ~= 'string' then
    error('invalid name for struct/union/exception field ')
  end
  if not validtype(f.type) then
    error('invalid type for struct/union/exception field '..f.name)
  end
end

local checkfields = function (fields)
  local newf = {}
  for i=1,table.getn(fields) do
    local f = fields[i]
    checkfield(f)
    newf[i] = f
  end
  return newf
end

function IDL.struct (s)
  assert(type(s) == 'table', "struct must be a table")
  s._type = 'struct'
  s.fields = checkfields(s)
  return s
end

function IDL.alias (t)
  t._type = 'alias' 
  t.type = t.type or t[1]
  return t 
end

function IDL.Object (t)
  return {
           _type = 'Object',
           type_id = t -- or 'IDL:omg.org/CORBA/Object:1.0'
         }
end

function IDL.except (s)
  assert(type(s) == 'table', "exception must be a table")
  s._type = 'except'
  s.members = checkfields(s)
  return s
end

function IDL.enum (s)
  s._type = 'enum'
  if s.enumvalues == nil then
    s.enumvalues = {}
    for i=1,table.getn(s) do
      s.enumvalues[i] = s[i]
    end
  end
  s.name2val = {}
  for i=1,table.getn(s.enumvalues) do
    s.name2val[s.enumvalues[i]] = i-1
  end
  return s
end

function IDL.union (u)
  assert(type(u) == 'table', "union must be a table")
  u._type = 'union'
  if not validtype(u.switch) then
    error("invalid discriminant type for union")
  end
  if not u.default then
    u.default = -1 -- indicates no default in cdr encoding
  end
  local fields = u.options
  assert(type(fields) == 'table', "union options must be a table")
  for k,f in fields do checkfield(f) end
  return u
end

function IDL.operation (o)
  o._type = "operation"
  o.kind = 'dk_Operation'
  o.params_in = {}
  o.params_out = {}
  for i=1, table.getn(o.parameters) do
    local p = o.parameters[i]
    p.mode = p.mode or "IN"
    if string.find(p.mode, "IN") then
      table.insert(o.params_in, p)
    end
    if string.find(p.mode, "OUT") then
      table.insert(o.params_out, p)
    end
  end
  local e = {}
  if o.exceptions then
    for i=1, table.getn(o.exceptions) do
      e[o.exceptions[i].id] = o.exceptions[i]
    end
  end
  o.exceptions = e
  return o
end


--------------------------
-- Factory Functions
--------------------------

CorbaObject = {}

function IDL.newObject (o)
  o._iiop = ""
  o.exc_handlers = {}
  setmetatable(o, CorbaObject)
  return o
end


--------------------------
-- some auxiliar functions
--------------------------


function IDL.tohexa (t)
  return (string.gsub(t, '(.)', function (c) return (string.format("%02x", string.byte(c))) end))
end

function IDL.fromhexa (t)
  return (string.gsub(t, '(%x%x)', function (h) return string.char(tonumber(h,16)) end))
end


--------------------------
-- IDL parser
--------------------------

function IDL.old_parser (text)
  local sig = {}

  --print(text) print'-----------------------'

  text = string.gsub(text, "#.-\n", "") -- for now, ignore preproc directives

  local consume = function (pos, pattern)
    local a, b
    if not string.find(pattern, "%(") then
      pattern = '('..pattern..')'
    end
    a, b, token = string.find(text, "^%s*"..pattern, pos)
    if a then
      return b+1, token
    else
      return pos, nil
    end
  end
    
  local readInterface = function (pos, interface_name)
    local int_sig = {}

    while 1 do
      pos, token = consume(pos, "[%w_}]+")
--print("*T",token, "in ", interface_name)

      if token == nil then
        return nil, "unexpected input at position "..pos
      elseif token == '}' then
        pos, token = consume(pos, ';')
        if token ~= ';' then
          return nil, "expected ';' at position "..pos
        end
        
        sig['IDL:'..interface_name..':1.0'] = int_sig
        
        return pos, nil
      else
        local func_sig = {}
        local ret_type = token

        func_sig.result = IDL[ret_type]
        func_sig.params_in = {}
        func_sig.params_out = {}

        pos, token = consume(pos, "[%w_]+")
        local func_name = token

        if func_name == nil then
          return nil, "expected function name at position "..pos
        end


        pos, token = consume(pos, '(%()')
        --print(token)
        if token ~= '(' then
          return nil, "expected '(' at position "..pos
        end

        while 1 do
          pos, token = consume(pos, "([%w_)]+)")
--print("*T",token, "in ", func_name, "(parameter list)")
          if token == nil then
            return nil, "unexpected input at position "..pos
          elseif token == ')' then
            pos, token = consume(pos, ';')
            if token ~= ';' then
              return nil, "expected ';' at position "..pos
            end
            break
          else
            local way = token
            pos, token = consume(pos, "([%w_]+)")
            local kind = token 
            pos, token = consume(pos, "([%w_]+)")
            local name = token

            if name == nil or kind == nil then
              return nil, "unexpected input at position "..pos
            end
--print("*P", way, kind, name)          

            if way == 'in' then
              table.insert( func_sig.params_in, { type = IDL[kind] } )
            elseif way == 'out' then
              table.insert( func_sig.params_out, { type = IDL[kind] } )
            elseif way == 'inout' then
              table.insert( func_sig.params_in, { type = IDL[kind] } )
              table.insert( func_sig.params_out, { type = IDL[kind] } )
            end

          end

        end

--print("*F", ret_type, func_name)
        int_sig[func_name] = func_sig
        
      end
    end
  end

  local readModule = function (pos, module_name)
    local module = {}
    while 1 do
      pos, token = consume(pos, "[%w_}]+")
--print("*T",token, "in ", module_name)

      if token == nil then
        return nil, "unexpected input at position "..pos
      elseif token == '}' then
        pos, token = consume(pos, ';')
        if token ~= ';' then
          return nil, "expected ';' at position "..pos
        end
        return pos
      elseif token == 'enum' then
        pos, token = consume(pos, "[%w_]+")
        if token == nil then
          return nil, "expected module name at position "..pos
        end
	local name = token
	local values = {}
--print("*E", token)
        pos, token = consume(pos, "{")
        if token ~= '{' then
          return nil, "expected '{' at position "..pos
        end
	pos, token = consume(pos, '"([^"])"')
	while token do
--print("*EI", token)
		table.insert(values, token)
		pos, token = consume(pos, ',%s*"([^"])"')
	end
        pos, token = consume(pos, "}")
        if token ~= '}' then
          return nil, "expected '}' at position "..pos
        end
	module[name] = IDL.enum(values)
      elseif token == 'interface' then
        pos, token = consume(pos, "[%w_]+")
        if token == nil then
          return nil, "expected interface name at position "..pos
        end
        local name = token
--print("*I", token)

        pos, token = consume(pos, "{")
        if token ~= '{' then
          return nil, "expected '{' at position "..pos
        end

        local err
        pos, err = readInterface(pos, module_name..'/'..name)
        if err then
          return pos, err
        end
      end
    end
  end
  
  local pos = 1
  local token

  while 1 do
    pos, token = consume(pos, "[%w_}]+")

--print("*T",token)

    if token == nil then
      break
    elseif token == 'module' then
      pos, token = consume(pos, "[%w_]+")
      if token == nil then
        return nil, "expected module name at position "..pos
      end
      local name = token
--print("*M", token)

      pos, token = consume(pos, "{")
      if token ~= '{' then
        return nil, "expected '{' at position "..pos
      end

      local err
      pos, err = readModule(pos, name)
      if err then
        return pos, err
      end
      
    end
  end
  

  return sig

end

function IDL.interface (t)
  return t
end

function IDL.readModule (name, data)
  assert(type(data) == 'table')
  assert(type(name) == 'string')

  for i, v in data do
    if type(v) == 'table' then
      IR.sigs['IDL:'..name..'/'..i..':1.0'] = v
      print('--<IDL:'..name..'/'..i..':1.0>--')
      --pr(v)
    end
  end
end

gsub = string.gsub

local private = {}

function private.preprocess(text)
  -- Ignores the /*  */ and // comments on the IDL
  text = gsub( '\n'..text..'\n', '[\n\r]*/%*.-%*/\n', '\n\n' )
  text = gsub( '\n'..text..'\n', '[\n\r]*//[^\n]*\n', '\n\n' )
  local defines = { ___depth = 0 }
  text = gsub('\n'..text..' \n', "[\n\r]#(%w+)%s+([^\n]+)", function(op, rest)
--print(string.format("*pp |%s|%s|", op, rest))
    if op == 'define' then
      local a,b, name, value = string.find(rest, '%s*([%w_]+)%s*(.*)$')
      value = value or ""
      if value == "" then value = "(null)" end
      defines[name] = value
      --print(name..'='..value..'!')
      return "\n"
    elseif op == 'ifdef' or op == 'ifndef' then
--print(op,rest,defines[rest],defines.___depth)
      if defines.___depth > 0 then
        defines.___depth = defines.___depth + 1
        return ""
      elseif defines[rest] ~= nil and op == 'ifndef' then
        defines.___depth = 1
        return "$BEGIN_CUT$"
      elseif defines[rest] == nil and op == 'ifdef' then
        defines.___depth = 1
        return "$BEGIN_CUT$"
      else
        return "\n"
      end
    elseif op == 'endif' then
      if defines.___depth > 0 then
        defines.___depth = defines.___depth - 1
        if defines.___depth == 0 then
          return "$END_CUT$"..'\n'..rest
        end
      end
      return '\n'..rest
    else
      error("undefined preprocessor directive: #"..op)
    end
  end)

  text = gsub(text, '//', '--//')
  text = gsub(text, '%$BEGIN_CUT%$.-%$END_CUT%$', '')
  text = gsub(text, '(%s[%w_]+%s)', function(s)
    local a,b,idx = string.find(s, "%s([%w_]+)%s")
    return ' '..(defines[idx] or s )..' '
  end)

  return text
end

function private.treattype (kind)
  if IDL[kind] then
    kind = 'IDL.'..kind
  elseif string.find( kind, '::' ) then
    kind = gsub( kind, '::', '.' )
    kind = gsub( kind, '^(%w+)%.(%w+)', "IR.sigs['IDL:%1/%2:1.0']" )
  else
    kind = "$MODULE$."..kind
  end
  return kind
end

function private.get_type(defline)
-- recebe 'sequence<book> teste[5]', retorna 'IDL.sequence{ $MODULE$.book}', 'teste[5]'
  local t = {}
  assert(type(defline)=="string")
  defline = gsub(defline, "%s*([%w_.:]+)%s*", function(s) t.kind=s return "" end, 1)
  assert(t.kind)
  if t.kind == 'sequence' then
    t.sequence = t.kind
    t.kind = nil
    defline = gsub(defline, "%s*<%s*([%w_.:]+)%s*>%s*", function(s) t.kind=s return "" end, 1)
  end

  t.kind = private.treattype(t.kind)
  if t.sequence then
  	t.kind = ' IDL.sequence { '..t.kind..' }, '
  end

  return t.kind, defline
end

function IDL.parse (text)
  text = private.preprocess(text)
  local modules = {}

  -- process modules
  local defs = gsub(text, 'module%s+([%w_]+)%s*(%b{})%s*;', function (module_name, text)
--print("!m", module_name)
    
    modules[module_name] = {}

    text = gsub(text, 'enum%s+([%w_]+)%s*(%b{})%s*;', function (enum_name, text)
--print("!e", enum_name)
      text = gsub(text, '([%w_]+)', '"%1"')
      return enum_name..' = IDL.enum '..text..',\n'
    end)

    text = gsub(text, 'struct%s+([%w_]+)%s*(%b{})%s*;', function (struct_name, text)
--print("!s", struct_name)
      modules[module_name][struct_name] = {}
      text = gsub(text, '%s*([%w_.:]+)%s+([%w_]+)%s*;%s*', function(kind, name)
        kind = private.treattype(kind)
        return '\n  {name="'..name..'", type = '..kind..'},'
      end)
      return struct_name..' = IDL.struct '..text..',\n'
    end)

    text = gsub(text, 'exception%s+([%w_]+)%s*(%b{})%s*;', function (exception_name, text)
--print("!x", struct_name)
      text = gsub(text, '%s*([%w_.:]+)%s+([%w_]+)%s*;%s*', function(kind, name)
        kind = private.treattype(kind)
        return '\n  {name="'..name..'", type = '..kind..'},'
      end)
      return exception_name..' = IDL.exception '..text..',\n'
    end)

    text = gsub(text, 'typedef%s+([^;]+);', function (defline)
      local kind, rest = private.get_type(defline)
      -- recebe 'sequence<book> teste[5]', retorna 'IDL.sequence{ $MODULE$.book}', 'teste[5]'
      local a,b,name = string.find(rest, '%s*([%w_]+)')
      return name..' = IDL.alias{ '..kind..' },\n'	
    end)
	

    text = gsub(text, 'interface%s+([%w_]+)%s*(%b{})%s*;', function (interface_name, text)
--print("!i", interface_name)
      
      modules[module_name][interface_name] = {}
      text = gsub(text, 'readonly%s+attribute%s+([%w_.:]+)%s*([%w_]+)%s*;', function (kind, attr_name)
        return ""
      end)

      text = gsub(text, 'attribute%s+([%w_.:]+)%s*([%w_]+)%s*;', function (kind, attr_name)
        return ""
      end)
      text = gsub(text, '([%w_.:]+)%s+([%w_]+)%s*(%b())%s*;', function (ret_type, function_name, params)
        params = string.sub( params, 2, -2 )
--print("!f", ret_type, function_name, params)
        params = gsub(params, "%s*([%w_.:]+)%s*([%w.:_]+)%s*([%w.:_]+)", function(mode, kind, name)
          if name == nil then
            name = kind
            kind = mode
            mode = "IN"
          end
          kind = private.treattype(kind)
          return string.format(' { name="%s", type=%s, mode="%s" }', name, kind, string.upper(mode) )
        end)
        ret_type = private.treattype(ret_type)

        return '\n'..function_name..[[ = IDL.operation {
  result = ]]..ret_type..[[,
  parameters = {
  ]] ..params..[[
  },
},
]]
      end)
      
      return interface_name..' = '..text..',\n'
    end)
    text = gsub(text, '%$MODULE%$', module_name)
    
    return 'IDL.readModule("'..module_name..'", '..text..')'
  end)

  defs = defs..'; return 1'
  --print(defs)
  local f,err = loadstring(defs)
  assert(f,err)
  assert(pcall(f))
end