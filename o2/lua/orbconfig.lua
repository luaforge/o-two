require("util.lua")

ORB_CONFIG = ORB_CONFIG or {}

-- IOR for an external Interface Repository or nil for none
--ORB_CONFIG.EXTERNAL_IR_REF = ORB_CONFIG.EXTERNAL_IR_REF or read_all("../ref/ir.ref")

-- which hostname to listen on
ORB_CONFIG.LISTEN_HOST = ORB_CONFIG.LISTEN_HOST or "localhost"
--ORB_CONFIG.LISTEN_HOST = ORB_CONFIG.LISTEN_HOST or "kobke.tecgraf.puc-rio.br"
