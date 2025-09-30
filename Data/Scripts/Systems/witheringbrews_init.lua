-- [scripts/WitheringBrews/init.lua]
WitheringBrews = WitheringBrews or {}

Script.ReloadScript("scripts/WitheringBrews/Config.lua")
Script.ReloadScript("scripts/WitheringBrews/Debug.lua")
Script.ReloadScript("scripts/WitheringBrews/Util.lua")
Script.ReloadScript("scripts/WitheringBrews/Core.lua")
Script.ReloadScript("scripts/WitheringBrews/Events.lua")
Script.ReloadScript("scripts/WitheringBrews/Cohorts.lua")

-- Bind lifecycle + ItemTransfer only
WitheringBrews.Events.BindAll()

-- CCommands for quick diagnostics
System.AddCCommand("wb_ping", "WitheringBrews_Cmd_Ping()", "WB: ping")
System.AddCCommand("wb_db_test", "WitheringBrews_Cmd_DbTest()", "WB: DB smoke test")
-- Bootstrap commands (preview/apply/reset)
System.AddCCommand("wb_bootstrap_preview", "WitheringBrews_Cmd_BootstrapPreview()", "WB: preview bootstrap (log-only)")
System.AddCCommand("wb_bootstrap_apply", "WitheringBrews_Cmd_BootstrapApply()", "WB: apply bootstrap (write cohorts)")
System.AddCCommand("wb_bootstrap_reset", "WitheringBrews_Cmd_BootstrapReset()", "WB: clear bootstrap flag")

-- Attach KCDUtils (logger + LuaDB)
WitheringBrews.Handshake(50, 100)
