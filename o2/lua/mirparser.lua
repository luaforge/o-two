-----------
-- $Id: mirparser.lua,v 1.1 2004-07-21 03:16:00 rmello Exp $
--   Pedro Miller Rabinovitch, DI, PUC-Rio
--
--   Processamento básico das estruturas que definem os tipos de interfaces.
--
--   Expõe:
--
--     IDLImport
--
--       .process( repositório, especificação )
--
--          Recebe um contâiner de interfaces e uma especificação de
--          conteúdo e constrói o mesmo no primeiro.
--
--       .mk
--
--          Tabela de construtores auxiliares para as especificações.
--
-----------

LUA_PATH="?;?.lua;../lua/?"
require'util.lua'
require'mir.lua'

IDLImport = {}

function IDL.interface (t)  return t end

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

      text = gsub(text, 'typedef%s+([^;]+);',
      function (defline)
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

        return function_name..[[ = IDL.operation {
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

local CORBA = 'IDL:omg.org/CORBA/'

local _tmp_ExceptionDefSeq = IDL.sequence{ IDL.Object('') }

local mk = {}
for i, v in { 'module', 'interface', 'attribute', 'operation' } do
   local v = v
   mk[v] = function( t ) 
      t._tp = v 
      return t 
   end
end
IDLImport.mk = mk

BASE_IR_SPECS = { 
   mk.module {      
      name = 'omg.org',
      contents = { 
         mk.module {
            name = 'CORBA',
            contents = {
               mk.interface { 
                  name = 'IRObject', 
                  contents = {
                     mk.attribute{ name = 'def_kind', type=IR.DefinitionKind, },
                  },
               },
               mk.interface { 
                  name = 'IDLType', 
                  base = { CORBA..'IRObject:1.0' },
                  contents = {
                     mk.attribute{ name = 'type', type = 'TypeCode', },
                  },
               },
               mk.interface { 
                  name = 'Contained', 
                  base = { CORBA..'IRObject:1.0' },
                  contents = {
                     mk.attribute{ name = 'name', type = 'string', },
                     mk.attribute{ name = 'version', type = 'string', },
                     mk.attribute{ name = 'id', type = 'string', },
                     mk.attribute{ name = 'defined_in', type = CORBA..'Contained', },
                     mk.attribute{ name = 'absolute_name', type = 'string', },
                     mk.attribute{ name = 'containing_repository', type = CORBA..'Repository', },
                     mk.operation{
                        name = 'describe',
                        result = IDL.struct{ 
                           { name='kind', type=IR.DefinitionKind },
                           { name='value', type=IDL.any },
                        },
                        parameters = {}
                     },
                  }
                  -- ...         
               },
               mk.interface { 
                  name = 'Container', 
                  base = { CORBA..'IRObject:1.0' },
                  contents = { 
                     mk.operation{
                        name = 'lookup',
                        result = CORBA..'Contained',
                        parameters = {
                           { name = 'search_id', type = 'string', }            
                        }
                     },
                     mk.operation{
                        name = 'contents',
                        result = IDL.sequence{ MIR.IDLType:_new( CORBA..'Contained:1.0' )},
                        parameters = {
				{name='limit_type', type=IR.DefinitionKind, },
				{name = "exclude_inherited", type = IDL.boolean, }
			},
                     },
                     mk.operation{
                        name = 'lookup_name',
                        result = IDL.sequence{ MIR.IDLType:_new( CORBA..'Contained:1.0' )},
                        parameters = {
                           { name = 'search_name', type = IR.Identifier, },
                           { name = 'levels_to_search', type = 'long', },
                           { name = 'limit_type', type = IR.DefinitionKind, },         
                           { name = 'exclude_inherited', type = 'boolean', },
                        }
                     },
                     mk.operation{
                        name = 'create_module',
                        result = CORBA..'ModuleDef',
                        parameters = {
                           { name = 'id', type = 'string', },
                           { name = 'name', type = 'string', },
                           { name = 'version', type = 'string', },         
                        }
                     },
                     mk.operation{
                        name = 'create_interface',
                        result = CORBA..'InterfaceDef',
                        parameters = {
                           { name = 'id', type = 'string', },
                           { name = 'name', type = 'string', },
                           { name = 'version', type = 'string', },         
                           { name = 'base_interfaces', type = IDL.sequence{ MIR.IDLType:_new( CORBA..'InterfaceDef:1.0' ) }, },         
                        }
                     },
                  },
                  -- ...         
               },
               mk.interface { 
                  name = 'Repository', 
                  base = { CORBA..'Container:1.0' },
                  contents = { 
                        mk.attribute{ name = 'id', type = 'string', },
                  	mk.operation {
				name = 'lookup_id',
				result = CORBA..'InterfaceDef',
				parameters = {
					{ name='search_id', type='string' }
				},
			},
		  },
	       },
               mk.interface { 
                  name = 'ModuleDef', 
                  base = { CORBA..'Container:1.0', CORBA..'Contained:1.0' },
                  contents = { 
		  },
	       },
               mk.interface { 
                  name = 'AttributeDef', 
                  base = { CORBA..'Contained:1.0' },
                  contents = { 
                        mk.attribute{ name = 'type', type = 'TypeCode', },
                        mk.attribute{ name = 'type_def', type = CORBA..'IDLType', },
                        mk.attribute{ name = 'mode', type = IR.AttributeMode, },
		  },
	       },
               mk.interface { 
                  name = 'OperationDef', 
                  base = { CORBA..'Contained:1.0' },
                  contents = { 
                        mk.attribute{ name = 'result_def', type = CORBA..'IDLType', },
                        mk.attribute{ name = 'result', type = 'TypeCode', },
                        mk.attribute{ name = 'mode', type = IR.OperationMode, },
                        mk.attribute{ name = 'params', type = IR.ParDescriptionSeq, },
                        mk.attribute{ name = 'contexts', type = IR.ContextIdSeq, },
                        mk.attribute{ name = 'exceptions', type = _tmp_ExceptionDefSeq, },
		  },
	       },
               mk.interface { 
                  name = 'InterfaceDef', 
                  base = { CORBA..'Container:1.0', CORBA..'Contained:1.0' },
                  contents = { 
		     mk.operation{
                        name = 'create_attribute',
                        result = CORBA..'AttributeDef',
                        parameters = {
                           { name = 'id', type = 'string', },
                           { name = 'name', type = 'string', },
                           { name = 'version', type = 'string', },         
                           { name = 'type', type = 'TypeCode', },
                           { name = 'mode', type = IR.AttributeMode, },
		        },
	             },
		     mk.operation{
                        name = 'create_operation',
                        result = CORBA..'OperationDef',
                        parameters = {
                           { name = 'id', type = 'string', },
                           { name = 'name', type = 'string', },
                           { name = 'version', type = 'string', },         
                           { name = 'result', type = 'TypeCode', },
                           { name = 'mode', type = IR.OperationMode, },
                           { name = 'params', type = IR.ParDescriptionSeq, },
                           { name = 'contexts', type = IR.ContextIdSeq, },
                           { name = 'exceptions', type = _tmp_ExceptionDefSeq, },
		        },
	             }
		  },
	       },
            }
         }
      }
   }
}

function gen_type_def( tp )
   assert( tp )
   return MIR.IDLType:_new( tp )
end

function check_types( type_name, ... )
   for i, v in ipairs( arg ) do
      assert( type(v) == type_name )
   end
end

function gen_id( name, version, scope )
   scope = scope or ''
   scope = string.gsub( scope, '^::', '' )
   scope = string.gsub( scope, '::', '/' )
   if scope ~= '' then scope = scope .. '/' end
   version = version or '1.0'
   return string.format( 'IDL:%s%s:%s', 
      scope, name, version )
end

function proc_type( tp )
   local t = type(tp)
   if t == 'string' then
      if IDL[tp] then
         return IDL[tp]
      else
         if not string.find( ':%d+.%d+$', tp ) then
            tp = tp .. ':1.0'
         end
verb( 4, 'creating Object for type ', tp )	 
         local o =  IDL.Object( tp )
	 o.repID = tp
	 return o
      end
   elseif t == 'table' then
      return tp
   else
      error( 'invalid type:', t )
   end
end

local proc = {
   module = function( spec, parent )
      check_types( 'table', spec )
      spec.version = spec.version or '1.0'
      check_types( 'string', spec.name, spec.version )      
      spec.id = spec.id or gen_id( spec.name, spec.version, parent.absolute_name )
      local r, m = pcall( parent.create_module, parent, 
         spec.id, spec.name, spec.version )
      assert( r, m )
      read_specs( spec.contents, m  )      
   end,
   interface = function( spec, parent )
      check_types( 'table', spec )
      spec.version = spec.version or '1.0'
      check_types( 'string', spec.name, spec.version )      
      spec.base = spec.base or {}
      check_types( 'table', spec.base )
      for i, v in ipairs( spec.base ) do
      	spec.base[i] = parent.containing_repository:lookup_id( v )
	assert( spec.base[i], v )
      end 
      spec.id = spec.id or gen_id( spec.name, spec.version, parent.absolute_name )
      local r, m = pcall( parent.create_interface, parent, 
         spec.id, spec.name, spec.version, spec.base )
      assert( r, m )
      read_specs( spec.contents, m  )      
   end,
   attribute = function( spec, parent )
      check_types( 'table', spec )
      spec.version = spec.version or '1.0'
      spec.mode = spec.mode or 'ATTR_NORMAL'      
      check_types( 'string', spec.name, spec.version, spec.mode )      
      spec.type = proc_type( spec.type )
      check_types( 'table', spec.type )
      spec.id = spec.id or gen_id( spec.name, spec.version, parent.absolute_name )
	 verb( 9, spec.name, spec.type )
      spec.type_def = spec.type_def or gen_type_def( spec.type )
      local r, m = pcall( parent.create_attribute, parent, 
         spec.id, spec.name, spec.version, spec.type, spec.mode, type_def )
      assert( r, m )
   end,
   operation = function( spec, parent )
      check_types( 'table', spec )
      spec.version = spec.version or '1.0'
      spec.mode = spec.mode or 'OP_NORMAL'      
      spec.result = spec.result or IDL.void
      spec.result = proc_type( spec.result )
      spec.parameters = spec.parameters or {}
      check_types( 'string', spec.name, spec.version, spec.mode )
      check_types( 'table', spec.result, spec.parameters )
      spec.id = spec.id or gen_id( spec.name, spec.version, parent.absolute_name )
      for i, param in ipairs( spec.parameters ) do
         check_types( 'table', param )
         param.mode = param.mode or 'PARAM_IN'
         check_types( 'string', param.name, param.mode )
         param.type = proc_type( param.type )
         check_types( 'table', param.type )
	 verb( 9, param.name )
         param.type_def = param.type_def or gen_type_def( param.type )
         check_types( 'table', param.type_def )
      end
      local r, m = pcall( parent.create_operation, parent, 
         spec.id, spec.name, spec.version, spec.result, spec.mode, spec.parameters, {}, {} )
      assert( r, m )
   end,
}

function read_specs( specs, parent )
   if specs == nil then return end
   for i, v in ipairs( specs ) do
verb( 8, 'processing ', i, v, v._tp )   
      check_types( 'string', v._tp )
      proc[v._tp]( v, parent )
   end   
end

function IDLImport.process( repository, specs )
   read_specs( specs, repository )
   --pr( specs, '', 7 )
end

