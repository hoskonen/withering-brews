-- [scripts/WitheringBrews/Util.lua]
WitheringBrews = WitheringBrews or {}
WitheringBrews.Util = WitheringBrews.Util or {}

local WB, U, D = WitheringBrews, WitheringBrews.Util, WitheringBrews.Debug

-- Return the current player entity if available
function U.Player()
    local p = rawget(_G, "player")
    if p then return p end
    -- Fallbacks (kept safe)
    if System and System.GetEntityByName then
        local e = System.GetEntityByName("player")
        if e then return e end
    end
    return nil
end

-- Minimal reverse index access (lazy-build if needed)
local function resolvePotion(tplId)
    if not WB._PotionIndex and WB.BuildPotionIndex then WB.BuildPotionIndex() end
    return WB._PotionIndex and WB._PotionIndex[tplId] or nil
end

-- Very conservative placeholder: we don’t know the engine API yet.
-- Returns a map { tplId -> qty } for the given entity. For now, log-only + empty.
function U.InventorySnapshot(entity)
    entity = entity or U.Player()
    if not entity then
        if D then D.warn("InventorySnapshot: no entity") end
        return {}
    end
    if D then D.printf("InventorySnapshot(%s) → [stub returns empty]", tostring(entity and entity.id or "nil")) end
    -- TODO: replace this stub with real enumeration when we wire your inventory helpers
    return {}
end

-- Helper: is a template ID a known potion (based on Config.PotionFamilies)?
function U.IsKnownPotionTpl(tplId)
    return resolvePotion(tplId) ~= nil
end

-- Dev CCommands (optional)
function WitheringBrews_Cmd_UtilWho()
    local p = U.Player()
    System.LogAlways("[WitheringBrews] UtilWho: player=" .. tostring(p and p.id or "nil"))
end

function WitheringBrews_Cmd_UtilSnap()
    local m = U.InventorySnapshot()
    local n = 0; for _, qty in pairs(m) do n = n + (tonumber(qty) or 0) end
    System.LogAlways("[WitheringBrews] UtilSnap: unique=" .. tostring(next(m) and "some" or "none") .. ", totalQty=" .. n)
end
