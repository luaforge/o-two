-- *********************************************************************************
-- * Copyright 2002 Noemi Rodriquez & Roberto Ierusalimschy.  All rights reserved. *
-- *********************************************************************************
require("idl.lua")

---------------------------
---------------------------

---------------------------
---------------------------
IR = {}

IR.Identifier = IDL.alias{IDL.string}
IR.ScopedName = IDL.alias{IDL.string}
IR.RepositoryId = IDL.alias{IDL.string}
IR.VersionSpec = IDL.alias{IDL.string}
IR.ContextIdentifier = IDL.alias{IDL.string}

IR.OperationMode = IDL.enum{"OP_NORMAL", "OP_ONEWAY"}
IR.ContextIdSeq = IDL.sequence{IR.ContextIdentifier}

IR.RepositoryIdSeq = IDL.sequence{IR.RepositoryId}

IR.DefinitionKind = IDL.enum{
                      "dk_none", "dk_all",
                      "dk_Attribute", "dk_Constant", "dk_Exception", "dk_Interface",
                      "dk_Module", "dk_Operation", "dk_Typedef",
                      "dk_Alias", "dk_Struct", "dk_Union", "dk_Enum",
                      "dk_Primitive", "dk_String", "dk_Sequence", "dk_Array",
                    }

-- parametros

IR.ParameterMode = IDL.enum{"PARAM_IN", "PARAM_OUT", "PARAM_INOUT"}

IR.ParameterDescription = IDL.struct{
  {name="name", type=IR.Identifier},
  {name="type", type=IDL.TypeCode},
  --{name="type_def", type=IDL.Object()}, -- seria IDLType, nao defini
  {name="type_def", type=IDL.Object('')}, -- seria IDLType, nao defini
  {name="mode", type=IR.ParameterMode}
}
  
IR.ParDescriptionSeq = IDL.sequence{IR.ParameterDescription}
IR.Contained = IDL.Object('IDL:omg.org/CORBA/Contained:1.0')
IR.ContainedSeq = IDL.alias( IDL.sequence{IR.Contained} )

-- excecoes

IR.ExceptionDescription = IDL.struct{
  {name="name", type=IR.Identifier},
  {name="id", type=IR.RepositoryId},
  {name="defined_in", type=IR.RepositoryId},
  {name="version", type=IR.VersionSpec},
  {name="type", type=IDL.TypeCode}
}

IR.ExcDescriptionSeq = IDL.sequence{IR.ExceptionDescription}

-- operacoes

IR.OperationDescription = IDL.struct{
  {name="name", type=IR.Identifier},
  {name="id", type=IR.RepositoryId},
  {name="defined_in", type=IR.RepositoryId},
  {name="version", type=IR.VersionSpec},
  {name="result", type=IDL.TypeCode},
  {name="mode", type=IR.OperationMode},
  {name="contexts", type=IR.ContextIdSeq},
  {name="parameters", type=IR.ParDescriptionSeq},
  {name="exceptions", type=IR.ExcDescriptionSeq}
}

IR.OpDescriptionSeq = IDL.sequence{IR.OperationDescription}

-- atributos

IR.AttributeMode = IDL.enum{"ATTR_NORMAL", "ATTR_READONLY"}

IR.ModuleDescription = IDL.struct{
  {name="name", type=IDL.string},
  {name="id", type=IDL.string},
  {name="defined_in", type=IDL.string},
  {name="version", type=IDL.string},
  --{name="name", type=IR.Identifier},
  --{name="id", type=IR.RepositoryId},
  --{name="defined_in", type=IR.RepositoryId},
  --{name="version", type=IR.VersionSpec},
}

IR.AttributeDescription = IDL.struct{
  {name="name", type=IR.Identifier},
  {name="id", type=IR.RepositoryId},
  {name="defined_in", type=IR.RepositoryId},
  {name="version", type=IR.VersionSpec},
  {name="type", type=IDL.TypeCode},
  {name="mode", type=IR.AttributeMode}
}

IR.AttrDescriptionSeq = IDL.sequence{IR.AttributeDescription}

--

IR.InterfaceDef = IDL.Object( 'IDL:omg.org/CORBA/InterfaceDef:1.0' )

IR.InterfaceDefSeq = IDL.sequence{IR.InterfaceDef}

IR.FullInterfaceDescription = IDL.struct{
  {name="name", type=IR.Identifier},
  {name="id", type=IR.RepositoryId},
  {name="defined_in", type=IR.RepositoryId},
  {name="version", type=IR.VersionSpec},
  {name="operations", type=IR.OpDescriptionSeq},
  {name="attributes", type=IR.AttrDescriptionSeq},
  {name="base_interfaces", type=IR.RepositoryIdSeq},
  {name="type", type=IDL.TypeCode}
}
IR.InterfaceDescription = IDL.struct{
  {name="name", type=IR.Identifier},
  {name="id", type=IR.RepositoryId},
  {name="defined_in", type=IR.RepositoryId},
  {name="version", type=IR.VersionSpec},
  {name="base_interfaces", type=IR.RepositoryIdSeq},
  {name="type", type=IDL.TypeCode}
}


