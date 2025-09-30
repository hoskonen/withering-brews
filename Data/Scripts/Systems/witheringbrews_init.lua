-- [scripts/WitheringBrews/init.lua]
WitheringBrews = WitheringBrews or {}

-- Load modules
Script.ReloadScript("scripts/WitheringBrews/Config.lua")
Script.ReloadScript("scripts/WitheringBrews/Core.lua")
Script.ReloadScript("scripts/WitheringBrews/Events.lua")
Script.ReloadScript("scripts/WitheringBrews/Cohorts.lua")
-- Commands.lua intentionally omitted for now (we’re using CCommands + #)

-- Bind *all* events in one place
WitheringBrews.Events.BindAll()

-- Handy CCommands (single source of truth)
System.AddCCommand("wb_ping", "WitheringBrews_Cmd_Ping()", "WB: ping")
System.AddCCommand("wb_db_test", "WitheringBrews_Cmd_DbTest()", "WB: DB smoke test")
-- [scripts/WitheringBrews/init.lua] (after existing System.AddCCommand lines)
System.AddCCommand("wb_db_put", "WitheringBrews_Cmd_DbPut(%1,%2)", "WB: DB put key value")
System.AddCCommand("wb_db_get", "WitheringBrews_Cmd_DbGet(%1)", "WB: DB get key")
-- Add near your other CCommands:
System.AddCCommand("wb_diag_ui", "WitheringBrews_Cmd_UiDiag()", "WB: print UIAction capabilities")

-- Start the KCDUtils attach (logger + DB when ready)
WitheringBrews.Handshake(50, 100)
