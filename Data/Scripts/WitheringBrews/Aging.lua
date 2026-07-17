-- Withering Brews: pure potion-aging calculations
--
-- This module must remain independent of inventory and LuaDB.
-- It receives all data through arguments and returns a plan.

WitheringBrews = WitheringBrews or {}

local WB = WitheringBrews

WB.Aging = WB.Aging or {}

local A = WB.Aging

local TIER_NAMES = {
    [1] = "i",
    [2] = "ii",
    [3] = "iii",
    [4] = "iv",
}

local function isFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function isPositiveInteger(value)
    return isFiniteNumber(value)
        and value >= 1
        and math.floor(value) == value
end

local function isBootstrapSource(value)
    return type(value) == "string"
        and value:sub(1, 10) == "bootstrap:"
end

local function block(result, reason)
    result.status = "blocked"
    result.reason = tostring(reason)

    return result
end

local function getStageSeconds(rules, tier)
    if type(rules) ~= "table" then
        return nil
    end

    local durations = rules.stageSecondsByTier

    if type(durations) ~= "table" then
        return nil
    end

    local value = durations[tier]

    if value == nil then
        value = durations[TIER_NAMES[tier]]
    end

    value = tonumber(value)

    if not isFiniteNumber(value)
        or value <= 0
    then
        return nil
    end

    return value
end

function A.PlanCohort(
    familyName,
    familyData,
    sourceTier,
    cohort,
    currentTime,
    rules
)
    local result = {
        status = "blocked",
        reason = nil,

        family = familyName,
        band = nil,

        sourceTier = sourceTier,
        sourceClassId = nil,

        targetTier = nil,
        targetClassId = nil,

        qty = nil,

        originalCreatedAt = nil,
        targetCreatedAt = nil,

        originalSource = nil,

        elapsedSeconds = nil,
        consumedStageSeconds = nil,
        remainingAgeSeconds = nil,

        sourceStageSeconds = nil,
        targetStageSeconds = nil,

        tiersCrossed = 0,

        conditionRemaining = nil,
        conditionPercent = nil,

        terminalPolicy = nil,
        isTerminalTier = false,
        terminalExpired = false,
        terminalOverrunSeconds = 0,
    }

    if type(familyName) ~= "string"
        or familyName == ""
    then
        return block(
            result,
            "family name is missing"
        )
    end

    if type(familyData) ~= "table" then
        return block(
            result,
            "family data is missing"
        )
    end

    result.band = familyData.band

    local ids = familyData.ids

    if type(ids) ~= "table" then
        return block(
            result,
            "family ids are missing"
        )
    end

    sourceTier = tonumber(sourceTier)

    if not isPositiveInteger(sourceTier) then
        return block(
            result,
            "source tier must be a positive integer"
        )
    end

    result.sourceTier = sourceTier

    local sourceClassId = ids[sourceTier]

    if type(sourceClassId) ~= "string"
        or sourceClassId == ""
    then
        return block(
            result,
            ("source tier %d has no configured class ID")
                :format(sourceTier)
        )
    end

    result.sourceClassId = sourceClassId

    if type(cohort) ~= "table" then
        return block(
            result,
            "cohort is missing"
        )
    end

    local qty = cohort.qty
    local createdAt = cohort.created_at
    local source = cohort.source

    if not isPositiveInteger(qty) then
        return block(
            result,
            "cohort qty must be a positive integer"
        )
    end

    result.qty = qty

    if not isFiniteNumber(currentTime) then
        return block(
            result,
            "current time must be numeric"
        )
    end

    if not isFiniteNumber(createdAt) then
        return block(
            result,
            "created_at must be numeric"
        )
    end

    if createdAt < 0
        and not isBootstrapSource(source)
    then
        return block(
            result,
            "negative created_at requires bootstrap source"
        )
    end

    if createdAt > currentTime then
        return block(
            result,
            "created_at is in the future"
        )
    end

    if type(source) ~= "string"
        or source == ""
    then
        return block(
            result,
            "cohort source is missing"
        )
    end

    result.originalCreatedAt = createdAt
    result.originalSource = source

    local terminalPolicy =
        type(rules) == "table"
        and rules.terminalPolicy
        or nil

    terminalPolicy =
        terminalPolicy or "keep"

    result.terminalPolicy = terminalPolicy

    if terminalPolicy ~= "keep" then
        return block(
            result,
            "only terminal policy 'keep' is supported in Patch 3 Step 1"
        )
    end

    local sourceStageSeconds =
        getStageSeconds(
            rules,
            sourceTier
        )

    if not sourceStageSeconds then
        return block(
            result,
            ("missing or invalid duration for source tier %d")
                :format(sourceTier)
        )
    end

    result.sourceStageSeconds =
        sourceStageSeconds

    local elapsedSeconds =
        currentTime - createdAt

    local remainingAgeSeconds =
        elapsedSeconds

    local targetTier = sourceTier
    local tiersCrossed = 0

    while true do
        local stageSeconds =
            getStageSeconds(
                rules,
                targetTier
            )

        if not stageSeconds then
            return block(
                result,
                ("missing or invalid duration for tier %d")
                    :format(targetTier)
            )
        end

        if remainingAgeSeconds
            < stageSeconds
        then
            local conditionRemaining =
                1
                - (
                    remainingAgeSeconds
                    / stageSeconds
                )

            result.status =
                tiersCrossed > 0
                and "downgrade"
                or "stable"

            result.targetTier = targetTier
            result.targetClassId =
                ids[targetTier]

            result.elapsedSeconds =
                elapsedSeconds

            result.consumedStageSeconds =
                elapsedSeconds
                - remainingAgeSeconds

            result.remainingAgeSeconds =
                remainingAgeSeconds

            result.targetCreatedAt =
                currentTime
                - remainingAgeSeconds

            result.targetStageSeconds =
                stageSeconds

            result.tiersCrossed =
                tiersCrossed

            result.conditionRemaining =
                conditionRemaining

            result.conditionPercent =
                conditionRemaining * 100

            result.isTerminalTier =
                targetTier == 1

            return result
        end

        if targetTier > 1 then
            local lowerTier =
                targetTier - 1

            local lowerClassId =
                ids[lowerTier]

            if type(lowerClassId) ~= "string"
                or lowerClassId == ""
            then
                return block(
                    result,
                    ("missing lower-tier mapping: tier %d -> tier %d")
                        :format(
                            targetTier,
                            lowerTier
                        )
                )
            end

            remainingAgeSeconds =
                remainingAgeSeconds
                - stageSeconds

            targetTier = lowerTier
            tiersCrossed =
                tiersCrossed + 1
        else
            result.status = "terminal"

            result.targetTier = 1
            result.targetClassId = ids[1]

            result.elapsedSeconds =
                elapsedSeconds

            result.consumedStageSeconds =
                elapsedSeconds
                - remainingAgeSeconds

            result.remainingAgeSeconds =
                remainingAgeSeconds

            -- Time when this cohort entered Quality I.
            result.targetCreatedAt =
                currentTime
                - remainingAgeSeconds

            result.targetStageSeconds =
                stageSeconds

            result.tiersCrossed =
                tiersCrossed

            result.conditionRemaining = 0
            result.conditionPercent = 0

            result.isTerminalTier = true
            result.terminalExpired = true

            result.terminalOverrunSeconds =
                remainingAgeSeconds
                - stageSeconds

            return result
        end
    end
end

-- Pure synthetic test suite --------------------------------------------------

local function approximatelyEqual(
    left,
    right,
    tolerance
)
    tolerance = tolerance or 0.0001

    return math.abs(left - right)
        <= tolerance
end

function A.RunSelfTests()
    local currentTime = 1000

    local fourTierFamily = {
        band = "test",
        ids = {
            "tier-i",
            "tier-ii",
            "tier-iii",
            "tier-iv",
        },
    }

    local threeTierFamily = {
        band = "test",
        ids = {
            "tier-i",
            "tier-ii",
            "tier-iii",
        },
    }

    local oneTierFamily = {
        band = "test",
        ids = {
            "only-tier",
        },
    }

    local brokenFamily = {
        band = "test",
        ids = {
            [1] = "tier-i",
            [3] = "tier-iii",
        },
    }

    -- Lower qualities deliberately have shorter stages.
    local rules = {
        terminalPolicy = "keep",

        stageSecondsByTier = {
            [4] = 400,
            [3] = 300,
            [2] = 200,
            [1] = 100,
        },
    }

    local function cohortForAge(
        ageSeconds,
        source
    )
        return {
            qty = 2,
            created_at =
                currentTime - ageSeconds,

            source =
                source or "selftest",
        }
    end

    local tests = {}

    local function addTest(name, callback)
        tests[#tests + 1] = {
            name = name,
            callback = callback,
        }
    end

    addTest("fresh Quality IV is stable", function()
        local plan = A.PlanCohort(
            "test",
            fourTierFamily,
            4,
            cohortForAge(0),
            currentTime,
            rules
        )

        return plan.status == "stable"
            and plan.targetTier == 4
            and approximatelyEqual(
                plan.conditionPercent,
                100
            )
    end)

    addTest("just before Quality IV threshold", function()
        local plan = A.PlanCohort(
            "test",
            fourTierFamily,
            4,
            cohortForAge(399),
            currentTime,
            rules
        )

        return plan.status == "stable"
            and plan.targetTier == 4
            and plan.tiersCrossed == 0
    end)

    addTest("exact Quality IV threshold", function()
        local plan = A.PlanCohort(
            "test",
            fourTierFamily,
            4,
            cohortForAge(400),
            currentTime,
            rules
        )

        return plan.status == "downgrade"
            and plan.targetTier == 3
            and plan.tiersCrossed == 1
            and approximatelyEqual(
                plan.conditionPercent,
                100
            )
    end)

    addTest("Quality III uses its own duration", function()
        local plan = A.PlanCohort(
            "test",
            fourTierFamily,
            4,
            cohortForAge(550),
            currentTime,
            rules
        )

        return plan.status == "downgrade"
            and plan.targetTier == 3
            and plan.remainingAgeSeconds == 150
            and approximatelyEqual(
                plan.conditionPercent,
                50
            )
    end)

    addTest("multiple tiers carry overflow", function()
        local plan = A.PlanCohort(
            "test",
            fourTierFamily,
            4,
            cohortForAge(800),
            currentTime,
            rules
        )

        return plan.status == "downgrade"
            and plan.targetTier == 2
            and plan.tiersCrossed == 2
            and plan.remainingAgeSeconds == 100
            and approximatelyEqual(
                plan.conditionPercent,
                50
            )
    end)

    addTest("exact entry into Quality I", function()
        local plan = A.PlanCohort(
            "test",
            fourTierFamily,
            4,
            cohortForAge(900),
            currentTime,
            rules
        )

        return plan.status == "downgrade"
            and plan.targetTier == 1
            and plan.tiersCrossed == 3
            and approximatelyEqual(
                plan.conditionPercent,
                100
            )
    end)

    addTest("exact terminal expiry", function()
        local plan = A.PlanCohort(
            "test",
            fourTierFamily,
            4,
            cohortForAge(1000),
            currentTime,
            rules
        )

        return plan.status == "terminal"
            and plan.targetTier == 1
            and plan.terminalExpired == true
            and plan.terminalOverrunSeconds == 0
            and plan.conditionPercent == 0
    end)

    addTest("one-tier potion before expiry", function()
        local plan = A.PlanCohort(
            "test",
            oneTierFamily,
            1,
            cohortForAge(99),
            currentTime,
            rules
        )

        return plan.status == "stable"
            and plan.targetTier == 1
            and plan.terminalExpired == false
    end)

    addTest("one-tier potion at expiry", function()
        local plan = A.PlanCohort(
            "test",
            oneTierFamily,
            1,
            cohortForAge(100),
            currentTime,
            rules
        )

        return plan.status == "terminal"
            and plan.targetTier == 1
            and plan.terminalExpired == true
    end)

    addTest("three-tier family uses actual chain", function()
        local plan = A.PlanCohort(
            "test",
            threeTierFamily,
            3,
            cohortForAge(300),
            currentTime,
            rules
        )

        return plan.status == "downgrade"
            and plan.sourceTier == 3
            and plan.targetTier == 2
            and plan.tiersCrossed == 1
    end)

    addTest("missing lower-tier mapping blocks", function()
        local plan = A.PlanCohort(
            "test",
            brokenFamily,
            3,
            cohortForAge(300),
            currentTime,
            rules
        )

        return plan.status == "blocked"
            and type(plan.reason) == "string"
            and plan.reason:find(
                "missing lower%-tier mapping"
            ) ~= nil
    end)

    addTest("negative bootstrap timestamp is valid", function()
        local plan = A.PlanCohort(
            "test",
            fourTierFamily,
            4,
            {
                qty = 1,
                created_at = -300,
                source = "bootstrap:player",
            },
            100,
            rules
        )

        return plan.status == "downgrade"
            and plan.targetTier == 3
    end)

    addTest("negative normal timestamp blocks", function()
        local plan = A.PlanCohort(
            "test",
            fourTierFamily,
            4,
            {
                qty = 1,
                created_at = -300,
                source = "loot",
            },
            100,
            rules
        )

        return plan.status == "blocked"
    end)

    local passed = 0
    local failed = 0

    for _, test in ipairs(tests) do
        local callOk, testPassed =
            pcall(test.callback)

        if callOk and testPassed then
            passed = passed + 1

            System.LogAlways(
                "[WitheringBrews/AgingTest] PASS "
                .. test.name
            )
        else
            failed = failed + 1

            System.LogAlways(
                "[WitheringBrews/AgingTest] FAIL "
                .. test.name
            )
        end
    end

    System.LogAlways(
        ("[WitheringBrews/AgingTest] Summary passed=%d failed=%d writes=0")
            :format(
                passed,
                failed
            )
    )

    return failed == 0, {
        passed = passed,
        failed = failed,
        writes = 0,
    }
end