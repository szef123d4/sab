local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- WEBHOOK URLs - REPLACE WITH YOUR ACTUAL WEBHOOKS
local WEBHOOK_URL_LOW = "https://discord.com/api/webhooks/1433203505740513401/87dI6dzUJJ8SX8P_INJAmhhuodKYAUWtTSMaRb4S_WUP-kx89bfnBtDNnlL6JroU4h3S"
local WEBHOOK_URL_HIGH = "https://discord.com/api/webhooks/1433203555631890552/OblORXzmJC0DhUSYlzn5mpTOcaDmUsiIyhrE9dVs9jFX87UDocrezJDHqaRyZ8OVVw4i"

local player = Players.LocalPlayer
local ALLOWED_PLACE_ID = 109983668079237
local isRunning = true

-- Simple notification function
local function showNotification(text)
    print("[ServerHopper] " .. text)
end

-- Extract money value from generation text
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

-- Get animal data from overhead
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

-- Find all animals in the server
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

-- Send webhook for animals
local function sendAnimalWebhooks()
    local animals = findAllAnimals()
    if #animals == 0 then return end
    
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
    
    if not bestAnimal then return end
    
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
    
    -- Format money value
    local moneyPerSecFormatted
    if bestAnimal.Value >= 1000000000 then
        moneyPerSecFormatted = string.format("💰 %.1fB/s", bestAnimal.Value / 1000000000)
    elseif bestAnimal.Value >= 1000000 then
        moneyPerSecFormatted = string.format("💰 %.1fM/s", bestAnimal.Value / 1000000000)
    elseif bestAnimal.Value >= 1000 then
        moneyPerSecFormatted = string.format("💰 %.1fK/s", bestAnimal.Value / 1000)
    else
        moneyPerSecFormatted = string.format("💰 %d/s", bestAnimal.Value)
    end

    -- Create embed
    local embed = {
        title = "🐾 **Brainrot Notify | KLPN Hub**",
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
                inline = true
            },
            {
                name = "**Category**",
                value = valueCategory == "HIGH" and "🔥 HIGH VALUE (10M+)" or "💰 LOW VALUE (0-10M)",
                inline = true
            },
            {
                name = "**Players**",
                value = string.format("👤 %d/%d", playersCount, Players.MaxPlayers),
                inline = true
            },
            {
                name = "**Job ID**",
                value = "```" .. jobId .. "```",
                inline = false
            },
            {
                name = "**Join Link**",
                value = "[Click to Join](https://www.roblox.com/games/" .. placeId .. "?jobId=" .. jobId .. ")",
                inline = false
            }
        },
        timestamp = DateTime.now():ToIsoDate(),
        footer = {
            text = "Made by KLPN Hub • " .. os.date("%m/%d/%Y %I:%M %p")
        }
    }
    
    local payload = {
        embeds = {embed},
        username = "KLPN Hub Notifier - " .. valueCategory,
        avatar_url = "https://cdn.discordapp.com/attachments/1128833213672656988/1215321493282160730/standard_1.gif"
    }
    
    -- Send webhook with error handling
    local success, result = pcall(function()
        local jsonPayload = HttpService:JSONEncode(payload)
        
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
        showNotification("Webhook sent: " .. bestAnimal.DisplayName .. " (" .. moneyPerSecFormatted .. ")")
    else
        showNotification("Webhook failed: " .. tostring(result))
    end
    
    return success
end

-- Get available servers
local function getAvailableServers()
    local servers = {}
    local cursor = ""
    local maxPages = 2
    
    for page = 1, maxPages do
        local url = "https://games.roblox.com/v1/games/" .. ALLOWED_PLACE_ID .. "/servers/Public?sortOrder=Desc&limit=100&excludeFullGames=true"
        if cursor ~= "" then url = url .. "&cursor=" .. cursor end
        
        local success, response = pcall(function() 
            return game:HttpGet(url)
        end)
        
        if not success then break end
        
        local body = HttpService:JSONDecode(response)
        if not body.data then break end
        
        for _, v in pairs(body.data) do
            if v.playing and v.maxPlayers and v.playing >= 2 and v.playing < v.maxPlayers and v.id ~= game.JobId then
                table.insert(servers, v.id)
            end
        end
        
        cursor = body.nextPageCursor or ""
        if cursor == "" then break end
    end
    
    return servers
end

-- Server hopping function
local function hopToNewServer()
    local servers = getAvailableServers()
    if #servers == 0 then
        showNotification("No servers found, retrying...")
        return false
    end
    
    local randomServer = servers[math.random(1, #servers)]
    showNotification("Hopping to server: " .. randomServer)
    
    local success, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(ALLOWED_PLACE_ID, randomServer, player)
    end)
    
    if not success then
        showNotification("Teleport failed: " .. tostring(err))
    end
    
    return success
end

-- Main loop
local function mainLoop()
    showNotification("Starting continuous server hopping...")
    
    while isRunning do
        -- Wait a bit for game to load
        task.wait(3)
        
        -- Send webhooks for current server
        local webhookSuccess = sendAnimalWebhooks()
        
        -- Wait for webhook to send (important!)
        if webhookSuccess then
            showNotification("Webhook sent, waiting before hopping...")
            task.wait(2) -- Wait 2 seconds to ensure webhook is delivered
        else
            task.wait(1) -- Shorter wait if webhook failed
        end
        
        -- Hop to new server
        local hopSuccess = hopToNewServer()
        
        if not hopSuccess then
            -- If hop failed, wait longer before retry
            showNotification("Hop failed, waiting 5 seconds before retry...")
            task.wait(5)
        else
            -- If hop succeeded, the script will restart in new server
            break
        end
    end
end

-- Auto-restart if hopping stops
local function keepAlive()
    while true do
        if not isRunning then
            showNotification("Restarting hopper...")
            isRunning = true
            task.wait(2)
            mainLoop()
        end
        task.wait(1)
    end
end

-- Start everything
showNotification("KLPN Hub Server Hopper Started!")
showNotification("Webhook LOW: 0-10M | Webhook HIGH: 10M+")
showNotification("Ignoring Lucky Block animals")

-- Start main loop and keep-alive
task.spawn(mainLoop)
task.spawn(keepAlive)

-- Emergency stop command (optional)
_G.StopHopper = function()
    isRunning = false
    showNotification("Hopper stopped by command")
end

showNotification("Use _G.StopHopper() to stop the hopper")
