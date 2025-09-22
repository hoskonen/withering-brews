-- [scripts/WitheringBrews/witheringbrews_init.lua]
Script.ReloadScript("scripts/WitheringBrews/Core.lua")

-- Always bind raw System listeners (UIAction path is universal)
if UIAction and UIAction.RegisterEventSystemListener then
    UIAction.RegisterEventSystemListener(WitheringBrews, "System", "OnGameplayStarted", "OnGameplayStarted")
    UIAction.RegisterEventSystemListener(WitheringBrews, "System", "OnHide", "OnHide")
    UIAction.RegisterEventSystemListener(WitheringBrews, "System", "OnShow", "OnShow")
    System.LogAlways("[WitheringBrews/init] UIAction system listeners bound")
end

-- (Optional) KCDUtils helpers if present (pure bonus)
if KCDUtils and KCDUtils.Events then
    KCDUtils.Events.RegisterOnGameplayStarted(WitheringBrews)
    KCDUtils.Events.SubscribeSystemEvent(WitheringBrews, "OnHide")
    KCDUtils.Events.SubscribeSystemEvent(WitheringBrews, "OnShow")
    System.LogAlways("[WitheringBrews/init] KCDUtils event helpers bound")
end

-- Also bind ItemTransfer + Inventory now so we see the signals later
if UIAction then
    if UIAction.RegisterEventMovieListener then
        UIAction.RegisterEventMovieListener(WitheringBrews, "ItemTransfer", "OnOpened", "OnItemTransferOpened")
        UIAction.RegisterEventMovieListener(WitheringBrews, "ItemTransfer", "OnClosed", "OnItemTransferClosed")
    end
    if UIAction.RegisterFSCommandListener then
        UIAction.RegisterFSCommandListener(WitheringBrews, "ItemTransfer", "onOpened", "OnItemTransferOpened")
        UIAction.RegisterFSCommandListener(WitheringBrews, "ItemTransfer", "onClosed", "OnItemTransferClosed")
    end
    UIAction.RegisterEventSystemListener(WitheringBrews, "Inventory", "OnOpened", "OnInventoryOpened")
    UIAction.RegisterEventSystemListener(WitheringBrews, "Inventory", "OnClosed", "OnInventoryClosed")
    System.LogAlways("[WitheringBrews/init] ItemTransfer + Inventory listeners bound")
end

-- Handshake still attaches logger/DB later when KCDUtils loads
WitheringBrews.Handshake(50, 100)
