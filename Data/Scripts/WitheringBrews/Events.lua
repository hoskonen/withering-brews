-- [scripts/WitheringBrews/Events.lua]
Script.ReloadScript("scripts/WitheringBrews/Core.lua")

WitheringBrews.Events = WitheringBrews.Events or {}
local EV, WB = WitheringBrews.Events, WitheringBrews
local function log(s) System.LogAlways("[WitheringBrews/Events] " .. s) end

-- Small helper to bind a movie event using ElementListener at root (-1)
local function bind_el(movie, eventName, fnName)
    if not (UIAction and UIAction.RegisterElementListener) then
        log(("RegisterElementListener missing (wanted %s.%s → %s)"):format(movie, eventName, fnName)); return false
    end
    local ok, err = pcall(UIAction.RegisterElementListener, WB, movie, -1, eventName, fnName)
    if ok then
        log(("ElementListener bound: %s.%s → %s"):format(movie, eventName, fnName))
    else
        log(("ElementListener FAILED: %s.%s → %s :: %s"):format(movie, eventName, fnName, tostring(err)))
    end
    return ok
end

function EV.BindAll()
    -- Lifecycle
    if UIAction and UIAction.RegisterEventSystemListener then
        UIAction.RegisterEventSystemListener(WB, "System", "OnGameplayStarted", "OnGameplayStarted")
        log("System listener bound: OnGameplayStarted")
    else
        log("System listener NOT bound: RegisterEventSystemListener missing")
    end

    -- ItemTransfer (loot UI) — primary anchor
    bind_el("ItemTransfer", "OnOpened", "OnItemTransferOpened")
    bind_el("ItemTransfer", "OnClosed", "OnItemTransferClosed")
end
