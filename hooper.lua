local Http = game:GetService("HttpService")
local TPS = game:GetService("TeleportService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

-- WEBHOOK URLs from script 1
local WEBHOOK_URL_LOW = "https://discord.com/api/webhooks/1433203505740513401/87dI6dzUJJ8SX8P_INJAmhhuodKYAUWtTSMaRb4S_WUP-kx89bfnBtDNnlL6JroU4h3S"
local WEBHOOK_URL_HIGH = "https://discord.com/api/webhooks/1433203555631890552/OblORXzmJC0DhUSYlzn5mpTOcaDmUsiIyhrE9dVs9jFX87UDocrezJDHqaRyZ8OVVw4i"

local player = Players.LocalPlayer
local ALLOWED_PLACE_ID = 109983668079237
local isRunning = true
local RETRY_DELAY = 0.1

-- Track if we've already sent webhook for current server
local currentServerJobId = nil
local webhookSentForCurrentServer = false

-- Server hopping API state from script 2
local apiState = {
    mainApiUses = 0,
    cachedServers = {},
    lastCacheUpdate = 0,
    useCachedServers = false
}

local settings = {
    minPlayers = 2,
    sortOrder = "Desc"
}

-- Extract money value from generation text (from script 1)
local function extractNumber(str)
    if not str then return 0 end
    local numberStr = str:match("%$(.-)/s")
    if not numberStr then return 0 end
    numberStr = numberStr:gsub("%s", "")
    local multiplier = 1
    if numberStr:lower():find("k") then
        multiplier = 1000
        numberStr = numberStr:gsub("[kK]", "")
    elseif numberStr:lower():find("m") then
        multiplier = 1000000
        numberStr = numberStr:gsub("[mM]", "")
    elseif numberStr:lower():find("b") then
        multiplier = 1000000000
        numberStr = numberStr:gsub("[bB]", "")
    end
    return (tonumber(numberStr) or 0) * multiplier
end

-- Get animal data from overhead (from script 1)
local function getAnimalData(overhead)
    if not overhead then return nil end
    
    local displayNameLabel = overhead:FindFirstChild("DisplayName")
    local genLabel = overhead:FindFirstChild("Generation")
    local rarityLabel = overhead:FindFirstChild("Rarity")
    
    if displayNameLabel and genLabel and rarityLabel then
        local genValue = extractNumber(genLabel.Text)
        return {
            DisplayName = displayNameLabel.Text,
            Value = genValue,
            Generation = genLabel.Text,
            Rarity = rarityLabel.Text
        }
    end
    return nil
end

-- Find all animals in the server (from script 1)
local function findAllAnimals()
    local animals = {}
    local plotsFolder = Workspace:FindFirstChild("Plots")
    if not plotsFolder then return animals end

    for _, plot in pairs(plotsFolder:GetDescendants()) do
        if plot.Name == "AnimalOverhead" and plot:IsA("BillboardGui") then
            local stolenLabel = plot:FindFirstChild("Stolen")
            local isStolen = stolenLabel and stolenLabel:IsA("TextLabel") and string.upper(stolenLabel.Text) == "FUSING"
            local displayNameLabel = plot:FindFirstChild("DisplayName")
            
            -- Skip Lucky Block animals
            if displayNameLabel and string.find(string.lower(displayNameLabel.Text), "lucky block") then
                continue
            end
            
            if displayNameLabel and not isStolen then
                local animalData = getAnimalData(plot)
                if animalData then
                    table.insert(animals, animalData)
                end
            end
        end
    end
    return animals
end

-- Send webhook for animals (from script 1) - with anti-spam protection
local function sendAnimalWebhooks()
    -- Check if we're in a new server
    if currentServerJobId ~= game.JobId then
        currentServerJobId = game.JobId
        webhookSentForCurrentServer = false
    end
    
    -- Don't send webhook if we already sent one for this server
    if webhookSentForCurrentServer then
        return false
    end
    
    local animals = findAllAnimals()
    if #animals == 0 then return false end
    
    local placeId = game.PlaceId
    local jobId = game.JobId
    local playersCount = #Players:GetPlayers()
    
    -- Find best animal for main webhook
    local bestAnimal = nil
    local bestValue = 0
    
    for _, animal in pairs(animals) do
        if animal.Value > bestValue then
            bestValue = animal.Value
            bestAnimal = animal
        end
    end
    
    if not bestAnimal then return false end
    
    -- Determine which webhook to use based on value
    local webhookUrl
    local valueCategory
    
    if bestAnimal.Value < 10000000 then -- 0-10M
        webhookUrl = WEBHOOK_URL_LOW
        valueCategory = "LOW"
    else -- 10M+
        webhookUrl = WEBHOOK_URL_HIGH
        valueCategory = "HIGH"
    end
    
    -- Format money value to match the image format (16.5M/s)
    local moneyPerSecFormatted
    if bestAnimal.Value >= 1000000000 then
        moneyPerSecFormatted = string.format("%.1fB/s", bestAnimal.Value / 1000000000)
    elseif bestAnimal.Value >= 1000000 then
        moneyPerSecFormatted = string.format("%.1fM/s", bestAnimal.Value / 1000000)
    elseif bestAnimal.Value >= 1000 then
        moneyPerSecFormatted = string.format("%.1fK/s", bestAnimal.Value / 1000)
    else
        moneyPerSecFormatted = string.format("%d/s", bestAnimal.Value)
    end

    -- Create embed matching the image format exactly
    local embed = {
        title = "# KLPN Hub Notifier API",
        description = "\n\n### Brainrot Notify | KLPN Hub",
        color = valueCategory == "HIGH" and 16711680 or 65280,
        fields = {
            {
                name = "**Name**",
                value = bestAnimal.DisplayName,
                inline = false
            },
            {
                name = "**Money per sec**",
                value = moneyPerSecFormatted,
                inline = false
            },
            {
                name = "**Players**",
                value = string.format("%d/%d", playersCount, Players.MaxPlayers),
                inline = false
            },
            {
                name = "**Job ID (Mobile)**",
                value = "```" .. jobId .. "```",
                inline = false
            },
            {
                name = "**Job ID (PC)**",
                value = "```" .. jobId .. "```",
                inline = false
            },
            {
                name = "**Join Link**",
                value = "[Click to Join](https://www.roblox.com/games/" .. placeId .. "?jobId=" .. jobId .. ")",
                inline = false
            },
            {
                name = "**Join Script (PC)**",
                value = "```game:GetService(\"TeleportService\"):TeleportToPlaceInstance(" .. placeId .. ",\"" .. jobId .. "\", game.Players.LocalPlayer)```",
                inline = false
            }
        },
        timestamp = DateTime.now():ToIsoDate(),
        footer = {
            text = "Made by KLPN Hub • " .. os.date("%m/%d/%Y %I:%M %p") .. " • Dzi6 o " .. os.date("%H:%M")
        }
    }
    
    local payload = {
        embeds = {embed},
        username = "KLPN Hub Notifier",
        avatar_url = "https://cdn.discordapp.com/attachments/1128833213672656988/1215321493282160730/standard_1.gif"
    }
    
    -- Send webhook with error handling
    local success, result = pcall(function()
        local jsonPayload = Http:JSONEncode(payload)
        
        if syn and syn.request then
            return syn.request({
                Url = webhookUrl,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json"
                },
                Body = jsonPayload
            })
        elseif request then
            return request({
                Url = webhookUrl,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json"
                },
                Body = jsonPayload
            })
        else
            return game:HttpGetAsync(webhookUrl, jsonPayload)
        end
    end)
    
    if success then
        webhookSentForCurrentServer = true  -- Mark as sent for this server
    end
    
    return success
end

-- Server hopping functions from script 2
local function checkAPIAvailability()
    local mainAPI = "https://games.roblox.com/v1/games/" .. ALLOWED_PLACE_ID .. "/servers/Public?sortOrder=" .. settings.sortOrder .. "&limit=100&excludeFullGames=true"
    local success, response = pcall(function() return game:HttpGet(mainAPI) end)
    return success and response ~= ""
end

local function getServersFromAPI(baseUrl, isMainAPI)
    local servers = {}
    local cursor = ""
    local maxPages = 3
    
    if isMainAPI then
        apiState.mainApiUses = apiState.mainApiUses + 1
    end
    
    for page = 1, maxPages do
        local url = baseUrl
        if cursor ~= "" then url = url .. "&cursor=" .. cursor end
        
        local success, response = pcall(function() return game:HttpGet(url) end)
        if not success then break end
        
        local body = Http:JSONDecode(response)
        if not body.data then break end
        
        for _, v in body.data do
            if v.playing and v.maxPlayers and v.playing >= settings.minPlayers and v.playing < v.maxPlayers and v.id ~= game.JobId then
                table.insert(servers, v.id)
                if not table.find(apiState.cachedServers, v.id) then
                    table.insert(apiState.cachedServers, v.id)
                end
            end
        end
        
        cursor = body.nextPageCursor or ""
        if cursor == "" then break end
    end
    
    while #apiState.cachedServers > 300 do
        table.remove(apiState.cachedServers, 1)
    end
    
    apiState.lastCacheUpdate = tick()
    return servers
end

local function getCachedServers()
    local availableServers = {}
    
    for _, serverId in ipairs(apiState.cachedServers) do
        if serverId ~= game.JobId then
            table.insert(availableServers, serverId)
        end
    end
    
    return availableServers
end

local function getAvailableServers()
    if apiState.mainApiUses >= 3 or apiState.useCachedServers then
        if not checkAPIAvailability() then
            apiState.useCachedServers = true
            return getCachedServers()
        else
            apiState.useCachedServers = false
            apiState.mainApiUses = 0
        end
    end
    
    local mainAPI = "https://games.roblox.com/v1/games/" .. ALLOWED_PLACE_ID .. "/servers/Public?sortOrder=" .. settings.sortOrder .. "&limit=100&excludeFullGames=true"
    local servers = getServersFromAPI(mainAPI, true)
    
    if #servers > 0 then return servers end
    
    apiState.useCachedServers = true
    return getCachedServers()
end

local function tryTeleportWithRetries()
    if not isRunning then
        return
    end

    local attempts = 0
    local maxAttempts = 5
    while attempts < maxAttempts and isRunning do
        local servers = getAvailableServers()
        if #servers == 0 then
            task.wait(RETRY_DELAY)
            attempts = attempts + 1
            continue
        end
        local randomServer = servers[math.random(1, #servers)]
        local success, err = pcall(function()
            TPS:TeleportToPlaceInstance(ALLOWED_PLACE_ID, randomServer)
        end)
        if success then
            return
        else
            if not isRunning then
                return
            end
            task.wait(RETRY_DELAY)
            attempts = attempts + 1
        end
    end
    if isRunning then
        isRunning = false
    end
end

-- Main loop with webhooks integrated
local function runServerCheck()
    if not isRunning then return end
    
    -- Send webhooks for current server (only once per server)
    local webhookSuccess = sendAnimalWebhooks()
    
    if webhookSuccess then
        task.wait(0.5)
    else
        task.wait(1)
    end
    
    if not isRunning then return end
    
    -- Hop to new server
    tryTeleportWithRetries()
end

-- Main loop with EXACT timing from script 2
local function mainLoop()
    while isRunning do
        -- Wait for game to load
        task.wait(0.1)
        
        runServerCheck()
        
        if not isRunning then
            break
        end
    end
end

-- Auto-restart if hopping stops
local function keepAlive()
    while true do
        if not isRunning then
            isRunning = true
            task.wait(2)
            mainLoop()
        end
        task.wait(1)
    end
end

-- Start everything
task.spawn(mainLoop)
task.spawn(keepAlive)

-- Emergency stop command
_G.StopHopper = function()
    isRunning = false
end
