-- [scripts/WitheringBrews/init.lua]
Script.ReloadScript("scripts/WitheringBrews/Core.lua")

-- Subscribe via UIAction (this one fires in your build)
if UIAction and UIAction.RegisterEventSystemListener then
    UIAction.RegisterEventSystemListener(WitheringBrews, "System", "OnGameplayStarted", "OnGameplayStarted")
else
    System.LogAlways("[WitheringBrews/init] UIAction missing; OnGameplayStarted may not fire")
end

-- Kick off the short startup handshake to catch KCDUtils when it appears
WitheringBrews.Handshake(50, 100) -- ~5s total, stops after success
