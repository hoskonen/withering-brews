-- [scripts/WitheringBrews/Events.lua]
Script.ReloadScript("scripts/WitheringBrews/Core.lua")
WitheringBrews.Events = WitheringBrews.Events or {}
local EV, WB = WitheringBrews.Events, WitheringBrews
local function log(s) System.LogAlways("[WitheringBrews/Events] " .. s) end

local function bind(movie, elementId, eventName, fnName)
    if not (UIAction and UIAction.RegisterElementListener) then
        log(("RegisterElementListener missing (wanted %s:%s → %s)"):format(movie, eventName, fnName))
        return false
    end
    local ok, err = pcall(UIAction.RegisterElementListener, WB, movie, elementId, eventName, fnName)
    if ok then
        log(("ElementListener bound: %s (elem=%s).%s → %s"):format(movie, tostring(elementId), eventName, fnName))
    else
        log(("ElementListener FAILED: %s (elem=%s).%s → %s :: %s"):format(movie, tostring(elementId), eventName, fnName,
            tostring(err)))
    end
    return ok
end

function EV.BindAll()
    -- Lifecycle (OnGameplayStarted) — keep MercyStrike-style system listener
    if UIAction and UIAction.RegisterEventSystemListener then
        UIAction.RegisterEventSystemListener(WB, "System", "OnGameplayStarted", "OnGameplayStarted")
        log("System listener bound: OnGameplayStarted")
    else
        log("System listener NOT bound: RegisterEventSystemListener missing")
    end

    -- === Primary: Loot/transfer movie ===
    -- Try the usual suspect first…
    local bound_any_item = false
    bound_any_item = bind("ItemTransfer", -1, "OnOpened", "OnItemTransferOpened") or bound_any_item
    bound_any_item = bind("ItemTransfer", -1, "OnClosed", "OnItemTransferClosed") or bound_any_item
    -- …and also try the inventory list movie name as a fallback (some builds route transfer there)
    bound_any_item = bind("ApseInventoryList", -1, "OnOpened", "OnItemTransferOpened") or bound_any_item
    bound_any_item = bind("ApseInventoryList", -1, "OnClosed", "OnItemTransferClosed") or bound_any_item
    if not bound_any_item then
        log("ItemTransfer NOT bound (try different movie or confirm XML).")
    end

    -- === Inventory FS-like element events (observability only) ===
    local inv = "ApseInventoryList"
    local bound_inv = false
    bound_inv = bind(inv, -1, "OnGeneralEvent", "OnInventory_General") or bound_inv
    bound_inv = bind(inv, -1, "OnStartDrag", "OnInventory_StartDrag") or bound_inv
    bound_inv = bind(inv, -1, "OnDropActiveAreaChanged", "OnInventory_DropArea") or bound_inv
    bound_inv = bind(inv, -1, "OnFocusTab", "OnInventory_FocusTab") or bound_inv
    bound_inv = bind(inv, -1, "OnDoubleClicked", "OnInventory_DoubleClicked") or bound_inv
    if not bound_inv then
        log("Inventory element probes NOT bound (movie name mismatch?).")
    end
end
