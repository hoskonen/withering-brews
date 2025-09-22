-- [scripts/WitheringBrews/init.lua]
Script.ReloadScript("scripts/WitheringBrews/Core.lua")

if UIAction and UIAction.RegisterEventSystemListener then
    UIAction.RegisterEventSystemListener(WitheringBrews, "System", "OnGameplayStarted", "OnGameplayStarted")
else
    System.LogAlways("[WitheringBrews/init] UIAction missing; OnGameplayStarted won't fire")
end
