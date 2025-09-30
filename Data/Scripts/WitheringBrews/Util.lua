-- [scripts/WitheringBrews/Util.lua]
WitheringBrews       = WitheringBrews or {}
WitheringBrews.Util  = WitheringBrews.Util or {}
WitheringBrews.Debug = WitheringBrews.Debug or {}

local WB, U, D       = WitheringBrews, WitheringBrews.Util, WitheringBrews.Debug

local function info(s) if D and D.info then D.info(s) else System.LogAlways("[WitheringBrews] " .. s) end end
local function warn(s) if D and D.warn then D.warn(s) else System.LogAlways("[WitheringBrews][WARN] " .. s) end end

-- helpers: qty from one item (explicit, no guessing)
local function _to_int(v)
    local n = tonumber(v); if not n or n <= 0 then return 1 end
    return math.floor(n + 0.00001)
end

local function _qty_from_item(itm)
    local B      = WitheringBrews.Config and WitheringBrews.Config.Behavior or {}
    local getter = B.qty_getter
    local field  = B.qty_field

    -- prefer method
    if getter and type(itm[getter]) == "function" then
        local ok, n = pcall(itm[getter], itm)
        if ok then return _to_int(n) end
    end
    -- fallback field
    if field and itm[field] ~= nil then
        return _to_int(itm[field])
    end
    return 1
end

-- ---------- basics ----------
function U.Player()
    local p = rawget(_G, "player")
    if p then return p end
    if System and System.GetEntityByName then
        local e = System.GetEntityByName("player")
        if e then return e end
    end
    return nil
end

-- ---------- inventory snapshot (SR technique, no dependency) ----------
-- Returns { classId -> qty } for given entity/inventory
-- main: { classId -> qty }
function WitheringBrews.Util.InventorySnapshot(entity)
    local U, D = WitheringBrews.Util, WitheringBrews.Debug
    entity = entity or U.Player()
    if not entity then
        if D then D.warn("InventorySnapshot: no entity") end
        return {}
    end

    local inv = entity.inventory or (entity.GetInventory and select(2, pcall(entity.GetInventory, entity)))
    if not inv then
        if D then D.warn("InventorySnapshot: no inventory handle") end
        return {}
    end
    if type(inv.GetInventoryTable) ~= "function" then
        if D then D.warn("InventorySnapshot: inventory has no GetInventoryTable()") end
        return {}
    end

    -- WUID list
    local okTbl, tbl = pcall(inv.GetInventoryTable, inv)
    if not okTbl or type(tbl) ~= "table" then
        if D then D.warn("InventorySnapshot: table fetch failed") end
        return {}
    end

    local out, uniqueClasses = {}, {}
    local entries, resolved = 0, 0

    for _, wuid in pairs(tbl) do
        entries = entries + 1
        local okItem, item = false, nil
        if ItemManager and ItemManager.GetItem then
            okItem, item = pcall(ItemManager.GetItem, wuid)
        end
        if okItem and item then
            resolved = resolved + 1
            local cid = item.classId or item.class or item.class_id or item.type or item.kind
            if cid then uniqueClasses[cid] = true end
        end
    end

    if type(inv.GetCountOfClass) == "function" then
        for cid in pairs(uniqueClasses) do
            local okC, n = pcall(inv.GetCountOfClass, inv, cid)
            if okC and type(n) == "number" and n > 0 then
                out[cid] = math.floor(n + 0.00001)
            end
        end
    else
        -- fallback: just mark presence (no quantities, all = 1)
        for cid in pairs(uniqueClasses) do
            out[cid] = (out[cid] or 0) + 1
        end
    end

    if D and D.info then
        local uniq, total = 0, 0
        for _, q in pairs(out) do
            uniq = uniq + 1; total = total + q
        end
        D.info(("InventorySnapshot: entries=%d resolved=%d kinds=%d total=%d"):format(entries, resolved, uniq, total))
    end

    return out
end

-- ---------- dev CCommands ----------
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

function WitheringBrews_Cmd_UtilProbeInv()
    local p = U.Player()
    if not p then
        System.LogAlways("[WitheringBrews] ProbeInv: no player"); return
    end
    local inv = p.inventory
    if not inv then
        System.LogAlways("[WitheringBrews] ProbeInv: player has no .inventory"); return
    end
    local keys = {}
    for k, _ in pairs(inv) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    System.LogAlways("[WitheringBrews] ProbeInv keys: " .. table.concat(keys, ", "))
    local has = function(n) return type(inv[n]) == "function" end
    System.LogAlways(("[WitheringBrews] ProbeInv methods: GetInventoryTable=%s, GetCountOfClass=%s, FindItem=%s, DeleteItemOfClass=%s")
        :format(tostring(has("GetInventoryTable")), tostring(has("GetCountOfClass")), tostring(has("FindItem")),
            tostring(has("DeleteItemOfClass"))))
end
