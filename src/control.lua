require("common")

script.on_event(NEXT_INGREDIENTS_PERMUTATION_INPUT, function(event)
    change_fluid_recipe(event, NEXT_INGREDIENT_KEY)
end)
script.on_event(PREVIOUS_INGREDIENTS_PERMUTATION_INPUT, function(event)
    change_fluid_recipe(event, PREVIOUS_INGREDIENT_KEY)
end)
script.on_event(NEXT_RESULTS_PERMUTATION_INPUT, function(event)
    change_fluid_recipe(event, NEXT_RESULT_KEY)
end)

script.on_event(PREVIOUS_RESULTS_PERMUTATION_INPUT, function(event)
    change_fluid_recipe(event, PREVIOUS_RESULT_KEY)
end)

function change_fluid_recipe(event, change)
    local player = game.players[event.player_index]
    if not (player.selected and player.selected.type == "assembling-machine") then
        return
    end
    local building = player.selected
    local recipe = building.get_recipe()
    if not recipe then
        return
    end
    local recipePermutations = permutations[recipe.name]
    if not recipePermutations then
        return
    end
    local targetPermutation = recipePermutations[change]
    if not targetPermutation then
        return
    end
    local crafting_progress = building.crafting_progress
    local bonus_progress = building.bonus_progress
    local products_finished = building.products_finished

    local fluidsBefore = {}
    local fluidbox = building.fluidbox
    local start,stop
    if change <= PREVIOUS_INGREDIENT_KEY then
        start, stop, step = 1, recipePermutations.ingredientsFluidCount, 1
    else
        start, stop, step = #fluidbox, #fluidbox - recipePermutations.resultsFluidCount + 1, -1
    end

    for i = start, stop, step do
        if fluidbox[i] ~=nil then
            fluidsBefore[fluidbox[i].name] = fluidbox[i]
        end
    end

    building.set_recipe(targetPermutation.name) -- ignore leftovers, since the crafting progress will be set

    building.crafting_progress = crafting_progress
    building.bonus_progress = bonus_progress
    building.products_finished = products_finished

    for i = start, stop, step do
        local filter = fluidbox.get_filter(i)
        if filter ~= nil then
            local filterName = filter.name;
            local before = fluidsBefore[filterName]
            if before ~= nil then
                fluidbox[i] = before
                fluidsBefore[filterName] = nil
            end
        end
    end
    local k, v = next(fluidsBefore)
    if k ~= nil then
        for i = start, stop, step do
            if fluidbox.get_filter(i) == nil then
                fluidbox[i] = v;
                k, v = next(fluidsBefore, key)
                if k == nil then
                    break
                end
            end
        end
    end
end

local function togglePermutations(effects, force, enabled)
    for i = 1, #effects do
        local effect = effects[i]
        if effect.type == "unlock-recipe" then
            local otherRecipes = unlocks[effect.recipe]
            if otherRecipes ~= nil then
                for j = 1, #otherRecipes do
                    local recipe = force.recipes[otherRecipes[j]]
                    if recipe ~= nil then
                        recipe.enabled = enabled
                    end
                end
            end
        end
    end
end

script.on_event(defines.events.on_research_finished, function(event)
    local effects = event.research.effects
    local force = event.research.force
    togglePermutations(effects, force, true)
end)

local function handleForceTechnologyEffectsReset(force)
    for _, technology in pairs(force.technologies) do
        togglePermutations(technology.effects, force, technology.researched)
    end
end

script.on_event(defines.events.on_technology_effects_reset, function(event)
    handleForceTechnologyEffectsReset(event.force)
end)

script.on_event(defines.events.on_force_created, function(event)
    handleForceTechnologyEffectsReset(event.force)
end)

script.on_event(defines.events.on_forces_merged, function(event)
    handleForceTechnologyEffectsReset(event.destination)
end)

function buildRegistry()
    local simpleMode = settings.startup["fluid-permutations-simple-mode"].value

    local reverseFactorial = {
        [0] = 0, [1] = 2, [2] = 2, [5] = 3, [6] = 3, [23] = 4, [24] = 4, [119] = 5, [120] = 5,
        [719] = 6, [720] = 6, [5039] = 7, [5040] = 7, [40319] = 8, [40320] = 8 }

    local difficulty = game.difficulty_settings.recipe_difficulty
    -- n - normal - '0', e - expensive - '1', a - all - '-1'
    local difficultyMap = { n = 0, e = 1, a = -1}
    local fpPatternString = "%"..RECIPE_AFFIX.."%-d([ane])%-i(%d+)%-r(%d+)"
    local omnipermPattern = OMNIPERMUTE_AFFIX.."%-%d+-%d+"
    local groups = {}
    permutations = {}
    unlocks = {}

    for _, recipe in pairs(game.recipe_prototypes) do
        local start, _, recipeDifficulty, ingredientRotation, resultRotation = string.find(recipe.name, fpPatternString)
        if start then
            local omnipermuteStart = string.find(recipe.name, omnipermPattern)
            if omnipermuteStart then
                start = omnipermuteStart
            end
            local originalRecipeName = string.sub(recipe.name, 0, start - 1)
            if recipeDifficulty == "a" or difficultyMap[recipeDifficulty] == difficulty then
                local group = groups[originalRecipeName]
                if not group then
                    group = {
                        limits = {
                            maxI = 0,
                            maxR = 0,
                            difficulty = recipeDifficulty
                        }
                    }
                    groups[originalRecipeName] = group
                end

                ingredientRotation = tonumber(ingredientRotation)
                resultRotation = tonumber(resultRotation)

                group.limits.maxI = math.max(group.limits.maxI, ingredientRotation)
                group.limits.maxR = math.max(group.limits.maxR, resultRotation)

                group[recipe.name] = {
                    name = recipe.name,
                    groupName = originalRecipeName,
                    ingredientRotation = ingredientRotation,
                    resultRotation = resultRotation
                }
            end
        end
    end

    for name, group in pairs(groups) do
        local groupDifficulty

        local limits = group.limits
        group.limits = nil
        if limits.maxI == 0 and limits.maxR == 1 then
            limits.maxR = 2
        elseif limits.maxI == 1 and limits.maxR == 0 then
            limits.maxI = 2
        end

        local recipeUnlocks = {}

        local base = {
            name = name,
            groupName = name,
            ingredientRotation = limits.maxI,
            resultRotation = limits.maxR
        }
        local alternativeBaseName = functions.generateRecipeName(name, RECIPE_AFFIX, limits.difficulty, limits.maxI, limits.maxR)
        group[alternativeBaseName] = base

        local resultsFluidCount = 0
        local ingredientsFluidCount = 0
        resultsFluidCount = reverseFactorial[limits.maxR]
        ingredientsFluidCount = reverseFactorial[limits.maxI]
        for _, permutation in pairs(group) do

            recipeUnlocks[#recipeUnlocks + 1] = permutation.name

            if limits.maxR > 0 then
                local nextPermutationIndex
                if simpleMode and permutation.resultRotation < limits.maxR then
                    nextPermutationIndex = limits.maxR
                else
                    nextPermutationIndex = permutation.resultRotation % limits.maxR + 1
                end
                local nextPermutationName = functions.generateRecipeName(name, RECIPE_AFFIX, limits.difficulty, permutation.ingredientRotation, nextPermutationIndex)
                local r = group[nextPermutationName]

                permutation[NEXT_RESULT_KEY] = r
                r[PREVIOUS_RESULT_KEY] = permutation

                permutation.resultsFluidCount = resultsFluidCount
            end
            if limits.maxI > 0 then
                local nextPermutationIndex
                if simpleMode and permutation.ingredientRotation < limits.maxI then
                    nextPermutationIndex = limits.maxI
                else
                    nextPermutationIndex = permutation.ingredientRotation % limits.maxI + 1
                end
                local nextPermutationName = functions.generateRecipeName(name, RECIPE_AFFIX, limits.difficulty, nextPermutationIndex, permutation.resultRotation)
                local d = group[nextPermutationName]

                permutation[NEXT_INGREDIENT_KEY] = d
                d[PREVIOUS_INGREDIENT_KEY] = permutation

                permutation.ingredientsFluidCount = ingredientsFluidCount
            end
            permutations[permutation.name] = permutation
        end

        unlocks[name] = recipeUnlocks
    end
    global.permutations = permutations
    global.unlocks = unlocks
end

script.on_load(function()
    permutations = global.permutations
    unlocks = global.unlocks or {}
end)

script.on_configuration_changed(function(conf)
    buildRegistry()
    for _, force in pairs(game.forces) do
        handleForceTechnologyEffectsReset(force)
    end
end)

script.on_init( function(conf)
    buildRegistry()
end)
