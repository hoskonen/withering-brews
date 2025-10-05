-- [scripts/WitheringBrews/Util.lua]
WitheringBrews       = WitheringBrews or {}
WitheringBrews.Util  = WitheringBrews.Util or {}
WitheringBrews.Debug = WitheringBrews.Debug or {}

local WB, U, D       = WitheringBrews, WitheringBrews.Util, WitheringBrews.Debug
local function info(s) if D and D.info then D.info(s) else System.LogAlways("[WitheringBrews] " .. s) end end
local function warn(s) if D and D.warn then D.warn(s) else System.LogAlways("[WitheringBrews][WARN] " .. s) end end

-- --- Player ---------------------------------------------------------------
function U.Player()
    local p = rawget(_G, "player")
    if p then return p end
    if System and System.GetEntityByName then
        local e = System.GetEntityByName("player")
        if e then return e end
    end
    return nil
end

-- --- Potion check (uses reverse index built in Core) -----------------------
function U.IsPotionId(classId)
    local idx = WB._PotionIndex
    return type(classId) == "string" and idx and idx[classId] ~= nil
end

-- --- Inventory snapshot: { classId -> qty } -------------------------------
function U.InventorySnapshot(entity)
    entity = entity or U.Player()
    if not entity then
        warn("InventorySnapshot: no entity"); return {}
    end

    local inv = entity.inventory or (entity.GetInventory and select(2, pcall(entity.GetInventory, entity)))
    if not inv then
        warn("InventorySnapshot: no inventory handle"); return {}
    end
    if type(inv.GetInventoryTable) ~= "function" then
        warn("InventorySnapshot: GetInventoryTable missing"); return {}
    end

    local okTbl, tbl = pcall(inv.GetInventoryTable, inv)
    if not okTbl or type(tbl) ~= "table" then
        warn("InventorySnapshot: table fetch failed"); return {}
    end

    local out, uniqueClasses = {}, {}
    local entries, resolved = 0, 0

    -- discover classIds from WUIDs
    for _, wuid in pairs(tbl) do
        entries = entries + 1
        local okItem, item = false, nil
        if ItemManager and ItemManager.GetItem then okItem, item = pcall(ItemManager.GetItem, wuid) end
        if okItem and item then
            resolved = resolved + 1
            local cid = item.classId or item.class or item.class_id or item.type or item.kind
            if cid then uniqueClasses[cid] = true end
        end
    end

    if type(inv.GetCountOfClass) == "function" then
        for cid in pairs(uniqueClasses) do
            local okC, n = pcall(inv.GetCountOfClass, inv, cid)
            if okC and type(n) == "number" and n > 0 then out[cid] = math.floor(n + 0.00001) end
        end
    else
        -- no authoritative counts available: presence-only (rare)
        for cid in pairs(uniqueClasses) do out[cid] = (out[cid] or 0) + 1 end
    end

    local uniq, total = 0, 0
    for _, q in pairs(out) do
        uniq = uniq + 1; total = total + q
    end
    info(("InventorySnapshot: entries=%d resolved=%d kinds=%d total=%d"):format(entries, resolved, uniq, total))
    return out
end

function U.DiffCounts(before, after)
    before, after = before or {}, after or {}
    local added, removed = {}, {}
    for cid, bq in pairs(before) do
        local aq = after[cid] or 0
        local d = aq - (bq or 0)
        if d < 0 then removed[cid] = -d end
    end
    for cid, aq in pairs(after) do
        local bq = before[cid] or 0
        local d = aq - bq
        if d > 0 then added[cid] = d end
    end
    return added, removed
end

-- --- Dev commands ----------------------------------------------------------
function WitheringBrews_Cmd_UtilWho()
    local p = U.Player()
    System.LogAlways("[WitheringBrews] UtilWho: player=" .. tostring(p and p.id or "nil"))
end

function WitheringBrews_Cmd_UtilSnap()
    local m = U.InventorySnapshot()
    local nUnique, nTotal = 0, 0
    for _, q in pairs(m) do
        nUnique = nUnique + 1; nTotal = nTotal + (tonumber(q) or 0)
    end
    System.LogAlways("[WitheringBrews] UtilSnap: unique=" .. nUnique .. ", total=" .. nTotal)
    local printed = 0
    for cid, qty in pairs(m) do
        System.LogAlways(string.format("[WitheringBrews]   %s x%d", tostring(cid), tonumber(qty) or 0))
        printed = printed + 1; if printed >= 10 then break end
    end
end

function WitheringBrews_Cmd_LootDeltaSim()
    local WB, U = WitheringBrews, WitheringBrews.Util
    WB.BuildPotionIndex()
    local p = U.Player()
    local a = U.InventorySnapshot(p)
    -- fake “before” by subtracting a tiny amount from a few keys:
    local before = {}
    local cut = 0
    for cid, qty in pairs(a) do
        before[cid] = math.max(0, qty - 1)
        cut = cut + 1; if cut >= 3 then break end
    end
    local added = U.DiffCounts(before, a)
    System.LogAlways("[WitheringBrews] LootDeltaSim → see OnItemTransferClosed logs in real use")
end
