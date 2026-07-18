-- [scripts/WitheringBrews/Dev.lua]
-- Diagnostic and explicit development utilities. None of these run automatically.
WitheringBrews = WitheringBrews or {}
WitheringBrews.Dev = WitheringBrews.Dev or {}

local WB = WitheringBrews
local Dev = WB.Dev
local U = WB.Util

local function log(message)
    System.LogAlways("[WitheringBrews/Dev] " .. tostring(message))
end

local function warn(message)
    System.LogAlways("[WitheringBrews/Dev][WARN] " .. tostring(message))
end

local function err(message)
    System.LogAlways("[WitheringBrews/Dev][ERROR] " .. tostring(message))
end

local function countKeys(value)
    local count = 0
    for _ in pairs(value or {}) do count = count + 1 end
    return count
end

local function boolText(value)
    return value and "yes" or "no"
end

local function safeCall(fn, ...)
    if type(fn) ~= "function" then return false, nil end
    return pcall(fn, ...)
end

local function getInventory(playerEntity)
    if not playerEntity then return nil end
    if playerEntity.inventory then return playerEntity.inventory end
    if type(playerEntity.GetInventory) == "function" then
        local ok, inventory = pcall(playerEntity.GetInventory, playerEntity)
        if ok then return inventory end
    end
    return nil
end

local function getDb()
    if WB.DB then return WB.DB end
    if KCDUtils and KCDUtils.DB and type(KCDUtils.DB.Factory) == "function" then
        local ok, db = pcall(KCDUtils.DB.Factory, "witheringbrews")
        if ok then return db end
    end
    return nil
end

local function getInventoryCount(inventory, classId)
    if not inventory or type(inventory.GetCountOfClass) ~= "function" then return nil end
    local ok, count = pcall(inventory.GetCountOfClass, inventory, classId)
    if not ok or type(count) ~= "number" then return nil end
    return math.floor(count + 0.00001)
end

local function normalizeFamily(value)
    if type(value) ~= "string" then return nil end
    return string.lower(value):gsub("%-", "_")
end

local function normalizeTier(value)
    if type(value) == "number" then
        local tier = math.floor(value)
        return tier >= 1 and tier <= 5 and tier or nil
    end

    if type(value) ~= "string" then return nil end
    local text = string.lower(value)
    local labels = { i = 1, ii = 2, iii = 3, iv = 4, v = 5 }
    if labels[text] then return labels[text] end

    local tier = tonumber(text)
    if not tier then return nil end
    tier = math.floor(tier)
    return tier >= 1 and tier <= 5 and tier or nil
end

function Dev.GetWorldTime()
    if WB.Clock and type(WB.Clock.Now) == "function" then
        return WB.Clock.Now()
    end

    return nil, "unavailable"
end

function Dev.FormatWorldTime(value)
    if type(value) ~= "number" then return "unavailable" end
    local total = math.floor(value)
    local days = math.floor(total / 86400)
    local hours = math.floor((total / 3600) % 24)
    local minutes = math.floor((total / 60) % 60)
    local seconds = total % 60
    return string.format("day=%d %02d:%02d:%02d", days, hours, minutes, seconds)
end

function Dev.PrintHelp()
    log("Commands:")
    log("  wb_help                              - show this command list")
    log("  wb_status                            - print lifecycle, API and persistence status")
    log("  wb_validate                          - validate potion data and tracking configuration")
    log("  wb_time                              - compare game-world time and os.time()")
    log("  wb_ui_diag                           - print available UIAction listener APIs")
    log("  wb_spawn <family> [tier] [quantity]  - add a supported potion to player inventory")
    log("  wb_spawn_testset [tier] [quantity]   - add one configured family from each decay band")
    log("  wb_scan_potions                      - scan current inventory for supported potion UUIDs")
    log("  wb_util_snap                         - print an inventory snapshot summary")
    log("  wb_db_test                           - run LuaDB write/read/delete smoke test")
    log("  wb_coh_validate                      - compare player potions with saved cohorts")
    log("  wb_age_selftest                      - run pure aging planner self-tests")
    log("  wb_age_validate_rules                - validate configured aging rules and boundaries")
    log("  wb_age_preview                       - preview current player potion aging and planned transitions")
    log("  wb_age_tx_preview                    - construct full aging transaction shell (read-only)")
    log("  wb_age_inv_roundtrip <id> <qty> TEST - verified inventory mutation round-trip")
    log("Spawn commands mutate inventory only; they do not create or alter cohorts.")
end

function Dev.PrintStatus()
    if type(WB.BuildPotionIndex) == "function" then WB.BuildPotionIndex() end

    local config = WB.Config or {}
    local playerEntity = U and type(U.Player) == "function" and U.Player() or nil
    local inventory = getInventory(playerEntity)
    local db = getDb()
    local bootstrap = config.Bootstrap or {}
    local bootstrapFlag = bootstrap.db_flag or "WB_Config:migrated_v1"
    local migrationValue = nil

    if db and type(db.Get) == "function" then
        local ok, value = pcall(db.Get, db, bootstrapFlag)
        if ok then migrationValue = value end
    end

    local worldTime, worldSource = Dev.GetWorldTime()
    local devConfig = config.Dev or {}

    log(string.format("Status v%s", tostring(config.Version or "?")))
    log(string.format("  KCDUtils=%s registered=%s ready=%s gameStarted=%s",
        boolText(KCDUtils ~= nil), boolText(WB._registered), boolText(WB._ready),
        tostring(KCDUtils and KCDUtils.HasGameStarted)))
    log(string.format("  player=%s inventory=%s LuaDB=%s dryRun=%s trackMode=%s",
        boolText(playerEntity ~= nil), boolText(inventory ~= nil), boolText(db ~= nil),
        tostring(config.DryRun), tostring(config.TrackMode)))
    log(string.format("  potionFamilies=%d potionIndex=%d whitelist=%d",
        countKeys(config.PotionFamilies), countKeys(WB._PotionIndex), countKeys(config.PotionWhitelist)))
    log(string.format("  bootstrapEnabled=%s bootstrapFlag=%s bootstrapComplete=%s",
        tostring(bootstrap.enable), bootstrapFlag, boolText(migrationValue ~= nil)))
    log(string.format("  worldTime=%s source=%s os.time=%s",
        Dev.FormatWorldTime(worldTime), tostring(worldSource), tostring(os.time())))
    log(string.format("  devSpawnEnabled=%s maxSpawnQuantity=%s",
        tostring(devConfig.allow_spawn_commands), tostring(devConfig.max_spawn_quantity)))
    log(string.format("  counters handshake=%d handshakeReplay=%d gameplayStarted=%d bindAll=%d transferOpen=%d transferClose=%d",
        tonumber(WB._handshakeCalls) or 0,
        tonumber(WB._handshakeReplayCalls) or 0,
        tonumber(WB._gameplayStartedCalls) or 0,
        tonumber(WB.Events and WB.Events._bindAllCalls) or 0,
        tonumber(WB._itemTransferOpenedCalls) or 0,
        tonumber(WB._itemTransferClosedCalls) or 0))
end

function Dev.Validate()
    if type(WB.BuildPotionIndex) == "function" then WB.BuildPotionIndex() end

    local config = WB.Config or {}
    local families = config.PotionFamilies or {}
    local whitelist = config.PotionWhitelist or {}
    local allowedBands = { water = true, wine = true, oil = true, spirit = true }
    local seen = {}
    local errors = 0
    local warnings = 0
    local familyCount = 0
    local idCount = 0

    local function addError(message)
        errors = errors + 1
        err(message)
    end

    local function addWarning(message)
        warnings = warnings + 1
        warn(message)
    end

    if config.TrackMode ~= "families" and config.TrackMode ~= "whitelist" then
        addError("TrackMode must be 'families' or 'whitelist'; got " .. tostring(config.TrackMode))
    end

    for family, data in pairs(families) do
        familyCount = familyCount + 1
        if type(data) ~= "table" then
            addError("Family " .. tostring(family) .. " is not a table")
        else
            if not allowedBands[data.band] then
                addError(string.format("Family %s has invalid decay band %s", tostring(family), tostring(data.band)))
            end

            local ids = data.ids
            if type(ids) ~= "table" or #ids == 0 then
                addError("Family " .. tostring(family) .. " has no tier UUIDs")
            else
                if #ids < 4 then
                    addWarning(string.format("Family %s has %d tier(s); it cannot support the full IV -> I chain",
                        tostring(family), #ids))
                end

                for tier, classId in ipairs(ids) do
                    idCount = idCount + 1
                    if type(classId) ~= "string" or classId == "" then
                        addError(string.format("Family %s tier %d has an invalid UUID", tostring(family), tier))
                    elseif seen[classId] then
                        addError(string.format("Duplicate UUID %s in %s tier %d; first seen in %s tier %d",
                            classId, tostring(family), tier, seen[classId].family, seen[classId].tier))
                    else
                        seen[classId] = { family = tostring(family), tier = tier }
                    end

                    if config.TrackMode == "whitelist" and whitelist[classId] ~= true then
                        addWarning(string.format("Indexed UUID is not whitelisted: %s (%s tier %d)",
                            tostring(classId), tostring(family), tier))
                    end
                end
            end
        end
    end

    for classId in pairs(whitelist) do
        if not seen[classId] then
            addWarning("Whitelisted UUID is not present in PotionFamilies: " .. tostring(classId))
        end
    end

    local indexCount = countKeys(WB._PotionIndex)
    if indexCount ~= idCount then
        addError(string.format("Potion index count mismatch: index=%d familyIds=%d", indexCount, idCount))
    end

    if not (config.Bootstrap and type(config.Bootstrap.seed_age_days) == "table") then
        addWarning("Bootstrap seed_age_days is missing")
    end

    log(string.format("Validation complete: families=%d ids=%d index=%d whitelist=%d errors=%d warnings=%d",
        familyCount, idCount, indexCount, countKeys(whitelist), errors, warnings))
    return errors == 0, errors, warnings
end

function Dev.PrintTime()
    local worldTime, source = Dev.GetWorldTime()
    log(string.format("Game world time: raw=%s formatted=%s source=%s",
        tostring(worldTime), Dev.FormatWorldTime(worldTime), tostring(source)))
    log(string.format("Real/system time: os.time=%s", tostring(os.time())))

    if type(worldTime) ~= "number" then
        warn("World time API is unavailable. Do not implement aging until this is resolved.")
    end
end

function Dev.SpawnPotion(familyArg, tierArg, quantityArg)
    local config = WB.Config or {}
    local devConfig = config.Dev or {}
    if devConfig.allow_spawn_commands == false then
        err("Spawn commands are disabled by Config.Dev.allow_spawn_commands")
        return false
    end

    local family = normalizeFamily(familyArg)
    local tier = normalizeTier(tierArg or "1") or 1
    local quantity = math.floor(tonumber(quantityArg) or 1)
    local maxQuantity = math.max(1, math.floor(tonumber(devConfig.max_spawn_quantity) or 20))
    quantity = math.max(1, math.min(quantity, maxQuantity))

    if not family then
        err("Usage: wb_spawn <family> [tier 1-4 or i-iv] [quantity]")
        return false
    end

    local familyData = config.PotionFamilies and config.PotionFamilies[family]
    if not familyData then
        err("Unknown potion family: " .. tostring(family))
        return false
    end

    local classId = familyData.ids and familyData.ids[tier]
    if not classId then
        err(string.format("Family %s does not have tier %s", family, tostring(tier)))
        return false
    end

    local playerEntity = U and type(U.Player) == "function" and U.Player() or nil
    local inventory = getInventory(playerEntity)
    if not inventory then
        err("Player inventory is unavailable")
        return false
    end
    if type(inventory.CreateItem) ~= "function" then
        err("player.inventory:CreateItem is unavailable")
        return false
    end

    local before = getInventoryCount(inventory, classId)
    if before == nil then
        err("Could not read inventory count before spawning")
        return false
    end

    local health = tonumber(devConfig.spawn_health) or 1.0
    local target = before + quantity
    local current = before
    local attempts = 0
    local maxAttempts = quantity + 5

    while current < target and attempts < maxAttempts do
        attempts = attempts + 1

        local remaining = target - current
        local ok, result = pcall(
            inventory.CreateItem,
            inventory,
            classId,
            health,
            remaining
        )

        if not ok then
            err("CreateItem raised an error: " .. tostring(result))
            return false
        end

        local nextCount = getInventoryCount(inventory, classId)
        if nextCount == nil then
            err("CreateItem returned, but the inventory count could not be read")
            return false
        end

        if nextCount <= current then
            err(string.format(
                "CreateItem made no progress: family=%s tier=%d id=%s return=%s current=%d target=%d",
                family,
                tier,
                classId,
                tostring(result),
                current,
                target
            ))
            return false
        end

        current = nextCount
    end

    local after = current

    local added = after - before

    if added ~= quantity then
        err(string.format(
            "Spawn quantity mismatch: family=%s tier=%d requested=%d added=%d before=%d after=%d attempts=%d",
            family,
            tier,
            quantity,
            added,
            before,
            after,
            attempts
        ))
        return false
    end

    if Game and type(Game.ShowItemsTransfer) == "function" then
        pcall(Game.ShowItemsTransfer, classId, added)
    end

    log(string.format("Spawned family=%s tier=%d requested=%d added=%d id=%s before=%d after=%d",
        family, tier, quantity, added, classId, before, after))
    log("Inventory only: no cohort was created or modified.")
    return true, classId, added
end

function Dev.SpawnTestSet(tierArg, quantityArg)
    local config = WB.Config or {}
    local devConfig = config.Dev or {}
    local families = devConfig.test_families or {
        "marigold", "saviour_schnapps", "embrocation", "artemisia"
    }
    local tier = normalizeTier(tierArg or "1") or 1
    local quantity = math.floor(tonumber(quantityArg) or 1)
    local succeeded = 0
    local failed = 0

    log(string.format("Spawning test set: tier=%d quantity=%d", tier, quantity))
    for _, family in ipairs(families) do
        local ok = Dev.SpawnPotion(family, tier, quantity)
        if ok then succeeded = succeeded + 1 else failed = failed + 1 end
    end
    log(string.format("Test set complete: succeeded=%d failed=%d", succeeded, failed))
    return failed == 0
end
