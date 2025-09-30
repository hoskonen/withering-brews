-- [scripts/WitheringBrews/init.lua]
WitheringBrews = WitheringBrews or {}

Script.ReloadScript("scripts/WitheringBrews/Config.lua")
Script.ReloadScript("scripts/WitheringBrews/Debug.lua")
Script.ReloadScript("scripts/WitheringBrews/Util.lua")
Script.ReloadScript("scripts/WitheringBrews/Core.lua")
Script.ReloadScript("scripts/WitheringBrews/Events.lua")
Script.ReloadScript("scripts/WitheringBrews/Cohorts.lua")

WitheringBrews.Events.BindAll()

System.AddCCommand("wb_ping", "WitheringBrews_Cmd_Ping()", "WB: ping")
System.AddCCommand("wb_db_test", "WitheringBrews_Cmd_DbTest()", "WB: DB smoke test")
System.AddCCommand("wb_db_put", "WitheringBrews_Cmd_DbPut(%1,%2)", "WB: DB put key value")
System.AddCCommand("wb_db_get", "WitheringBrews_Cmd_DbGet(%1)", "WB: DB get key")
System.AddCCommand("wb_util_who", "WitheringBrews_Cmd_UtilWho()", "WB Util: print player entity")
System.AddCCommand("wb_util_snap", "WitheringBrews_Cmd_UtilSnap()", "WB Util: snapshot player inventory (stub)")
System.AddCCommand("wb_bootstrap_preview", "WitheringBrews_Cmd_BootstrapPreview()", "WB: preview bootstrap")
System.AddCCommand("wb_bootstrap_apply", "WitheringBrews_Cmd_BootstrapApply()", "WB: apply bootstrap")
System.AddCCommand("wb_bootstrap_reset", "WitheringBrews_Cmd_BootstrapReset()", "WB: clear bootstrap flag")

WitheringBrews.Handshake(50, 100)
