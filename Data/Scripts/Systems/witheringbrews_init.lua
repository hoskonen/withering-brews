-- [scripts/WitheringBrews/init.lua]
WitheringBrews = WitheringBrews or {}

Script.ReloadScript("scripts/WitheringBrews/Config.lua")
Script.ReloadScript("scripts/WitheringBrews/Core.lua")
Script.ReloadScript("scripts/WitheringBrews/Events.lua")
Script.ReloadScript("scripts/WitheringBrews/Cohorts.lua")

-- Bind lifecycle + ItemTransfer only
WitheringBrews.Events.BindAll()

-- CCommands for quick diagnostics
System.AddCCommand("wb_ping", "WitheringBrews_Cmd_Ping()", "WB: ping")
System.AddCCommand("wb_db_test", "WitheringBrews_Cmd_DbTest()", "WB: DB smoke test")

-- Attach KCDUtils (logger + LuaDB)
WitheringBrews.Handshake(50, 100)
